# AI Credentials Reference

## Complete List of Mounted Paths

All paths are mounted as **read-only (`:ro`)** for security.

### Claude (Anthropic)

| Host Path | Container Path | Contents |
|-----------|----------------|----------|
| `~/.claude/` | `/home/${USER}/.claude/` | Subagents, Skills, and logs |
| `~/.claude.json` | `/home/${USER}/.claude.json` | **Critical**: OAuth session token and MCP configs |
| `~/.claude/.credentials.json` | `/home/${USER}/.claude/.credentials.json` | Fallback API key (some Linux versions) |

### Grok (xAI)

| Host Path | Container Path | Contents |
|-----------|----------------|----------|
| `~/.grok/` | `/home/${USER}/.grok/` | `api-key` file, `config.json`, and `GROK.md` memory |

### Codex (OpenAI/ChatGPT)

| Host Path | Container Path | Contents |
|-----------|----------------|----------|
| `~/.codex/` | `/home/${USER}/.codex/` | `auth.json` (OAuth session) and `config.toml` (model settings) |

### GitHub Copilot

| Host Path | Container Path | Contents |
|-----------|----------------|----------|
| `~/.copilot-cli/` | `/home/${USER}/.copilot-cli/` | Main storage for GitHub Copilot CLI agentic sessions |
| `~/.config/gh/` | `/home/${USER}/.config/gh/` | **Critical**: `hosts.yml` with GitHub OAuth token |

### Gemini (Google)

| Host Path | Container Path | Contents |
|-----------|----------------|----------|
| `~/.gemini/` | `/home/${USER}/.gemini/` | OAuth credentials (`oauth_creds.json`), config, and sessions |

### Letta Code

| Host Path | Container Path | Contents |
|-----------|----------------|----------|
| `~/.letta/` | `/home/${USER}/.letta/` | Complete Letta storage: |
| `~/.letta/env` | | **LETTA_API_KEY** and **LETTA_BASE_URL** |
| `~/.letta/desktop_data/` | | PostgreSQL or SQLite data for local agents |
| `~/.letta/desktop_config.json` | | Database connection types and server settings |

### OpenCode AI

| Host Path | Container Path | Contents |
|-----------|----------------|----------|
| `~/.opencode/` | `/home/${USER}/.opencode/` | OpenCode configuration and session data |

## Common Configuration Mounts

### Docker Socket
- `/var/run/docker.sock` - **Read-write** for docker-in-docker operations

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

## Authentication Methods by Provider

| Provider | Auth Method | Location | Notes |
|----------|-------------|----------|-------|
| Claude | OAuth Session | `~/.claude.json` → `sessionKey` | From Claude Desktop app |
| Codex | OAuth Token | `~/.codex/auth.json` → `tokens` | From ChatGPT Plus/Pro login |
| Grok | API Key | `~/.grok/api-key` | Plain text file |
| Gemini | OAuth | `~/.gemini/oauth_creds.json` | JSON credentials |
| Copilot | GitHub OAuth | `~/.config/gh/hosts.yml` | Via gh CLI |
| Letta | API Key + URL | `~/.letta/env` | Environment variables |
| OpenCode | Config | `~/.opencode/` | Tool-specific format |

## Verifying Mounts in Container

### Check All AI Credentials

```bash
# From inside devcontainer
ls -la ~/.claude ~/.codex ~/.grok ~/.gemini ~/.copilot-cli ~/.letta ~/.opencode

# Check specific configs
cat ~/.claude.json | jq .sessionKey
cat ~/.codex/auth.json | jq .tokens
cat ~/.grok/api-key
cat ~/.letta/env
cat ~/.gemini/oauth_creds.json | jq .
```

### Test CLI Authentication

```bash
# Claude
claude --version

# Codex
codex --version

# Grok
grok --version

# Gemini
gemini --version

# Copilot (via gh)
gh auth status

# Letta
letta --version

# OpenCode
opencode --version
```

## Security Considerations

### Read-Only Mounts
All credential directories are mounted as `:ro` (read-only):
- Prevents accidental modification from within container
- Credentials remain on host system only
- Container can read and use credentials but cannot alter them

### Exception: Docker Socket
The Docker socket is mounted as `:rw` (read-write) to enable:
- Building images from within container
- Running docker-compose commands
- Managing containers

### User Mapping
Container user matches host user via `${USER}`, `${UID}`, `${GID}`:
- File permissions work correctly
- No permission errors accessing mounts
- Processes run as same user inside and outside container

## Troubleshooting

### Credentials Not Accessible

**Symptom**: `ls: cannot access '~/.claude': No such file or directory`

**Check on host**:
```bash
ls -la ~/.claude ~/.codex ~/.grok
```

**Fix**: If paths don't exist on host, they won't mount. Either:
1. Create the directory: `mkdir -p ~/.claude`
2. Install/configure the AI tool on host first
3. Comment out that specific mount in override file

### Permission Denied

**Symptom**: `Permission denied` when accessing mounted credentials

**Check**: Container user matches host:
```bash
# On host
echo "UID: $UID, GID: $GID"

# In container
id
```

**Fix**: Ensure docker-compose.yml sets correct user:
```yaml
user: "${UID:-1000}:${GID:-1000}"
```

### Letta Database Not Accessible

**Symptom**: Letta CLI can't access local agents

**Check**: Verify desktop_data is mounted:
```bash
ls -la ~/.letta/desktop_data/
```

**Fix**: Letta's database needs to be initialized on host first:
```bash
letta init
```

### Tool Works on Host, Not in Container

**Checklist**:
1. ✅ Tool installed in Dockerfile? (Check `install-ai-clis.sh`)
2. ✅ Credentials mounted? (Check `docker-compose.override.yml`)
3. ✅ Tool in PATH? (Check `echo $PATH`)
4. ✅ Credentials readable? (Check `ls -la ~/.toolname`)

## Adding New AI Provider

### Complete Checklist

1. **Install CLI** (`devcontainer-shared/install-ai-clis.sh`):
   ```bash
   echo "Installing NewAI..."
   npm install -g @newai/cli
   ```

2. **Mount Credentials** (`devcontainer-shared/docker-compose.override.yml`):
   ```yaml
   # NewAI
   - ~/.newai:/home/${USER:-vscode}/.newai:ro
   ```

3. **Document** (this file):
   - Add to provider list
   - Document credential location
   - Add authentication method

4. **Test**:
   ```bash
   docker-compose build
   docker-compose up -d
   docker-compose exec service newai --version
   ```

## Related Documentation

- [Symlink Architecture](./SYMLINK-ARCHITECTURE.md) - How configurations inherit
- [Dockerfile Inheritance](./DOCKERFILE-INHERITANCE.md) - How CLIs install
- [AI Provider Setup](../scripts/AI-PROVIDER-SETUP.md) - AI detection and priority
