# AI Credentials Mounts in DevContainers

## Overview

All devcontainer templates in workBenches now mount AI agent credentials and configurations to enable seamless AI assistance inside containers.

## Mounted AI Credential Paths

### Claude (Anthropic)
| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `~/.claude/` | `/home/${USER}/.claude/` | Stores Subagents, Skills, and logs |
| `~/.claude.json` | `/home/${USER}/.claude.json` | **Critical**: OAuth session token and MCP configs |
| `~/.claude/.credentials.json` | `/home/${USER}/.claude/.credentials.json` | Fallback API key storage (some Linux versions) |

### Grok (xAI)
| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `~/.grok/` | `/home/${USER}/.grok/` | Stores `api-key` file, `config.json`, and `GROK.md` memory |

### Codex (OpenAI/ChatGPT)
| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `~/.codex/` | `/home/${USER}/.codex/` | Stores `auth.json` (OAuth session) and `config.toml` (model settings) |

### GitHub Copilot
| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `~/.copilot-cli/` | `/home/${USER}/.copilot-cli/` | Main storage for GitHub Copilot CLI agentic sessions |
| `~/.config/gh/` | `/home/${USER}/.config/gh/` | **Critical**: `hosts.yml` with GitHub OAuth token |

## Additional Mounted Configurations

### Shell Configurations
- `~/.zshrc` - Zsh configuration
- `~/.bashrc` - Bash configuration  
- `~/.oh-my-zsh/` - Oh My Zsh framework
- `~/.p10k.zsh` - Powerlevel10k theme

### Git Configuration
- `~/.gitconfig` - Global Git settings

### SSH Keys and Configuration
- `~/.ssh/config` - SSH client configuration
- `~/.ssh/id_ed25519` - Ed25519 private key
- `~/.ssh/id_ed25519.pub` - Ed25519 public key
- `~/.ssh/id_rsa_ado` - Azure DevOps RSA key
- `~/.ssh/id_rsa_ado.pub` - Azure DevOps RSA public key
- `~/.ssh/known_hosts` - Known SSH hosts

### Docker Socket
- `/var/run/docker.sock` - Enables Docker commands inside container (read-write)

## Mount Permissions

All AI credential mounts are **read-only (`:ro`)** for security:
- Prevents accidental modification of credentials from within container
- Credentials remain on host system only
- Container can read and use credentials but cannot alter them

## Updated Templates

### Primary Templates
1. `/home/brett/projects/workBenches/devcontainer.example/docker-compose.yml`
2. `/home/brett/projects/workBenches/devBenches/frappeBench/devcontainer.example/docker-compose.yml`

### Templates to Check/Update
- `devBenches/flutterBench/.devcontainer/docker-compose.yml`
- `devBenches/cppBench/.devcontainer/docker-compose.yml`
- `devBenches/dotNetBench/.devcontainer/docker-compose.yml`

## Usage in Containers

Once a devcontainer is started with these mounts:

```bash
# Check Claude CLI authentication
claude --version

# Check Codex authentication  
codex --version

# Check Grok CLI
grok --version

# Check GitHub Copilot
copilot --version

# Verify gh CLI token
gh auth status
```

## AI Provider Priority Configuration

The user's configured AI provider priority order is automatically available inside containers via:

**Config File**: `~/.config/workbenches/ai-provider-priority.conf`

This file is **NOT** automatically mounted to containers. If you need it inside a container, add:

```yaml
- ~/.config/workbenches:/home/${USER}/.config/workbenches:ro
```

However, the AI CLI tools themselves (claude, codex, grok, copilot) work directly with their mounted credential directories.

## Security Considerations

1. **Read-Only Mounts**: All credential directories are mounted as read-only
2. **User Mapping**: Container user matches host user (`${USER}`, `${UID}`, `${GID}`)
3. **No Credential Copying**: Credentials stay on host, not copied into image
4. **Session Tokens**: OAuth session tokens are time-limited and can be revoked

## Troubleshooting

### Container can't find credentials

Check if paths exist on host:
```bash
ls -la ~/.claude/
ls -la ~/.codex/
ls -la ~/.grok/
ls -la ~/.config/gh/
ls -la ~/.copilot-cli/
```

### Permission errors

Verify container user matches host:
```bash
echo "Host UID: $UID, GID: $GID"
# Inside container:
id
```

### AI CLI not working

1. Verify CLI installed in container (check Dockerfile)
2. Check if credentials mounted: `ls -la ~/.claude/`
3. Test authentication: `claude --version` or `gh auth status`

## Maintenance

When updating devcontainer templates:
1. Always include all AI credential mounts
2. Keep mounts read-only (`:ro`)
3. Use `${USER}` variable for user path
4. Document any additional AI tools added

## Related Documentation

- [AI Provider Priority Configuration](../scripts/AI-PROVIDER-SETUP.md)
- [DevContainer Setup Guide](./README.md)
