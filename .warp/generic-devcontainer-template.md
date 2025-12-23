# Generic DevContainer Template

## Overview

The `devcontainer.example/` folder in `/home/brett/projects/workBenches/` is a **reusable, framework-agnostic template** for creating development workspaces across all Bench types (Frappe, Flutter, and others).

## Key Improvements Over Frappe-Specific Template

### Before
- Hardcoded Frappe-specific configuration
- MariaDB, Redis, and Frappe networking assumptions
- Not reusable for other Bench types

### After
- Generic development environment with common tools
- Framework-agnostic Docker Compose
- Clear extension points for framework-specific services
- Can be used as a base for any Bench type

## Template Structure

```
devcontainer.example/
├── Dockerfile              # Ubuntu 24.04 with generic dev tools
├── devcontainer.json       # VSCode config (customize per workspace)
├── docker-compose.yml      # Generic dev service only
├── docker-compose.override.example.yml  # Template for additions
├── .env.example            # Generic env template
├── .env                    # Generic default env
├── README.md              # This template's documentation
├── nginx.conf             # Optional reverse proxy
└── assets/                # Supporting files
```

## Generic Dockerfile

Includes:
- **Base OS**: Ubuntu 24.04
- **System tools**: Git, curl, wget, zsh, docker client, SSH
- **Development**: Python 3, Node.js LTS, build tools
- **Linting/Formatting**: black, flake8, isort, pylint, pytest
- **AI Assistants**: Claude, Codex, Gemini, Copilot CLIs
- **User Management**: Matches host UID/GID automatically
- **Shell**: Oh My Zsh with plugins

**Removed**:
- ❌ `frappe-bench` pip package
- ❌ Frappe-specific verification
- ❌ Framework database clients (MariaDB installed but not configured)

## Generic docker-compose.yml

**Single Service**:
```yaml
services:
  dev:  # Generic name (not "dartwing-dev" or "frappe")
    build: ...
    networks:
      - bench-network  # Generic network (not "frappe-network")
    environment:
      # Basic PATH and SSH config
      # NO framework-specific vars
```

**Extend for Your Framework**:

### Frappe Example
```yaml
# docker-compose.override.yml
services:
  mariadb:
    image: mariadb:10.6
    environment:
      MYSQL_ROOT_PASSWORD: frappe
  redis-cache:
    image: redis:alpine
  dev:
    depends_on:
      - mariadb
      - redis-cache
    environment:
      DB_HOST: mariadb
      REDIS_CACHE: redis-cache:6379
```

### Flutter Example
```yaml
# docker-compose.override.yml
services:
  dev:
    environment:
      FLUTTER_VERSION: 3.24
      ANDROID_SDK_ROOT: /android/sdk
```

## Generic Environment Variables

### Template (.env.example)
```bash
# Basic workspace identity (generic)
CODENAME=alpha
CONTAINER_NAME=bench-alpha
COMPOSE_PROJECT_NAME=bench
HOST_PORT=8000
USER=brett
UID=1000
GID=1000

# Framework-specific (commented, to be uncommented per Bench type)
# For Frappe:
# DB_HOST=mariadb
# For Flutter:
# FLUTTER_VERSION=3.x
```

## Using This Template

### For frappeBench

1. The template is already in place
2. When creating workspaces, `scripts/new-frappe-workspace.sh` copies and customizes it
3. Customize `docker-compose.override.yml` to add Frappe services

### For a New Bench Type

1. Copy the workspace creation script pattern from frappeBench
2. Customize `docker-compose.override.yml` in the script
3. Set framework-specific environment variables in workspace `.env`
4. Extend the Dockerfile if needed (via docker-compose build args)

### Example: Creating a FlutterBench

```bash
mkdir -p /home/brett/projects/workBenches/devBenches/flutterBench
cp /home/brett/projects/workBenches/devcontainer.example flutterBench/
# Customize docker-compose.override.yml for Flutter
# Create workspace scripts similar to frappeBench
```

## Version Management

- **Version**: 1.0.0 (generic template)
- **Tracked in**: `devcontainer.example/README.md`
- **Setup script**: Detects version mismatches and offers updates

## Customization Checklist

For each Bench type:

- [ ] Create workspace directory structure (`workspaces/`, `scripts/`)
- [ ] Create workspace creation script (see `frappeBench/scripts/new-frappe-workspace.sh`)
- [ ] Copy `devcontainer.example/` to template location
- [ ] Create `docker-compose.override.example.yml` with framework services
- [ ] Add framework-specific environment variables to `.env` generation
- [ ] Update VSCode extensions in `devcontainer.json` if needed
- [ ] Create setup.sh to manage workspaces (see `frappeBench/setup.sh`)

## Benefits

1. **Code Reuse**: Single template for all Bench types
2. **Consistency**: Same development tools across projects
3. **Maintainability**: Update once, propagate to all projects
4. **Flexibility**: Easy to customize per framework
5. **Scalability**: Add new Bench types without duplicating infrastructure

## Future Improvements

- Parameterize more of the Dockerfile for framework-specific tools
- Create Dockerfile variants for specialized stacks
- Auto-detect framework type and suggest customizations
- Shared script library for workspace management
