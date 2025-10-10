#!/bin/bash

# Post-Create Script for C++ Heavy Development Environment
# This script runs after the container is created to set up the development environment

set -e

echo "🔧 Setting up C++ Heavy Development Environment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Update package lists
print_status "Updating package lists..."
sudo apt-get update

# Install additional development tools that might be needed
print_status "Installing additional development tools..."
sudo apt-get install -y \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# Set up git configuration placeholders
print_status "Setting up Git configuration..."
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "code --wait"

# Set up vcpkg integration
print_status "Setting up vcpkg integration..."
if [ -d "/opt/vcpkg" ]; then
    /opt/vcpkg/vcpkg integrate install
    print_success "vcpkg integration completed"
else
    print_warning "vcpkg not found, skipping integration"
fi

# Set up conan profile
print_status "Setting up Conan profile..."
if command -v conan &> /dev/null; then
    conan profile detect --force
    print_success "Conan profile created"
else
    print_warning "Conan not found, skipping profile setup"
fi

# Create sample project structure
print_status "Creating sample project structure..."
mkdir -p /workspace/projects/sample-cpp
mkdir -p /workspace/builds
mkdir -p /workspace/install
mkdir -p /workspace/tests

# Create a sample CMakeLists.txt
cat > /workspace/projects/sample-cpp/CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.16)
project(SampleCppProject VERSION 1.0.0 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Compiler-specific options
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(${PROJECT_NAME} PRIVATE
        -Wall -Wextra -Wpedantic
        -Wno-unused-parameter
    )
endif()

# Find packages
find_package(Threads REQUIRED)

# Create executable
add_executable(sample_app
    src/main.cpp
    src/hello.cpp
)

target_include_directories(sample_app PRIVATE
    include
)

target_link_libraries(sample_app PRIVATE
    Threads::Threads
)

# Enable testing
enable_testing()
find_package(GTest REQUIRED)

add_executable(sample_tests
    tests/test_hello.cpp
    src/hello.cpp
)

target_include_directories(sample_tests PRIVATE
    include
)

target_link_libraries(sample_tests PRIVATE
    GTest::GTest
    GTest::Main
    Threads::Threads
)

add_test(NAME SampleTests COMMAND sample_tests)
EOF

# Create sample source files
mkdir -p /workspace/projects/sample-cpp/src
mkdir -p /workspace/projects/sample-cpp/include
mkdir -p /workspace/projects/sample-cpp/tests

# Sample header file
cat > /workspace/projects/sample-cpp/include/hello.h << 'EOF'
#pragma once
#include <string>

namespace sample {
    std::string get_greeting(const std::string& name = "World");
    void print_greeting(const std::string& name = "World");
}
EOF

# Sample implementation file
cat > /workspace/projects/sample-cpp/src/hello.cpp << 'EOF'
#include "hello.h"
#include <iostream>

namespace sample {
    std::string get_greeting(const std::string& name) {
        return "Hello, " + name + "!";
    }

    void print_greeting(const std::string& name) {
        std::cout << get_greeting(name) << std::endl;
    }
}
EOF

# Sample main file
cat > /workspace/projects/sample-cpp/src/main.cpp << 'EOF'
#include "hello.h"
#include <iostream>
#include <vector>
#include <algorithm>

int main() {
    sample::print_greeting("C++ Developer");
    
    // Demonstrate modern C++20 features
    std::vector<int> numbers = {1, 2, 3, 4, 5};
    
    // Range-based for loop
    std::cout << "Numbers: ";
    for (const auto& num : numbers) {
        std::cout << num << " ";
    }
    std::cout << std::endl;
    
    // Lambda and algorithms
    auto doubled = std::vector<int>{};
    std::transform(numbers.begin(), numbers.end(), std::back_inserter(doubled),
                   [](int n) { return n * 2; });
    
    std::cout << "Doubled: ";
    for (const auto& num : doubled) {
        std::cout << num << " ";
    }
    std::cout << std::endl;
    
    return 0;
}
EOF

# Sample test file
cat > /workspace/projects/sample-cpp/tests/test_hello.cpp << 'EOF'
#include <gtest/gtest.h>
#include "hello.h"

TEST(HelloTest, BasicGreeting) {
    EXPECT_EQ(sample::get_greeting("Test"), "Hello, Test!");
}

TEST(HelloTest, DefaultGreeting) {
    EXPECT_EQ(sample::get_greeting(), "Hello, World!");
}

TEST(HelloTest, EmptyName) {
    EXPECT_EQ(sample::get_greeting(""), "Hello, !");
}
EOF

# Create build script
cat > /workspace/projects/sample-cpp/build.sh << 'EOF'
#!/bin/bash
set -e

BUILD_DIR="../builds/sample-cpp"
INSTALL_DIR="../install/sample-cpp"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure
cmake ../../projects/sample-cpp \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# Build
cmake --build . --parallel $(nproc)

# Test
ctest --output-on-failure

echo "Build completed successfully!"
echo "Run the sample app: $BUILD_DIR/sample_app"
echo "Run tests: $BUILD_DIR/sample_tests"
EOF

chmod +x /workspace/projects/sample-cpp/build.sh

# Create .clang-format file
cat > /workspace/projects/sample-cpp/.clang-format << 'EOF'
---
Language: Cpp
BasedOnStyle: Google
IndentWidth: 4
TabWidth: 4
UseTab: Never
ColumnLimit: 100
AccessModifierOffset: -2
AlignAfterOpenBracket: Align
AlignConsecutiveAssignments: false
AlignConsecutiveDeclarations: false
AlignOperands: true
AllowAllParametersOfDeclarationOnNextLine: true
AllowShortBlocksOnASingleLine: false
AllowShortCaseLabelsOnASingleLine: false
AllowShortFunctionsOnASingleLine: All
AllowShortIfStatementsOnASingleLine: true
AllowShortLoopsOnASingleLine: true
BinPackArguments: true
BinPackParameters: true
BreakBeforeBinaryOperators: None
BreakBeforeBraces: Attach
BreakBeforeTernaryOperators: true
BreakConstructorInitializersBeforeComma: false
KeepEmptyLinesAtTheStartOfBlocks: false
MaxEmptyLinesToKeep: 1
NamespaceIndentation: None
ObjCBlockIndentWidth: 2
ObjCSpaceAfterProperty: false
ObjCSpaceBeforeProtocolList: false
PenaltyBreakBeforeFirstCallParameter: 1
PenaltyBreakComment: 300
PenaltyBreakString: 1000
PenaltyExcessCharacter: 1000000
PenaltyReturnTypeOnItsOwnLine: 200
PointerAlignment: Left
SpaceAfterCStyleCast: false
SpaceBeforeAssignmentOperators: true
SpaceBeforeParens: ControlStatements
SpaceInEmptyParentheses: false
SpacesBeforeTrailingComments: 2
SpacesInAngles: false
SpacesInContainerLiterals: true
SpacesInCStyleCastParentheses: false
SpacesInParentheses: false
SpacesInSquareBrackets: false
Standard: Auto
EOF

print_success "Sample C++ project created in /workspace/projects/sample-cpp"

# Display environment information
print_status "Development Environment Information:"
echo "=================================="
echo "GCC Version: $(gcc --version | head -n1)"
echo "Clang Version: $(clang --version | head -n1)"
echo "CMake Version: $(cmake --version | head -n1)"
echo "Python Version: $(python3 --version)"
echo "Git Version: $(git --version)"

if command -v vcpkg &> /dev/null; then
    echo "vcpkg Version: $(vcpkg version)"
fi

if command -v conan &> /dev/null; then
    echo "Conan Version: $(conan --version)"
fi

print_success "Post-create setup completed!"
print_status "Ready for heavy C++ development! 🚀"
print_status "Sample project available at: /workspace/projects/sample-cpp"
print_status "Run 'cd /workspace/projects/sample-cpp && ./build.sh' to build the sample project"