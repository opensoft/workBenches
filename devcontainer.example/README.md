# Generic Bench DevContainer Template

This is a reusable, generic template for creating Bench development workspaces with devcontainer configuration. It can be used as a base for all Bench types (Frappe, Flutter, and others).

## Template Version

**Current Version: 1.0.0**

## Overview

This template provides a complete development environment with:
- Generic development tools (Git, Python, Node.js, zsh, etc.)
- AI coding assistants (Claude, Gemini, Copilot, Codex)
- VSCode integration with recommended extensions
- Docker Compose for multi-service setup
- Configurable via environment variables

When creating a new workspace in a Bench project, the contents of this directory are automatically copied to your workspace's `.devcontainer/` folder and customized.

## Files Included

- `Dockerfile` - Ubuntu 24.04 based container with dev tools
- `devcontainer.json` - VS Code devcontainer configuration (workspace-specific)
- `docker-compose.yml` - Generic Docker Compose with dev service
- `docker-compose.override.example.yml` - Example for adding framework-specific services
- `docker-compose.override.yml` - Active override configuration
- `.env` - Generated environment variables per workspace
- `.env.example` - Environment variable template
- `nginx.conf` - Nginx reverse proxy configuration (optional)

## Included Tools

### System Tools
- Git with SSH support
- GitHub CLI (gh)
- Docker client
- curl, wget, jq
- zsh with Oh My Zsh
- Build tools (gcc, make, pkg-config)
- MariaDB client
- Node.js LTS

### Python Development
- Python 3 with pip
- Black formatter
- Flake8 linter
- isort import sorter
- Pylint
- Pytest
- IPython

### AI Coding Assistants
- Claude Code CLI
- OpenAI Codex CLI
- Google Gemini CLI
- GitHub Copilot CLI
- OpenCode AI
- Letta Code

### Utilities
- uv (fast Python package installer)
- npm with global package support
- Yarn package manager

## Customization for Specific Bench Types

### For Frappe
Extend `docker-compose.yml` to include MariaDB, Redis, and Frappe-specific services.

### For Flutter
Add Flutter SDK installation and Android/iOS build tools.

### For Other Frameworks
Add framework-specific services and build tools as needed.

## Environment Variables

Each workspace gets a `.devcontainer/.env` file with:
- `CODENAME` - Workspace name
- `CONTAINER_NAME` - Unique container identifier
- `COMPOSE_PROJECT_NAME` - Docker Compose project name
- `HOST_PORT` - Port mapping (unique per workspace)
- `USER` - Host user for permission matching
- `UID`/`GID` - User ID and group ID
- Framework-specific variables

## Version Tracking

Each workspace tracks which template version it was created from. The setup script can detect version mismatches and offer to update workspaces while preserving their custom `.env` settings.

## Updating Workspaces

When the template is updated:

1. Update the version number in this README
2. Run the setup script in the parent Bench directory
3. The script will detect outdated workspaces and offer updates
4. Existing `.env` files will be preserved during updates
