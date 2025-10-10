#!/bin/bash

# C++ DevContainer Project Creation Script
# Creates a new C++ project with development container setup

set -e

PROJECT_NAME=$1
TARGET_DIR=$2

# Validate project name is provided
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: ./new-cpp-project.sh <project-name> [target-directory]"
    echo "Examples:"
    echo "  ./new-cpp-project.sh myapp                    # Creates ~/projects/myapp"
    echo "  ./new-cpp-project.sh myapp ../../MyProjects  # Creates ../../MyProjects/myapp"
    echo ""
    echo "This script will:"
    echo "  1. Create a new C++ project with CMake"
    echo "  2. Copy DevContainer and VS Code configurations"
    echo "  3. Set up build system and dependencies"
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

echo "⚡ Creating C++ project: $PROJECT_NAME"
echo "📍 Project path: $PROJECT_PATH"

# Create project directory
mkdir -p "$PROJECT_PATH"
cd "$PROJECT_PATH"

# Create C++ project structure
echo "📋 Creating C++ project structure..."
mkdir -p src include tests build docs

# Create CMakeLists.txt
cat > CMakeLists.txt << EOF
cmake_minimum_required(VERSION 3.20)

project($PROJECT_NAME VERSION 1.0.0 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Set compiler flags
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# Set build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Include directories
include_directories(include)

# Add executable
add_executable(\${PROJECT_NAME} src/main.cpp)

# Optional: Add library if you have multiple source files
# add_library(\${PROJECT_NAME}_lib src/example.cpp)
# target_link_libraries(\${PROJECT_NAME} \${PROJECT_NAME}_lib)

# Optional: Enable testing
# enable_testing()
# add_subdirectory(tests)

# Installation
install(TARGETS \${PROJECT_NAME} DESTINATION bin)
EOF

# Create main.cpp
cat > src/main.cpp << EOF
#include <iostream>
#include <string>

int main() {
    std::string projectName = "$PROJECT_NAME";
    std::cout << "Hello from " << projectName << "!" << std::endl;
    std::cout << "Welcome to C++ development!" << std::endl;
    return 0;
}
EOF

# Create example header
cat > include/example.h << EOF
#ifndef EXAMPLE_H
#define EXAMPLE_H

#include <string>

namespace $PROJECT_NAME {
    class Example {
    public:
        Example();
        std::string getMessage() const;
        
    private:
        std::string message_;
    };
}

#endif // EXAMPLE_H
EOF

# Create example implementation
cat > src/example.cpp << EOF
#include "example.h"

namespace $PROJECT_NAME {
    Example::Example() : message_("Hello from Example class!") {}
    
    std::string Example::getMessage() const {
        return message_;
    }
}
EOF

# Create basic test (if using Google Test)
cat > tests/test_example.cpp << EOF
// Uncomment and modify this if you add Google Test
/*
#include <gtest/gtest.h>
#include "example.h"

TEST(ExampleTest, GetMessage) {
    $PROJECT_NAME::Example example;
    EXPECT_EQ(example.getMessage(), "Hello from Example class!");
}

int main(int argc, char **argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
*/

// Simple test without Google Test framework
#include <iostream>
#include <cassert>

int main() {
    std::cout << "Running basic tests..." << std::endl;
    
    // Add your tests here
    assert(true); // Example assertion
    
    std::cout << "All tests passed!" << std::endl;
    return 0;
}
EOF

# Create build script
cat > build.sh << EOF
#!/bin/bash
set -e

BUILD_TYPE=\${1:-Release}
BUILD_DIR="build/\$BUILD_TYPE"

echo "Building $PROJECT_NAME in \$BUILD_TYPE mode..."

# Create build directory
mkdir -p "\$BUILD_DIR"

# Configure with CMake
cd "\$BUILD_DIR"
cmake -DCMAKE_BUILD_TYPE=\$BUILD_TYPE ../../

# Build
make -j\$(nproc)

echo "Build complete! Executable: \$BUILD_DIR/$PROJECT_NAME"
EOF

chmod +x build.sh

# Create README.md
cat > README.md << EOF
# $PROJECT_NAME

A C++ project with development container setup.

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
├── src/                 # Source files
│   ├── main.cpp
│   └── example.cpp
├── include/             # Header files
│   └── example.h
├── tests/               # Test files
│   └── test_example.cpp
├── build/               # Build artifacts (generated)
├── docs/                # Documentation
├── CMakeLists.txt       # CMake configuration
├── build.sh            # Build script
└── README.md           # This file
\`\`\`

### Building the Project

#### Using the build script (recommended):
\`\`\`bash
./build.sh                # Release build
./build.sh Debug          # Debug build
\`\`\`

#### Manual CMake build:
\`\`\`bash
mkdir -p build/Release
cd build/Release
cmake -DCMAKE_BUILD_TYPE=Release ../../
make -j\$(nproc)
\`\`\`

### Running the Project

After building:
\`\`\`bash
./build/Release/$PROJECT_NAME
\`\`\`

### Available Commands

- \`./build.sh\` - Build the project (Release mode)
- \`./build.sh Debug\` - Build in debug mode
- \`make clean\` - Clean build artifacts (from build directory)

### Development Features

This project includes:

- C++20 standard
- CMake build system
- Proper project structure
- Example class and header
- Basic testing setup
- Compiler warnings enabled
- Cross-platform compatibility

## Adding Dependencies

To add external libraries, modify \`CMakeLists.txt\`:

\`\`\`cmake
# Example: Adding a library
find_package(SomeLibrary REQUIRED)
target_link_libraries(\${PROJECT_NAME} SomeLibrary::SomeLibrary)
\`\`\`

## License

This project is licensed under the MIT License.
EOF

# Create basic .gitignore
cat > .gitignore << EOF
# Build artifacts
build/
*.o
*.a
*.so
*.exe

# CMake
CMakeCache.txt
CMakeFiles/
cmake_install.cmake
Makefile
*.cmake
!CMakeLists.txt

# IDE files
.vscode/settings.json
.idea/
*.swp
*.swo

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# DevContainer
.devcontainer/docker-compose.override.yml
EOF

echo ""
echo "✅ C++ project created successfully: $PROJECT_PATH"
echo ""
echo "📝 Next steps:"
echo "   1. cd $PROJECT_PATH"
echo "   2. code ."
echo "   3. When prompted, click 'Reopen in Container'"
echo "   4. Wait for container build (first time: ~5-10 minutes)"
echo "   5. Container will automatically:"
echo "      - Install C++ compiler (GCC/Clang)"
echo "      - Install CMake and build tools"
echo "      - Set up development environment"
echo ""
echo "⚡ Development commands:"
echo "   - ./build.sh            : Build project (Release)"
echo "   - ./build.sh Debug      : Build project (Debug)"
echo "   - ./build/Release/$PROJECT_NAME  : Run application"
echo ""
echo "🛠️  Project features:"
echo "   - C++20 standard"
echo "   - CMake build system"
echo "   - Example class structure"
echo "   - Basic testing setup"
echo ""
echo "🎯 Happy C++ Development with Spec-Driven Development!"