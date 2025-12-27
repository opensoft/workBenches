# C++ Development Environment - Build Fixes and Troubleshooting (Legacy)

This document applies to the **legacy monolithic .devcontainer** build and is deprecated. The current standard is the layered image system (`workbench-base` → `devbench-base` → `cpp-bench`). Keep this for historical reference only.

This document contains common build issues and their solutions for the C++ Heavy Development Environment.

## Common Build Issues

### 1. Compiler Issues

#### GCC/G++ Not Found
```bash
# Check if compilers are properly installed
which gcc g++ clang clang++

# If missing, reinstall build essentials
sudo apt-get update
sudo apt-get install -y build-essential gcc-12 g++-12
```

#### Wrong Compiler Version
```bash
# Check current versions
gcc --version
g++ --version

# Update alternatives if needed
sudo update-alternatives --config gcc
sudo update-alternatives --config g++
```

### 2. CMake Issues

#### CMake Version Too Old
```bash
# Check CMake version
cmake --version

# If version is < 3.16, update CMake
sudo apt-get install -y cmake
```

#### CMake Can't Find Packages
```bash
# Update CMake module path
export CMAKE_MODULE_PATH=/usr/share/cmake/Modules:$CMAKE_MODULE_PATH

# Or specify package location explicitly
cmake -DCMAKE_PREFIX_PATH=/usr/local ..
```

### 3. Package Manager Issues

#### vcpkg Integration Problems
```bash
# Re-run vcpkg integration
/opt/vcpkg/vcpkg integrate install

# Check integration status
/opt/vcpkg/vcpkg integrate remove
/opt/vcpkg/vcpkg integrate install
```

#### Conan Profile Issues
```bash
# Reset Conan profile
conan profile detect --force

# Check profile settings
conan profile show default
```

### 4. Library and Dependency Issues

#### Missing Development Headers
```bash
# Install common development libraries
sudo apt-get install -y \
    libssl-dev \
    libcurl4-openssl-dev \
    libboost-all-dev \
    libeigen3-dev \
    libgtest-dev \
    libgmock-dev
```

#### GTest Not Found
```bash
# Build and install GTest manually
cd /usr/src/gtest
sudo cmake CMakeLists.txt
sudo make
sudo cp lib/*.a /usr/lib
sudo mkdir -p /usr/local/lib/gtest
sudo ln -s /usr/lib/libgtest.a /usr/local/lib/gtest/libgtest.a
sudo ln -s /usr/lib/libgtest_main.a /usr/local/lib/gtest/libgtest_main.a
```

### 5. Debugging Issues

#### GDB Not Working in Container
```bash
# Ensure container runs with proper capabilities
# Add to docker run command or docker-compose:
--cap-add=SYS_PTRACE --security-opt seccomp=unconfined
```

#### Valgrind Issues
```bash
# Install valgrind if missing
sudo apt-get install -y valgrind

# Run with proper options
valgrind --tool=memcheck --leak-check=full ./your_program
```

### 6. Performance Issues

#### Slow Compilation
```bash
# Use parallel compilation
make -j$(nproc)
# or with CMake
cmake --build . --parallel $(nproc)

# Use Ninja generator for faster builds
cmake -GNinja ..
ninja
```

#### Large Binary Size
```bash
# Strip debug symbols for release
strip your_binary

# Use release build type
cmake -DCMAKE_BUILD_TYPE=Release ..
```

### 7. Static Analysis Issues

#### Clang-Tidy Not Working
```bash
# Generate compile_commands.json
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..

# Run clang-tidy
clang-tidy src/*.cpp -- -std=c++20
```

#### CppCheck Issues
```bash
# Run cppcheck with proper options
cppcheck --enable=all --std=c++20 src/
```

### 8. IDE Integration Issues

#### VS Code IntelliSense Problems
1. Ensure C++ extension is installed
2. Generate `compile_commands.json`:
   ```bash
   cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..
   ```
3. Update `c_cpp_properties.json` if needed

#### Missing Extensions
```bash
# Reinstall VS Code extensions
code --install-extension ms-vscode.cpptools
code --install-extension ms-vscode.cmake-tools
```

### 9. Container-Specific Issues

#### Permission Denied
```bash
# Fix file permissions
sudo chown -R vscode:vscode /workspace
chmod -R 755 /workspace
```

#### Port Not Accessible
- Ensure ports are forwarded in `devcontainer.json`
- Check firewall settings on host machine

### 10. Environment Variables

#### PATH Issues
```bash
# Add to ~/.bashrc
export PATH="/opt/vcpkg:$PATH"
export VCPKG_ROOT="/opt/vcpkg"

# Reload bash configuration
source ~/.bashrc
```

## Quick Fixes

### Reset Development Environment
```bash
# Clean build directory
rm -rf build/
mkdir build && cd build

# Reconfigure and build
cmake .. -DCMAKE_BUILD_TYPE=Debug
cmake --build . --parallel $(nproc)
```

### Update All Tools
```bash
# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Update vcpkg
cd /opt/vcpkg && git pull && ./bootstrap-vcpkg.sh

# Update Conan
pip3 install --upgrade conan
```

## Getting Help

1. Check the build logs carefully
2. Verify all dependencies are installed
3. Ensure proper compiler and CMake versions
4. Test with a minimal example first
5. Check container capabilities and security settings

## Useful Commands

```bash
# System information
lsb_release -a
gcc --version
cmake --version
vcpkg version
conan --version

# Build information
ldd your_binary          # Check shared library dependencies
objdump -t your_binary   # Check symbol table
readelf -h your_binary   # Check ELF header

# Resource usage
htop                     # System resource monitor
valgrind --tool=massif   # Memory profiler
gprof                    # Performance profiler
```
