# workBenches

A collection of development workbenches and tools for various projects.

## Quick Setup

To set up workBenches on a new system, run:

```bash
./scripts/setup-workbenches.sh
```

The setup script provides an interactive menu with status-driven UI:

**Status Display** (shown first):
- ✓ Required dependencies (git, jq, curl) with versions
- ✓ AI credentials configuration status
- ✓ AI coding assistant CLIs (Claude Code, Copilot, Codex, Gemini, OpenCode)
- ✓ Spec-driven development tools status

**Interactive Menu**:
1. **Interactive Selection (TUI)** - Visual multi-select interface
2. Install/update benches
3. Setup/update AI credentials
4. Install spec-driven development tools
5. Install commands (onp, launchBench, workbench)
6. View setup summary
7. Exit setup

### Features
- **Status-First UI** - See what's installed before making changes
- **Selective Updates** - Update only what you need
- **Auto-Install** - Dependencies installed automatically based on OS
- **Re-runnable** - Safe to run multiple times to add components

For detailed UI flow and examples, see [Setup Script UI Guide](docs/setup-script-ui.md)

## Creating New Projects

To create a new project using installed benches, run:

```bash
./scripts/new-project.sh
```

This script will:
1. Show available project types from installed benches
2. Let you select the project type (e.g., Flutter, DartWing, etc.)
3. Prompt for project name and optional target directory
4. Delegate to the appropriate bench-specific script

### Examples:
```bash
./scripts/new-project.sh                    # Interactive mode
./scripts/new-project.sh myapp               # Interactive type selection for 'myapp'
./scripts/new-project.sh myapp ~/custom/path # Interactive type selection with custom path
```

The script discovers and uses project creation scripts from installed benches, making it easy to create properly configured projects for any development stack you have installed.

## Creating New Development Benches

To create a new development bench (workspace for a specific technology), run:

```bash
./scripts/new-bench.sh
```

This script will:
1. 🤖 Query AI APIs (OpenAI/Claude) for current tech stack information
2. Show interactive menu of popular technologies (Go, Rust, Node.js, PHP, Ruby, etc.)
3. Allow custom tech stack creation
4. Generate complete bench structure with DevContainer setup
5. Create project creation scripts
6. Update workBenches configuration automatically

### AI-Powered Tech Stack Discovery

Set API keys for current technology information:
```bash
# Using OpenAI
export OPENAI_API_KEY="your-key-here"
./scripts/new-bench.sh

# Using Claude API
export ANTHROPIC_API_KEY="your-key-here"
./scripts/new-bench.sh

# Using Claude Session (browser-based auth)
# Run setup to configure: ./scripts/setup-workbenches.sh
# Session stored in ~/.claude/config.json

# Without AI keys (uses built-in tech stacks)
./scripts/new-bench.sh
```

The script supports creating benches for any technology and will generate:
- Complete DevContainer configuration
- VS Code settings and extensions
- Project creation scripts
- Documentation and templates
- Git repository initialization

## AI Credentials Management

### Check Credentials Status

View the status of all configured AI services with color-coded indicators:

```bash
# Show status of all credentials
./scripts/check-ai-credentials.sh

# Interactive menu to update credentials
./scripts/check-ai-credentials.sh interactive
```

**Features:**
- 🟢 **Green**: Configured and valid
- 🔴 **Red**: Not configured or invalid
- Shows location of each credential
- Preview of API keys (first/last 4 chars)
- Interactive update menu

## Claude Session Authentication

workBenches supports Claude session authentication for seamless CLI access across all projects:

### Setup
```bash
./scripts/setup-workbenches.sh
# Select option 3: "Claude Session Token"
```

### Features
- **Centralized authentication**: One setup for all projects on your machine
- **Browser-based login**: Use your existing Claude account
- **Secure storage**: Session tokens stored in `~/.claude/config.json` with restricted permissions
- **Easy management**: Helper script for accessing session in your projects

### Usage
```bash
# Check session status
./scripts/claude-session-helper.sh info

# Get session key
./scripts/claude-session-helper.sh get

# Use in scripts
source ./scripts/claude-session-helper.sh
if has_claude_session; then
    SESSION_KEY=$(get_claude_session_key)
    # Use SESSION_KEY in your application
fi
```

For detailed instructions, see [Claude Session Setup Guide](docs/claude-session-setup.md)

## Spec-Driven Development Tools

workBenches supports spec-driven development with **spec-kit** (GitHub) and **OpenSpec** (Fission AI) for better AI collaboration:

### Setup
```bash
./scripts/setup-workbenches.sh
# Setup will check and offer to install both tools
```

### What Are These Tools?

