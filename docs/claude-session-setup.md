# Claude Session Setup Guide

This guide explains how to set up Claude session authentication for workBenches, allowing all your projects to access Claude CLI features.

## What is Claude Session Authentication?

Claude session authentication uses your browser's active session to authenticate with Claude. This allows you to:
- Use Claude CLI tools across all projects
- Avoid entering credentials repeatedly
- Share authentication across the entire machine

## Setup Methods

### Method 1: During workBenches Setup (Recommended)

When running the initial setup:
```bash
./setup.sh
```

Choose option 3 "Claude Session Token" when prompted for AI service setup.

### Method 2: Re-run Setup Later

```bash
./scripts/setup-workbenches.sh
```

When prompted about AI features, select the Claude Session Token option.

## Getting Your Claude Session Key

### Step-by-Step Instructions

1. **Visit Claude**: Go to https://claude.ai/ and log in

2. **Open DevTools**:
   - Press `F12` on your keyboard
   - Or right-click anywhere → Select "Inspect"
   - Or use menu: More Tools → Developer Tools

3. **Navigate to Cookies**:
   - Click the **Application** tab (Chrome/Edge) or **Storage** tab (Firefox)
   - Expand **Cookies** in the left sidebar
   - Click on `https://claude.ai`

4. **Find sessionKey**:
   - Look for a cookie named `sessionKey`
   - Click on it to view details
   - Copy the **Value** (it starts with `sk-ant-sid`)

### Alternative Console Method

1. Open DevTools Console tab
2. Run this command:
   ```javascript
   document.cookie
   ```
3. Find and copy the sessionKey value from the output

## Storage Location

Your Claude session is stored securely in:
```
~/.claude/config.json
```

**File structure:**
```json
{
  "sessionKey": "sk-ant-sid...",
  "createdAt": "2024-12-06T12:00:00Z",
  "createdBy": "workBenches setup"
}
```

**Security:**
- File permissions: `600` (readable only by you)
- Not stored in environment variables
- Not committed to git
- Accessible only on your local machine

## Using Claude Session in Projects

### Helper Script

Use the provided helper script to access your session:

```bash
# Check if session is configured
./scripts/claude-session-helper.sh check

# Get session key
./scripts/claude-session-helper.sh get

# Show session info
./scripts/claude-session-helper.sh info

# Export as environment variable
./scripts/claude-session-helper.sh export
```

### In Your Scripts

Source the helper to use functions:

```bash
#!/bin/bash
source "$(dirname "$0")/scripts/claude-session-helper.sh"

if has_claude_session; then
    SESSION_KEY=$(get_claude_session_key)
    # Use SESSION_KEY in your application
else
    echo "Claude session not configured"
fi
```

### In Your Applications

Read the config file directly:

```python
# Python example
import json
import os

config_path = os.path.expanduser("~/.claude/config.json")
with open(config_path) as f:
    config = json.load(f)
    session_key = config["sessionKey"]
```

```javascript
// Node.js example
const fs = require('fs');
const path = require('path');

const configPath = path.join(os.homedir(), '.claude/config.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const sessionKey = config.sessionKey;
```

## Session Expiration

Claude session keys may expire:
- After a period of inactivity (typically 30-90 days)
- When you log out from Claude
- When you change your password

### Updating Expired Sessions

Simply re-run the setup:
```bash
./scripts/setup-workbenches.sh
```

Select Claude Session Token option and provide the new key.

## Security Best Practices

### ✅ DO:
- Keep your session key private
- Use file permissions (600) on config file
- Update expired keys promptly
- Log out of Claude when using shared computers

### ❌ DON'T:
- Commit `.claude/` to version control
- Share your session key
- Store session keys in public repositories
- Use session keys on untrusted machines

## Troubleshooting

### Session Key Not Working

1. **Check if key is valid**:
   ```bash
   ./scripts/claude-session-helper.sh info
   ```

2. **Verify you're logged into Claude**:
   - Visit https://claude.ai/
   - Ensure you're logged in
   - Get a fresh session key

3. **Check file permissions**:
   ```bash
   ls -la ~/.claude/config.json
   # Should show: -rw------- (600)
   ```

### Can't Find sessionKey Cookie

Some browsers organize cookies differently:
- **Chrome/Edge**: Application → Cookies
- **Firefox**: Storage → Cookies
- **Safari**: Develop → Show Web Inspector → Storage

If you still can't find it, use the Console method described above.

### Session Expired Message

Run setup again to get a new key:
```bash
./scripts/setup-workbenches.sh
```

## Multiple Machines

Each machine needs its own Claude session setup:
- Session keys are machine-specific
- Not synced automatically
- Run setup on each development machine

## Privacy & Data

- Session keys are stored locally only
- Not sent to any third-party services
- Used only for Claude API authentication
- Can be deleted anytime by removing `~/.claude/`

## Support

For issues with Claude session authentication:
1. Check this documentation first
2. Review workBenches setup logs
3. Visit https://claude.ai/help for Claude-specific issues
4. Re-run setup to reset configuration
