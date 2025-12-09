# Spec-Driven Development Tools

workBenches supports two popular spec-driven development frameworks: **spec-kit** (GitHub) and **OpenSpec** (Fission AI).

## Overview

Spec-driven development helps align humans and AI coding assistants by defining what to build before any code is written. This approach:

- 📋 **Structures Planning** - Clear requirements before coding
- 🤝 **Aligns AI** - Keep AI assistants on track
- 📝 **Documents Intent** - Living documentation that evolves
- 🔄 **Enables Iteration** - Review and adjust before implementation

## Installation

### Automated Installation

Run the setup script and choose option 3:

```bash
./scripts/setup-workbenches.sh
# Select: 3) Install spec-driven development tools
```

The setup script will:
1. Check if spec-kit and OpenSpec are already installed
2. Report version numbers for installed tools
3. Offer to install missing tools
4. Handle prerequisites (uv for spec-kit, npm for OpenSpec)

### Manual Installation

**spec-kit (GitHub Spec Kit)**
```bash
# Requires Python 3.11+ and uv package manager
uvx --from git+https://github.com/github/spec-kit.git specify init <project>
```

**OpenSpec**
```bash
# Requires Node.js and npm
npm install -g @fission-ai/openspec@latest
```

## Tools Comparison

### spec-kit (GitHub Spec Kit)

- **Language**: Python-based
- **Best For**: New projects (0→1)
- **Installation**: Via `uvx` (Python package runner)
- **Prerequisites**: Python 3.11+, uv package manager
- **Command**: `specify`
- **Repository**: https://github.com/github/spec-kit

**Workflow**:
1. `/specify` - Create specification
2. `/plan` - Generate technical plan
3. `/tasks` - Break into actionable tasks
4. Implement task by task

### OpenSpec (Fission AI)

- **Language**: Node.js/TypeScript
- **Best For**: Existing projects (1→n), brownfield development
- **Installation**: Via npm
- **Prerequisites**: Node.js, npm
- **Command**: `openspec`
- **Repository**: https://github.com/Fission-AI/OpenSpec
- **Website**: https://openspec.dev/

**Workflow**:
1. **Proposal** - Create change proposal with spec deltas
2. **Apply** - Implement according to spec
3. **Archive** - Merge approved changes into living specs

**Key Features**:
- Separates source of truth (`openspec/specs/`) from proposals (`openspec/changes/`)
- Tracks spec changes as diffs (ADDED, MODIFIED, REMOVED)
- Great for modifying existing behavior across multiple specs

## AI Tool Integration

Both tools work with popular AI coding assistants:

- Claude Code
- GitHub Copilot
- Cursor
- Windsurf
- Codex
- Cline
- And many more...

## Checking Installation Status

View installed tools and their versions:

```bash
./scripts/setup-workbenches.sh
# Dependencies and spec tools status shown automatically
```

## Usage Examples

### spec-kit

```bash
# Initialize a new project
specify init my-project

# In your AI assistant (e.g., Claude Code)
/specify    # Create specification
/plan       # Generate technical plan
/tasks      # Break into tasks
# Then implement each task
```

### OpenSpec

```bash
# Initialize in existing project
openspec init

# Create a change proposal
openspec list                           # See current changes
openspec validate <change-id> --strict  # Validate proposal
openspec show <change-id>               # Review details

# In your AI assistant
/openspec:proposal Add feature X
/openspec:apply
/openspec:archive
```

## Benefits Over Traditional Development

**Without Spec-Driven Development**:
- Requirements scattered across chat history
- AI drifts from original intent
- Endless correction cycles
- Lost context between sessions

**With Spec-Driven Development**:
- Requirements captured in markdown files
- AI stays aligned with explicit specs
- Review intent before implementation
- Persistent context across sessions
- Easier collaboration and code review

## Resources

### spec-kit
- GitHub: https://github.com/github/spec-kit
- Blog Post: https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/

### OpenSpec
- GitHub: https://github.com/Fission-AI/OpenSpec
- Website: https://openspec.dev/
- Discord: https://discord.gg/YctCnvvshC

## Troubleshooting

### spec-kit Installation Issues

**uv not found**:
```bash
# Install uv manually
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.cargo/bin:$PATH"
```

**Python version too old**:
```bash
# Check Python version
python3 --version
# spec-kit requires Python 3.11+
```

### OpenSpec Installation Issues

**npm not found**:
```bash
# Install Node.js and npm
# Ubuntu/Debian:
sudo apt update && sudo apt install nodejs npm

# macOS:
brew install node

# Or download from: https://nodejs.org/
```

**Permission errors**:
```bash
# Use npm without sudo (recommended)
npm config set prefix ~/.npm-global
export PATH=~/.npm-global/bin:$PATH

# Then install OpenSpec
npm install -g @fission-ai/openspec@latest
```

## Integration with workBenches

Spec-driven development tools complement workBenches' development workflow:

1. **Setup** - Install tools via setup script
2. **Create Bench** - Use `new-bench` to create development environment
3. **Initialize Spec Tool** - Run `specify init` or `openspec init` in your project
4. **Develop with AI** - Use spec-driven workflow with AI assistants
5. **Create Projects** - Use `onp` to create new projects from benches

The tools are globally available once installed, so you can use them in any project on your system.
