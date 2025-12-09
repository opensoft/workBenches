# AI Credentials Management

## Quick Reference

### Check All Credentials Status
```bash
./scripts/check-ai-credentials.sh
# or
./scripts/check-ai-credentials.sh status
```

**Example Output:**
```
═══════════════════════════════════════════════
       AI Credentials Status Report
═══════════════════════════════════════════════

1. Claude Session Token
   Status:   ✓ Configured
   Location: /home/user/.claude/config.json
   Created:  2024-12-06T12:00:00Z

2. OpenAI API Key
   Status:   ✓ Configured
   Location: Environment: $OPENAI_API_KEY
   Key:      sk-proj...xyz9

3. Anthropic API Key (Claude API)
   Status:   ✗ Not Configured
   Location: Not set

═══════════════════════════════════════════════

ℹ️  2 of 3 services configured
```

### Interactive Update Menu
```bash
./scripts/check-ai-credentials.sh interactive
```

Provides menu to:
1. Update Claude Session Token
2. Update OpenAI API Key
3. Update Anthropic API Key
4. Set up all services
5. Exit

## Supported AI Services

### 1. Claude Session Token
**What it is:** Browser-based session authentication for Claude  
**Storage:** `~/.claude/config.json`  
**Used by:** Claude CLI tools, session-based authentication  
**Setup:** Get from browser cookies after logging into claude.ai

**Status Indicators:**
- 🟢 **Configured**: Valid session key found
- 🔴 **Not Configured**: No config file found
- 🔴 **Invalid Format**: Config exists but key format is wrong

### 2. OpenAI API Key
**What it is:** API key for OpenAI services (GPT-4, GPT-3.5, etc.)  
**Storage:** Environment variable `$OPENAI_API_KEY` in shell profile  
**Used by:** new-bench.sh (tech stack discovery), other OpenAI integrations  
**Setup:** Get from https://platform.openai.com/api-keys

**Status Indicators:**
- 🟢 **Configured**: Valid key found in environment
- 🔴 **Not Configured**: Environment variable not set
- 🔴 **Invalid Format**: Key doesn't start with 'sk-'

### 3. Anthropic API Key
**What it is:** API key for Anthropic Claude API  
**Storage:** Environment variable `$ANTHROPIC_API_KEY` in shell profile  
**Used by:** new-bench.sh (tech stack discovery), direct API access  
**Setup:** Get from https://console.anthropic.com/account/keys

**Status Indicators:**
- 🟢 **Configured**: Valid key found in environment
- 🔴 **Not Configured**: Environment variable not set
- 🔴 **Invalid Format**: Key doesn't start with 'sk-'

## Storage Locations

### Claude Session
```
~/.claude/config.json
```
**Format:**
```json
{
  "sessionKey": "sk-ant-sid01-...",
  "createdAt": "2024-12-06T12:00:00Z",
  "createdBy": "workBenches setup"
}
```
**Permissions:** 600 (user read/write only)

### API Keys (OpenAI & Anthropic)
```
~/.zshrc      # For zsh users
~/.bashrc     # For bash users
~/.profile    # Fallback
```
**Format:**
```bash
export OPENAI_API_KEY='sk-proj-...'
export ANTHROPIC_API_KEY='sk-ant-...'
```

## Common Tasks

### Set Up New Credentials
```bash
# Full setup wizard
./scripts/setup-workbenches.sh

# Or use interactive menu
./scripts/check-ai-credentials.sh interactive
```

### Update Expired Claude Session
```bash
./scripts/check-ai-credentials.sh interactive
# Select option 1: Update Claude Session Token
```

### Update OpenAI or Anthropic Keys
```bash
./scripts/check-ai-credentials.sh interactive
# Select option 2 or 3
```

### Check Specific Credential
```bash
# Check Claude session
./scripts/claude-session-helper.sh info

# Check if any service is configured
./scripts/check-ai-credentials.sh status
```

### Remove Credentials

**Claude Session:**
```bash
rm -rf ~/.claude/
```

**API Keys:**
Edit your shell profile:
```bash
# For zsh
nano ~/.zshrc

# For bash
nano ~/.bashrc

# Remove or comment out lines:
# export OPENAI_API_KEY='...'
# export ANTHROPIC_API_KEY='...'
```

Then reload:
```bash
source ~/.zshrc  # or ~/.bashrc
```

## Security Best Practices

### ✅ DO:
- Check credentials status regularly
- Update expired sessions promptly
- Use restricted file permissions (600 for config files)
- Keep API keys private
- Remove credentials when switching machines

### ❌ DON'T:
- Commit credentials to version control
- Share credentials across users
- Store credentials in plain text in projects
- Use the same credentials on untrusted machines
- Expose credentials in logs or error messages

## Troubleshooting

### "Not Configured" for All Services
**Solution:** Run setup to configure credentials:
```bash
./scripts/setup-workbenches.sh
```

### "Invalid Format" Error
**Possible causes:**
- Wrong key format (should start with 'sk-')
- Corrupted config file
- Partial key copied

**Solution:**
```bash
# Re-run setup to enter correct key
./scripts/check-ai-credentials.sh interactive
```

### Changes Not Taking Effect
**For API keys in shell profile:**
```bash
# Reload shell profile
source ~/.zshrc  # or ~/.bashrc

# Or restart terminal
```

### Can't Update Credentials
**Check permissions:**
```bash
# For Claude config
ls -la ~/.claude/config.json
# Should show: -rw------- (600)

# For shell profile
ls -la ~/.zshrc  # or ~/.bashrc
# Should show: -rw-r--r-- (644)
```

**Fix permissions:**
```bash
chmod 600 ~/.claude/config.json
chmod 644 ~/.zshrc  # or ~/.bashrc
```

## Integration in Scripts

### Check Before Using
```bash
#!/bin/bash
source ./scripts/claude-session-helper.sh

# Check all credentials
if ! ./scripts/check-ai-credentials.sh status >/dev/null; then
    echo "Some credentials not configured"
    exit 1
fi

# Check specific service
if has_claude_session; then
    echo "Claude session available"
else
    echo "Claude session not configured"
fi
```

### Use in Projects
```bash
# Get Claude session key
if [ -f ~/.claude/config.json ]; then
    CLAUDE_KEY=$(jq -r '.sessionKey' ~/.claude/config.json)
fi

# Get API keys from environment
if [ -n "$OPENAI_API_KEY" ]; then
    echo "OpenAI available"
fi

if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "Anthropic available"
fi
```

## Command Reference

```bash
# Status check (default)
./scripts/check-ai-credentials.sh
./scripts/check-ai-credentials.sh status
./scripts/check-ai-credentials.sh check

# Interactive menu
./scripts/check-ai-credentials.sh interactive
./scripts/check-ai-credentials.sh update
./scripts/check-ai-credentials.sh menu

# Help
./scripts/check-ai-credentials.sh help
./scripts/check-ai-credentials.sh -h
./scripts/check-ai-credentials.sh --help
```

## Related Documentation

- [Claude Session Setup Guide](claude-session-setup.md) - Detailed Claude session instructions
- [Main README](../README.md) - workBenches overview and quick start
- Setup Scripts:
  - `scripts/setup-workbenches.sh` - Full setup wizard
  - `scripts/check-ai-credentials.sh` - Status checker and updater
  - `scripts/claude-session-helper.sh` - Claude session utilities
