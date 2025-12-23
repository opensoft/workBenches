# AI Provider Priority Configuration

## Overview

The workBenches system now supports configurable AI provider priority with automatic detection of CLI tools (OAuth/subscription-based) and fallback to API keys.

## Architecture

### Centralized AI Detection Flow

```
┌─────────────────────────────────────────┐
│  Wrapper Scripts (One-Time Detection)  │
│  - new-workspace.sh                     │
│  - delete-workspace.sh                  │
│  - update-workspace.sh                  │
└────────────────┬────────────────────────┘
                 │
                 ├─ Load user priority: ~/.config/workbenches/ai-provider-priority.conf
                 ├─ Check CLI tools (OAuth): claude, codex, gemini, etc.
                 ├─ Fallback to API keys: ANTHROPIC_API_KEY, etc.
                 │
                 ▼
         Export AI_PROVIDER and AI_PROVIDER_TYPE
                 │
                 ▼
┌─────────────────────────────────────────┐
│   Bench-Specific Scripts (Inherit)     │
│   - new-frappe-workspace.sh             │
│   - delete-frappe-workspace.sh          │
│   - update-frappe-workspace.sh          │
│                                         │
│   init_ai_provider() checks if          │
│   AI_PROVIDER already set by parent     │
└─────────────────────────────────────────┘
```

## Configuration

### Interactive Configuration Tool

```bash
# Simple interactive mode (default)
./scripts/configure-ai-priority.sh

# Advanced mode with move/swap commands
./scripts/configure-ai-priority.sh --advanced

# Show current configuration
./scripts/configure-ai-priority.sh --show

# Reset to defaults
./scripts/configure-ai-priority.sh --reset
```

### Configuration File

Location: `~/.config/workbenches/ai-provider-priority.conf`

Format: One provider per line, in priority order:
```
claude
codex
gemini
copilot
grok
meta
kimi2
deepseek
```

## Supported Providers

| Provider | Display Name | CLI Command | Auth Type |
|----------|--------------|-------------|-----------|
| codex | GitHub Codex | `codex` | CLI OAuth |
| claude | Claude (Anthropic) | `claude` | CLI OAuth + API key |
| gemini | Google Gemini | `gemini` | CLI OAuth |
| copilot | GitHub Copilot | `github-copilot-cli` | CLI OAuth |
| grok | xAI Grok | `grok` | CLI OAuth |
| meta | Meta Llama | `llama` | CLI OAuth |
| kimi2 | Moonshot Kimi 2 | `kimi` | CLI OAuth |
| deepseek | DeepSeek | `deepseek` | CLI OAuth |

## Default Priority Order

1. **codex** (GitHub Codex)
2. **claude** (Claude - Anthropic)
3. **gemini** (Google Gemini)
4. **copilot** (GitHub Copilot)
5. **grok** (xAI Grok)
6. **meta** (Meta Llama)
7. **kimi2** (Moonshot Kimi 2)
8. **deepseek** (DeepSeek)

## How It Works

### 1. Configuration Phase

Users run the configuration tool to set their preferred priority order. The TUI shows:
- ✓ Installed providers (green checkmark)
- ✗ Not installed providers (red X)
- Current priority order (numbered)

### 2. Detection Phase (Runtime)

When you run a workspace command:

1. **Wrapper script** loads `ai-provider-priority.conf`
2. **Iterates through providers** in configured order
3. **For each provider:**
   - Check if CLI tool is installed and authenticated (OAuth)
   - If not, check for API key in environment or config files
4. **First available provider** is selected
5. **Exports** `AI_PROVIDER` and `AI_PROVIDER_TYPE` to child scripts

### 3. Usage Phase

Bench-specific scripts inherit the detected provider without re-detection, ensuring:
- ✓ Single detection point
- ✓ Consistent provider across operation
- ✓ No duplicate authentication checks

## CLI vs API Key Priority

For each provider, the system checks in this order:

1. **CLI tool** (OAuth/subscription auth)
   - Example: `~/.claude/` config for Claude Desktop
   - Requires CLI command to be installed and authenticated
   
2. **API key** (fallback)
   - Environment variables: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.
   - Config files: `~/.anthropic/`, `~/.config/anthropic/`, etc.

## Claude Desktop Integration

The system automatically detects Claude Desktop credentials from:
- CLI: `claude` command with OAuth from `~/.claude/`
- Session key: `~/.claude.json` sessionKey field
- API key: Environment variable `ANTHROPIC_API_KEY`

## Example Usage

### Scenario 1: Developer with Claude Desktop

```bash
# Configure Claude as top priority
./scripts/configure-ai-priority.sh
# Select option to move Claude to #1
# Save and exit

# Now workspace commands use Claude automatically
./scripts/new-workspace.sh dartwing
# ✓ Using AI provider from parent: claude (via cli)
```

### Scenario 2: Developer with Multiple CLIs

```bash
# Configure priority: codex > claude > gemini
./scripts/configure-ai-priority.sh --advanced
# Use 't' command to set order
# save

# System will try:
# 1. Codex CLI (if authenticated)
# 2. Claude CLI (if authenticated)
# 3. Gemini CLI (if authenticated)
# 4. Fall back to API keys in same order
```

### Scenario 3: View Current Setup

```bash
./scripts/configure-ai-priority.sh --show
# Shows:
# - Current priority order
# - Installation status for each provider
# - Config file location
```

## Integration with setup-workbenches.sh

The main setup script should call the priority configuration tool during initial setup:

```bash
# In setup-workbenches.sh
echo "Configuring AI provider priority..."
./scripts/configure-ai-priority.sh --interactive
```

## Benefits

1. **User Control**: Users set their preferred AI provider order once
2. **Single Detection**: AI detection happens once per command, not per script
3. **Automatic Fallback**: If preferred provider unavailable, tries next in line
4. **OAuth Support**: Prioritizes CLI OAuth over API keys (better UX)
5. **Extensible**: Easy to add new providers to the system

## Files Modified/Created

### New Files
- `scripts/configure-ai-priority.sh` - TUI configuration tool

### Modified Files
- `scripts/new-workspace.sh` - Exports AI_PROVIDER variables
- `scripts/delete-workspace.sh` - Exports AI_PROVIDER variables
- `scripts/update-workspace.sh` - Exports AI_PROVIDER variables
- `devBenches/scripts/ai-cli-adapter.sh` - Loads user priority config
- `devBenches/frappeBench/scripts/lib/ai-provider.sh` - Respects parent's detection

### Configuration File
- `~/.config/workbenches/ai-provider-priority.conf` - User's priority order
