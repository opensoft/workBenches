# cppBench - Heavy C++ Development Environment

A comprehensive, containerized C++ development environment designed for serious C++ development with modern toolchains, package managers, and debugging tools.

## 🧱 Container Architecture (Layered)

cppBench follows the layered workBenches model:
- **Layer 0**: `workbench-base:{user}`
- **Layer 1a**: `devbench-base:{user}`
- **Layer 2**: `cpp-bench:{user}` (bench-specific tools)

### Legacy Note
The `.devcontainer/` directory in this repo is a **legacy monolithic setup** and is deprecated. The layered images are the source of truth going forward.

## 🚀 Features

### Compilers & Standards
- **GCC 12** - Latest stable GNU Compiler Collection
- **Clang 15** - Modern LLVM-based compiler with advanced diagnostics
- **C++20 Support** - Full support for the latest C++ standard
- **Multiple Standards** - C++11, C++14, C++17, C++20 support

### Build Systems
- **CMake 3.16+** - Modern build system generator
- **Ninja** - Fast, parallel build system
- **Make** - Traditional build system
- **Autotools** - Configure, make, install workflow

### Package Management
- **vcpkg** - Microsoft's C++ package manager
- **Conan 2.0** - Modern C++ package manager
- **System Packages** - Pre-installed development libraries

### Debugging & Profiling
- **GDB** - GNU Debugger with container debugging support
- **Valgrind** - Memory debugging and profiling suite
- **AddressSanitizer (ASan)** - Fast memory error detector
- **ThreadSanitizer (TSan)** - Data race detector
- **Strace/Ltrace** - System and library call tracers

### Static Analysis
- **Clang-Tidy** - Clang-based C++ linter
- **Clang-Format** - Code formatter
- **CppCheck** - Static analysis tool
- **Vera++** - Source code analyzer

### Testing Framework
- **Google Test (GTest)** - Unit testing framework
- **Google Mock (GMock)** - Mocking framework
- **CTest** - CMake integrated testing

### Development Tools
- **VS Code Extensions** - Full C++ development suite
- **Git & Git LFS** - Version control
- **Doxygen** - Documentation generation
- **Python 3** - Scripting and tool support

## 📁 Project Structure

```
cppBench/
├── .devcontainer/          # Legacy monolithic devcontainer (deprecated)
│   ├── Dockerfile          # Legacy container definition
│   ├── devcontainer.json   # VS Code devcontainer settings
│   ├── docker-compose.yml  # Multi-container orchestration
│   ├── post-create.sh      # Post-creation setup script
│   ├── BUILD_FIXES.md      # Troubleshooting guide
│   ├── .env                # Environment variables
│   └── .env.example        # Environment template
├── scripts/
│   ├── launch-devbench.sh  # Quick VS Code launcher (Linux/macOS)
│   ├── start-monster.ps1   # PowerShell launcher (Windows)
│   └── start-monster.sh    # Advanced shell launcher
├── .gitignore              # Comprehensive C++ gitignore
└── README.md               # This file
```

## 🚀 Getting Started

### Prerequisites

- **Docker Desktop** - For containerization
- **VS Code** - With Dev Containers extension (recommended)
- **Git** - For version control

### Quick Launch

#### Option 1: VS Code (Recommended)
```bash
# Clone and launch
git clone <your-repo-url>
cd cppBench
./scripts/launch-devbench.sh
```

#### Option 2: Shell Access
```bash
# Launch with direct shell access
./scripts/start-monster.sh --shell

# Or rebuild and launch
./scripts/start-monster.sh --rebuild --shell
```

#### Option 3: Windows PowerShell
```powershell
# Launch from PowerShell
.\scripts\start-monster.ps1

# Rebuild and launch
.\scripts\start-monster.ps1 -Rebuild
```

### First Run

1. **Image Build** - Build the layered images if they are missing
2. **VS Code Integration** - Extensions will install automatically
3. **Sample Project** - Ready-to-use C++20 sample project included
4. **Environment Setup** - All tools pre-configured and ready

## 📚 Sample Project

A complete sample project is included to demonstrate the environment:

```bash
# Navigate to sample project
cd /workspace/projects/sample-cpp

# Build and test
./build.sh

# Run the application
../builds/sample-cpp/sample_app

# Run tests
../builds/sample-cpp/sample_tests
```

### Sample Project Features
- **Modern C++20** syntax and features
- **CMake build system** with multiple targets
- **Google Test** unit tests
- **Clang-Format** configuration
- **Header/source separation**
- **Namespace organization**

## 🔧 Development Workflow

### Building Projects

#### CMake (Recommended)
```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
cmake --build . --parallel $(nproc)
```

