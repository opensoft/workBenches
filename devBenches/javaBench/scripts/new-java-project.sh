#!/bin/bash

# Java DevContainer Project Creation Script
# Creates a new Java project with development container setup

set -e

PROJECT_NAME=$1
TARGET_DIR=$2

# Validate project name is provided
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: ./new-java-project.sh <project-name> [target-directory]"
    echo "Examples:"
    echo "  ./new-java-project.sh myapp                    # Creates ~/projects/myapp"
    echo "  ./new-java-project.sh myapp ../../MyProjects  # Creates ../../MyProjects/myapp"
    echo ""
    echo "This script will:"
    echo "  1. Create a new Java Spring Boot project"
    echo "  2. Copy DevContainer and VS Code configurations"
    echo "  3. Set up Maven build configuration"
    echo "  4. Configure Docker for development"
    echo ""
    exit 1
fi

# If no target directory specified, default to ~/projects/<project-name>
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/projects"
    PROJECT_PATH="$TARGET_DIR/$PROJECT_NAME"
    
    # Check if project already exists
    if [ -d "$PROJECT_PATH" ]; then
        echo "❌ Error: Project already exists at $PROJECT_PATH"
        echo "Please choose a different project name or remove the existing project."
        exit 1
    fi
    
    # Create the target directory if it doesn't exist
    if [ ! -d "$TARGET_DIR" ]; then
        echo "📁 Creating projects directory: $TARGET_DIR"
        mkdir -p "$TARGET_DIR"
    fi
else
    PROJECT_PATH="$TARGET_DIR/$PROJECT_NAME"
    
    # Check if project already exists in specified directory
    if [ -d "$PROJECT_PATH" ]; then
        echo "❌ Error: Project already exists at $PROJECT_PATH"
        echo "Please choose a different project name or remove the existing project."
        exit 1
    fi
fi

echo "☕ Creating Java Spring Boot project: $PROJECT_NAME"
echo "📍 Project path: $PROJECT_PATH"

# Create project directory
mkdir -p "$PROJECT_PATH"
cd "$PROJECT_PATH"

# Create Maven project structure
echo "📋 Creating Java project structure..."
mkdir -p src/main/java/com/example/$PROJECT_NAME
mkdir -p src/main/resources
mkdir -p src/test/java/com/example/$PROJECT_NAME

# Create pom.xml
cat > pom.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.1.5</version>
        <relativePath/> <!-- lookup parent from repository -->
    </parent>
    <groupId>com.example</groupId>
    <artifactId>$PROJECT_NAME</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>$PROJECT_NAME</name>
    <description>Spring Boot project for $PROJECT_NAME</description>
    <properties>
        <java.version>17</java.version>
    </properties>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-devtools</artifactId>
            <scope>runtime</scope>
            <optional>true</optional>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
EOF

# Create main application class
PROJECT_CLASS=$(echo "$PROJECT_NAME" | sed 's/.*/\L&/; s/[a-z]/\U&/')
cat > "src/main/java/com/example/$PROJECT_NAME/${PROJECT_CLASS}Application.java" << EOF
package com.example.$PROJECT_NAME;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ${PROJECT_CLASS}Application {

    public static void main(String[] args) {
        SpringApplication.run(${PROJECT_CLASS}Application.class, args);
    }

}
EOF

# Create a simple controller
cat > "src/main/java/com/example/$PROJECT_NAME/HelloController.java" << EOF
package com.example.$PROJECT_NAME;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    @GetMapping("/")
    public String hello() {
        return "Hello from $PROJECT_NAME!";
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }
}
EOF

# Create test class
cat > "src/test/java/com/example/$PROJECT_NAME/${PROJECT_CLASS}ApplicationTests.java" << EOF
package com.example.$PROJECT_NAME;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class ${PROJECT_CLASS}ApplicationTests {

    @Test
    void contextLoads() {
    }

}
EOF

# Create application.properties
cat > src/main/resources/application.properties << EOF
# Server configuration
server.port=8080

# Application name
spring.application.name=$PROJECT_NAME

# Development profile
spring.profiles.active=dev
EOF

# Create README.md
cat > README.md << EOF
# $PROJECT_NAME

A Java Spring Boot project with development container setup.

## Getting Started

This project uses VS Code DevContainers for a consistent development environment.

### Prerequisites

- Docker Desktop
- VS Code with Remote-Containers extension

### Development Setup

1. Open this project in VS Code
2. When prompted, click "Reopen in Container"
3. Wait for the container to build (first time: ~5-10 minutes)
4. Start developing!

### Project Structure

\`\`\`
├── src/
│   ├── main/
│   │   ├── java/com/example/$PROJECT_NAME/
│   │   └── resources/
│   └── test/java/com/example/$PROJECT_NAME/
├── pom.xml
└── README.md
\`\`\`

### Available Commands

- \`mvn spring-boot:run\` - Run the application
- \`mvn test\` - Run tests
- \`mvn package\` - Build JAR file
- \`mvn clean\` - Clean build artifacts

### API Endpoints

- \`GET /\` - Hello endpoint
- \`GET /health\` - Health check endpoint

## Development

This project uses:

- Java 17
- Spring Boot 3.1.5
- Maven for build management
- JUnit 5 for testing

## License

This project is licensed under the MIT License.
EOF

# Create basic .gitignore
cat > .gitignore << EOF
target/
!.mvn/wrapper/maven-wrapper.jar
!**/src/main/**/target/
!**/src/test/**/target/

### STS ###
.apt_generated
.classpath
.factorypath
.project
.settings
.springBeans
.sts4-cache

### IntelliJ IDEA ###
.idea
*.iws
*.iml
*.ipr

### NetBeans ###
/nbproject/private/
/nbbuild/
/dist/
/nbdist/
/.nb-gradle/
build/
!**/src/main/**/build/
!**/src/test/**/build/

### VS Code ###
.vscode/

### DevContainer ###
.devcontainer/docker-compose.override.yml
EOF

echo ""
echo "✅ Java Spring Boot project created successfully: $PROJECT_PATH"
echo ""
echo "📝 Next steps:"
echo "   1. cd $PROJECT_PATH"
echo "   2. code ."
echo "   3. When prompted, click 'Reopen in Container'"
echo "   4. Wait for container build (first time: ~5-10 minutes)"
echo "   5. Container will automatically:"
echo "      - Install Java 17 and Maven"
echo "      - Download dependencies"
echo "      - Set up development environment"
echo ""
echo "☕ Development commands:"
echo "   - mvn spring-boot:run    : Run application"
echo "   - mvn test              : Run tests"
echo "   - mvn package           : Build JAR"
echo ""
echo "🌐 Application will be available at: http://localhost:8080"
echo ""
echo "🎯 Happy Java Development with Spec-Driven Development!"