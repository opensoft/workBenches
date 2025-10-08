# devBench - Development Workbenches

This folder contains individual development workbenches for different programming languages and technologies.

## Structure

Each subfolder is a separate git repository containing a complete development environment:

- **`cppBench/`** - C++ development environment with DevContainer
- **`dotNetBench/`** - .NET development environment with DevContainer  
- **`flutterBench/`** - Flutter/Dart development environment with DevContainer
- **`javaBench/`** - Java development environment with DevContainer
- **`pythonBench/`** - Python development environment with DevContainer

## Usage

### Using WorkBenches (Recommended)
```bash
# From workBenches root directory
./new-project.sh
```

### Direct Access
```bash
# Navigate to specific bench
cd devBench/flutterBench
code .  # Open in VS Code with DevContainer
```

## Adding New Development Benches

Use the workBenches new-bench script:
```bash
# From workBenches root
./new-bench.sh
```

This will create a new development bench with:
- Complete DevContainer setup
- VS Code configuration
- Project creation scripts
- Documentation and templates

## Organization

- **This folder** (`devBench/`) is part of the main workBenches repository
- **Individual benches** are separate git repositories
- **Each bench** provides a complete development environment for its technology