**spec-kit (GitHub Spec Kit)**
- Python-based tool for spec-driven development
- Creates structured specs, plans, and tasks
- Works with Claude Code, GitHub Copilot, Cursor, and other AI assistants
- Installation: `uvx --from git+https://github.com/github/spec-kit.git specify init <project>`
- [GitHub Repository](https://github.com/github/spec-kit)

**OpenSpec (Fission AI)**
- Node.js-based lightweight spec framework
- Manages proposals, tasks, and spec changes
- Brownfield-first: great for existing projects (1→n)
- Installation: `npm install -g @fission-ai/openspec@latest`
- [GitHub Repository](https://github.com/Fission-AI/OpenSpec) | [Official Site](https://openspec.dev/)

### Benefits
- 📋 **Structured Planning**: Define what to build before coding
- 🤝 **AI Alignment**: Keep AI assistants on track with explicit requirements
- 📝 **Living Documentation**: Specs evolve with your project
- 🔄 **Iterative Refinement**: Review and adjust plans before implementation

### How It Works

1. **Specify** - Write down what you're building (requirements, constraints)
2. **Plan** - Create technical implementation plan
3. **Tasks** - Break down into actionable tasks
4. **Implement** - AI codes according to the spec

Both tools keep requirements explicit and auditable, reducing miscommunication between humans and AI coding assistants.

For detailed documentation, see [Spec-Driven Development Guide](docs/spec-driven-development.md)

## Configuration Management

The workBenches system uses `config/bench-config.json` to track benches and their capabilities.

### Automatic Discovery
```bash
./scripts/update-bench-config.sh
```

This script will:
- Auto-discover all installed benches (directories with .git repositories)
- Scan for project creation scripts in each bench
- Update `config/bench-config.json` with current state
- Backup the existing configuration

### Manual Configuration
You can also manually edit `config/bench-config.json` to:
- Add repository URLs for benches
- Define custom project script descriptions
- Add new bench types

## Container Architecture

WorkBenches uses a **multi-layer Docker image architecture** for efficiency and reusability:

- **Layer 0**: System base (Ubuntu + core utilities)
- **Layer 1a**: Development tools (Python, Node.js, AI CLIs)
- **Layer 1b**: Admin tools (Kubernetes, Cloud CLIs)
- **Layer 2**: Specialized bench tools (Frappe, Flutter, .NET, etc.)

**Benefits**:
- ⚡ Fast workspace creation (< 10 seconds with pre-built images)
- 🔄 Efficient rebuilds (only changed layers rebuild)
- 🎯 Clear separation of concerns
- 🔒 Security layers (read-only vs. action tools)

For complete documentation, see [Container Architecture Guide](CONTAINER-ARCHITECTURE.md)

## Structure

**All workbenches are maintained as separate repositories:**

- **adminBenches** - Administrative tools and utilities → [opensoft/adminBench](https://github.com/opensoft/adminBench)
- **devBenches** - Development environment collection:
  - **flutterBench** → [opensoft/flutterBench](https://github.com/opensoft/flutterBench)
  - **javaBench** → [opensoft/javaBench](https://github.com/opensoft/javaBench)
  - **dotNetBench** → [opensoft/dotNetBench](https://github.com/opensoft/dotNetBench)
  - **pythonBench** → [opensoft/pythonBench](https://github.com/opensoft/pythonBench)

## Separate Repositories

All workbenches are maintained as separate repositories:

| Workbench | Repository | Description |
|-----------|------------|-------------|
| adminBenches | [opensoft/adminBench](https://github.com/opensoft/adminBench) | Administrative tools and Kubernetes configs |
| flutterBench | [opensoft/flutterBench](https://github.com/opensoft/flutterBench) | Flutter development environment with devcontainers |
| javaBench | [opensoft/javaBench](https://github.com/opensoft/javaBench) | Java development environment and tools |
| dotNetBench | [opensoft/dotNetBench](https://github.com/opensoft/dotNetBench) | .NET development environment with devcontainers |
| pythonBench | [opensoft/pythonBench](https://github.com/opensoft/pythonBench) | Python development environment and tools |

To work with these, clone them separately or use git submodules.

## Getting Started

Each workbench contains its own documentation and setup instructions. Navigate to the respective directories to get started with specific tools.

## Contributing

This is a public repository. Feel free to contribute improvements and suggestions.

### Contributing to Individual Repositories

Each workbench is maintained in its own repository. Please contribute directly to the specific repository you want to improve:

- **adminBenches**: [opensoft/adminBench](https://github.com/opensoft/adminBench)
- **flutterBench**: [opensoft/flutterBench](https://github.com/opensoft/flutterBench)
- **javaBench**: [opensoft/javaBench](https://github.com/opensoft/javaBench)
- **dotNetBench**: [opensoft/dotNetBench](https://github.com/opensoft/dotNetBench)
- **pythonBench**: [opensoft/pythonBench](https://github.com/opensoft/pythonBench)
