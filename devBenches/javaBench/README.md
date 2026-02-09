# Java Development Bench

A comprehensive Java development environment using layered Docker containers.

## Features

### Java Development Stack
- **OpenJDK 21** (LTS version)
- **Maven** - Dependency management and build tool
- **Gradle 8.5** - Modern build automation
- **Spring Boot CLI** - Spring application scaffolding
- **SDKMan** - Java version management

### Development Tools
- Git, Docker, and common development utilities (from base layer)
- VS Code Java extension pack support
- Maven and Gradle caching for faster builds
- Persistent M2 repository at `/workspace/m2repo`

### Ports
- `8080` - Spring Boot default port
- `8081` - Alternative web application port
- `5005` - Java remote debugging port
- `9090` - Metrics/Actuator endpoints

## Quick Start

### 1. Build the Image

```bash
./scripts/build-layer.sh
```

This will:
- Check for `devbench-base:${USER}` (build if needed)
- Build the Java-specific layer (`java-bench:${USER}`)

### 2. Start the Container

```bash
./setup.sh
```

### 3. Open in VS Code

```bash
code .
```

Then select "Reopen in Container" from the command palette.

## Architecture

### Layered Build System
- **Layer 1** (`devbench-base`): Common development tools
- **Layer 2** (`java-bench`): Java-specific packages and tools

Benefits:
- Faster rebuilds (only Layer 2 changes)
- Shared base across all benches
- Better Docker layer caching

## Usage

### Maven Projects

```bash
# Create new Maven project
mvn archetype:generate -DgroupId=com.example -DartifactId=my-app

# Build and package
mvn-package  # alias for: mvn clean package

# Run tests
mvn-test
```

### Gradle Projects

```bash
# Create new Gradle project
gradle init

# Build project
gradle-build  # alias for: gradle build

# Run tests
gradle-test
```

### Spring Boot Projects

```bash
# Create new Spring Boot project
spring init --dependencies=web,data-jpa my-spring-app

# Run Spring Boot application
spring-run  # alias for: ./mvnw spring-boot:run
```

### SDKMan

```bash
# List available Java versions
sdk list java

# Install a specific Java version
sdk install java 17.0.9-tem

# Switch Java version
sdk use java 17.0.9-tem
```

## Directory Structure

```
/workspace/
├── projects/      # Your Java projects
├── m2repo/        # Maven repository cache
└── .gradle/       # Gradle cache
```

## Configuration

### Maven Settings
Maven is configured to use `/workspace/m2repo` for the local repository, persisting dependencies across container restarts.

### Environment Variables
- `JAVA_HOME`: `/usr/lib/jvm/java-21-openjdk-amd64`
- `GRADLE_HOME`: `/opt/gradle/gradle-8.5`
- `MAVEN_OPTS`: `-Dmaven.repo.local=/workspace/m2repo`

## Useful Aliases

- `mvn-clean` - Clean Maven project
- `mvn-package` - Clean and package
- `mvn-install` - Clean and install
- `mvn-test` - Run tests
- `gradle-build` - Build Gradle project
- `gradle-clean` - Clean Gradle project
- `gradle-test` - Run Gradle tests
- `spring-run` - Run Spring Boot app

## Troubleshooting

### Container won't start
```bash
# Check if image exists
docker images | grep java-bench

# Rebuild if needed
./scripts/build-layer.sh
```

### Maven dependencies not downloading
```bash
# Check Maven settings
cat ~/.m2/settings.xml

# Clear cache if needed
rm -rf /workspace/m2repo/*
```

### Java version issues
```bash
# Verify Java version
java -version

# Check JAVA_HOME
echo $JAVA_HOME
```

## Version Information

- Container Version: 1.0.0
- Base Image: devbench-base
- JDK Version: OpenJDK 21
- Maven Version: (from apt)
- Gradle Version: 8.5
- Spring Boot CLI: 3.2.0
