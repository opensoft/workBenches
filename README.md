# workBenches

A collection of development workbenches and tools for various projects.

## Quick Setup

To set up workBenches on a new system, run:

```bash
./setup-workbenches.sh
```

This script will:
1. Always clone the infrastructure repository (specKit)
2. Prompt you to choose which benches to install:
   - Install all benches at once
   - Select benches individually (y/n for each)
   - Skip bench installation

### Setup Script Requirements
- `git` - for cloning repositories
- `jq` - for JSON processing

The script automatically detects already installed benches and can be re-run to install additional components.

## Creating New Projects

To create a new project using installed benches, run:

```bash
./new-project.sh
```

This script will:
1. Show available project types from installed benches
2. Let you select the project type (e.g., Flutter, DartWing, etc.)
3. Prompt for project name and optional target directory
4. Delegate to the appropriate bench-specific script

### Examples:
```bash
./new-project.sh                    # Interactive mode
./new-project.sh myapp               # Interactive type selection for 'myapp'
./new-project.sh myapp ~/custom/path # Interactive type selection with custom path
```

The script discovers and uses project creation scripts from installed benches, making it easy to create properly configured projects for any development stack you have installed.

## Creating New Development Benches

To create a new development bench (workspace for a specific technology), run:

```bash
./new-bench.sh
```

This script will:
1. 🤖 Query AI APIs (OpenAI/Claude) for current tech stack information
2. Show interactive menu of popular technologies (Go, Rust, Node.js, PHP, Ruby, etc.)
3. Allow custom tech stack creation
4. Generate complete bench structure with DevContainer setup
5. Create project creation scripts with specKit integration
6. Update workBenches configuration automatically

### AI-Powered Tech Stack Discovery

Set API keys for current technology information:
```bash
# Using OpenAI
export OPENAI_API_KEY="your-key-here"
./new-bench.sh

# Using Claude
export ANTHROPIC_API_KEY="your-key-here"
./new-bench.sh

# Without API keys (uses built-in tech stacks)
./new-bench.sh
```

The script supports creating benches for any technology and will generate:
- Complete DevContainer configuration
- VS Code settings and extensions
- Project creation scripts
- Documentation and templates
- Git repository initialization

## Configuration Management

The workBenches system uses `bench-config.json` to track benches and their capabilities. You can manage this configuration:

### Automatic Discovery
```bash
./update-bench-config.sh
```

This script will:
- Auto-discover all installed benches (directories with .git repositories)
- Scan for project creation scripts in each bench
- Detect if scripts handle specKit copying
- Update `bench-config.json` with current state
- Backup the existing configuration

### Manual Configuration
You can also manually edit `bench-config.json` to:
- Add repository URLs for benches
- Define custom project script descriptions
- Control specKit inclusion behavior
- Add new bench types

## Structure

**All workbenches are maintained as separate repositories:**

- **adminBench** - Administrative tools and utilities → [opensoft/adminBench](https://github.com/opensoft/adminBench)
- **devBench** - Development environment collection:
  - **flutterBench** → [opensoft/flutterBench](https://github.com/opensoft/flutterBench)
  - **javaBench** → [opensoft/javaBench](https://github.com/opensoft/javaBench)
  - **dotNetBench** → [opensoft/dotNetBench](https://github.com/opensoft/dotNetBench)
  - **pythonBench** → [opensoft/pythonBench](https://github.com/opensoft/pythonBench)
- **specKit** - Specification-driven development toolkit → [opensoft/specKit](https://github.com/opensoft/specKit)

## Separate Repositories

All workbenches are maintained as separate repositories:

| Workbench | Repository | Description |
|-----------|------------|-------------|
| adminBench | [opensoft/adminBench](https://github.com/opensoft/adminBench) | Administrative tools and Kubernetes configs |
| flutterBench | [opensoft/flutterBench](https://github.com/opensoft/flutterBench) | Flutter development environment with devcontainers |
| javaBench | [opensoft/javaBench](https://github.com/opensoft/javaBench) | Java development environment and tools |
| dotNetBench | [opensoft/dotNetBench](https://github.com/opensoft/dotNetBench) | .NET development environment with devcontainers |
| pythonBench | [opensoft/pythonBench](https://github.com/opensoft/pythonBench) | Python development environment and tools |
| specKit | [opensoft/specKit](https://github.com/opensoft/specKit) | Specification-driven development toolkit |

To work with these, clone them separately or use git submodules.

## Getting Started

Each workbench contains its own documentation and setup instructions. Navigate to the respective directories to get started with specific tools.

## Contributing

This is a public repository. Feel free to contribute improvements and suggestions.

### Contributing to Individual Repositories

Each workbench is maintained in its own repository. Please contribute directly to the specific repository you want to improve:

- **adminBench**: [opensoft/adminBench](https://github.com/opensoft/adminBench)
- **flutterBench**: [opensoft/flutterBench](https://github.com/opensoft/flutterBench)
- **javaBench**: [opensoft/javaBench](https://github.com/opensoft/javaBench)
- **dotNetBench**: [opensoft/dotNetBench](https://github.com/opensoft/dotNetBench)
- **pythonBench**: [opensoft/pythonBench](https://github.com/opensoft/pythonBench)
- **specKit**: [opensoft/specKit](https://github.com/opensoft/specKit)
