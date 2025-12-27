# devBenches - Development Workbenches

This folder contains individual development workbenches for different programming languages and technologies.

## Structure

Each subfolder is a separate git repository containing a complete development environment:

- **`cppBench/`** - C++ development environment with DevContainer
- **`dotNetBench/`** - .NET development environment with DevContainer  
- **`flutterBench/`** - Flutter/Dart development environment with DevContainer
- **`javaBench/`** - Java development environment with DevContainer
- **`pythonBench/`** - Python development environment with DevContainer

## Layered Containers (Current Standard)

All benches are moving to the layered image model described in `workBenches/CONTAINER-ARCHITECTURE.md`:
- **Layer 0**: `workbench-base:{user}`
- **Layer 1a**: `devbench-base:{user}`
- **Layer 2**: `<bench>-bench:{user}` (bench-specific tools)

## Legacy Monolithic DevContainers (Deprecated)

Some benches still include a `.devcontainer/` directory with a monolithic Dockerfile. These are **legacy** and should not be used as the source of truth. Use the layered images and bench-level build scripts instead; treat monolithic Dockerfiles as deprecated artifacts until removed.

## Usage

### Using WorkBenches (Recommended)
```bash
# From workBenches root directory
./scripts/new-project.sh
```

### Direct Access
```bash
# Navigate to specific bench
cd devBenches/flutterBench
code .  # Open in VS Code with DevContainer
```

## Adding New Development Benches

Use the workBenches new-bench script:
```bash
# From workBenches root
./scripts/new-bench.sh
```

This will create a new development bench with:
- Complete DevContainer setup
- VS Code configuration
- Project creation scripts
- Documentation and templates

## Organization

- **This folder** (`devBenches/`) is part of the main workBenches repository
- **Individual benches** are separate git repositories
- **Each bench** provides a complete development environment for its technology