#### With Ninja (Faster)
```bash
mkdir build && cd build
cmake .. -GNinja -DCMAKE_BUILD_TYPE=Debug
ninja
```

### Testing

#### Running Tests
```bash
# With CTest
ctest --output-on-failure

# Direct execution
./your_test_executable
```

#### Debugging Tests
```bash
gdb ./your_test_executable
(gdb) run
```

### Package Management

#### vcpkg
```bash
# Search for packages
vcpkg search boost

# Install packages
vcpkg install boost-system boost-filesystem

# In CMakeLists.txt
find_package(Boost REQUIRED COMPONENTS system filesystem)
```

#### Conan
```bash
# Create conanfile.txt
[requires]
boost/1.82.0

[generators]
CMakeDeps

# Install dependencies
conan install . --build=missing
```

### Debugging

#### GDB
```bash
gdb ./your_program
(gdb) set args arg1 arg2
(gdb) break main
(gdb) run
```

#### Valgrind
```bash
# Memory check
valgrind --tool=memcheck --leak-check=full ./your_program

# Performance profiling
valgrind --tool=callgrind ./your_program
```

#### AddressSanitizer
```bash
# Compile with ASan
cmake .. -DCMAKE_CXX_FLAGS="-fsanitize=address -g"
./your_program
```

### Static Analysis

#### Clang-Tidy
```bash
# Generate compile_commands.json
cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# Run analysis
clang-tidy src/*.cpp
```

#### CppCheck
```bash
cppcheck --enable=all --std=c++20 src/
```

## 🔍 Advanced Features

### Multiple Compiler Testing
```bash
# Switch to Clang
export CC=clang-15
export CXX=clang++-15
cmake .. -DCMAKE_BUILD_TYPE=Debug

# Switch back to GCC
export CC=gcc-12
export CXX=g++-12
```

### Cross-Platform Development
The environment supports development for multiple platforms with consistent tooling across Linux, macOS, and Windows hosts.

### Performance Optimization
- **Link Time Optimization (LTO)**
- **Profile Guided Optimization (PGO)**
- **Parallel compilation** with optimal core usage
- **Ninja generator** for fastest builds

## 🐛 Troubleshooting

### Common Issues

1. **Container build fails**: Check Docker resources and network connectivity
2. **VS Code connection issues**: Rebuild container or restart VS Code
3. **Compilation errors**: See `.devcontainer/BUILD_FIXES.md`
4. **Permission issues**: Container runs as `vscode` user with sudo access

### Debug Information
```bash
# Check compiler versions
gcc --version
clang --version

# Check CMake version
cmake --version

# Check available tools
which gdb valgrind clang-tidy cppcheck

# Check environment
echo $CC $CXX
printenv | grep -E "(VCPKG|CONAN)"
```

### Getting Help

1. **BUILD_FIXES.md** - Comprehensive troubleshooting guide
2. **Container logs** - Check Docker logs for container issues
3. **VS Code Dev Containers** - Extension documentation
4. **Tool documentation** - Each tool has extensive online docs

## 🚀 Performance Characteristics

### Build Performance
- **Parallel compilation** utilizing all available cores
- **Ninja generator** for optimal build dependency tracking
- **ccache integration** for incremental builds (optional)
- **Precompiled headers** support

### Container Resources
- **Base Image**: Ubuntu 22.04 LTS
- **Container Size**: ~4-6 GB (includes all tools)
- **Memory Usage**: 2-8 GB depending on workload
- **CPU Usage**: Optimized for multi-core development

## 📈 What's Included

### Compilers
- GCC 12.x (default)
- Clang 15.x with LLVM tools
- Support for C++11 through C++20

### Libraries (Pre-installed)
- Boost libraries
- OpenSSL development headers
- cURL development libraries
- Eigen3 mathematical library
- Google Test and Google Mock

### Tools
- Git with LFS support
- CMake 3.16+
- Ninja build system
- pkg-config
- Autotools suite
- Python 3 with pip

### Development Environment
- VS Code optimized settings
- IntelliSense configuration
- Debugging configurations
- Code formatting rules
- Extension recommendations

## 🔒 Security Features

- **Non-root user** execution (vscode user)
- **Sudo access** for system administration when needed
- **Container isolation** from host system
- **Secure defaults** for all development tools

## 📝 Contributing

This development environment is designed to be extensible. To add new tools or modify configurations:

1. **Dockerfile** - Add system packages and tools
2. **devcontainer.json** - VS Code settings and extensions
3. **post-create.sh** - Additional setup steps
4. **BUILD_FIXES.md** - Document new troubleshooting steps

## 📄 License

This development environment configuration is provided as-is for development use.

---

**Ready for heavy C++ development!** 🛠️⚡🚀
