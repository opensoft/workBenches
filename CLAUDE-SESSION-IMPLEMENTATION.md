# Claude Session Implementation - December 6, 2024

## Summary
Added comprehensive Claude session authentication support to workBenches, allowing users to set up Claude CLI access once and use it across all projects.

## What Was Implemented

### 1. Setup Script Enhancement (`scripts/setup-workbenches.sh`)

Added new Claude Session Token setup option:
- **Modified AI service menu** to include 5 options instead of 4
- **Added `setup_claude_session()` function** that:
  - Guides users to get their session key from Claude.ai
  - Optionally opens browser to https://claude.ai/
  - Validates session key format (sk-ant-sid prefix)
  - Creates `~/.claude/` directory structure
  - Saves session key to `~/.claude/config.json`
  - Sets secure file permissions (600)

### 2. Helper Script (`scripts/claude-session-helper.sh`)

Created utility script with functions:
- `get_claude_session_key()` - Retrieve session key from config
- `has_claude_session()` - Check if session is configured
- `get_session_created_at()` - Get timestamp of session creation
- `export_claude_session()` - Export as environment variable
- `show_claude_session_info()` - Display session status

**CLI Commands:**
```bash
./scripts/claude-session-helper.sh check    # Check if configured
./scripts/claude-session-helper.sh get      # Get session key
./scripts/claude-session-helper.sh info     # Show session info
./scripts/claude-session-helper.sh export   # Export as env var
```

### 3. Documentation

#### Main Documentation (`docs/claude-session-setup.md`)
Comprehensive guide covering:
- What Claude session authentication is
- Step-by-step setup instructions with screenshots guidance
- How to extract session key from browser DevTools
- Storage location and file structure
- Usage examples (Bash, Python, Node.js)
- Security best practices
- Troubleshooting guide
- Session expiration handling

#### README Updates (`README.md`)
- Added Claude Session Authentication section
- Updated AI-Powered Tech Stack Discovery section
- Added usage examples and links to detailed docs

## File Structure

```
workBenches/
├── .claude/                              # Created in user's home directory
│   └── config.json                       # Session key storage (chmod 600)
├── scripts/
│   ├── setup-workbenches.sh             # Enhanced with Claude setup
│   └── claude-session-helper.sh         # NEW: Helper utilities
├── docs/
│   └── claude-session-setup.md          # NEW: Comprehensive guide
└── README.md                             # Updated with Claude docs
```

## Config File Format

`~/.claude/config.json`:
```json
{
  "sessionKey": "sk-ant-sid01-...",
  "createdAt": "2024-12-06T12:00:00Z",
  "createdBy": "workBenches setup"
}
```

## Security Features

1. **File Permissions**: Config file has 600 permissions (user read/write only)
2. **Home Directory Storage**: Stored in `~/.claude/` not in project directories
3. **No Git Commits**: Config file stays local, never committed to version control
4. **Validation**: Session key format validation before saving
5. **Warnings**: Users warned about session expiration and best practices

## User Workflow

### Setup Flow
1. User runs `./scripts/setup-workbenches.sh`
2. Chooses option 3 "Claude Session Token"
3. Setup guides them to:
   - Visit https://claude.ai/
   - Open DevTools (F12)
   - Navigate to Cookies
   - Copy sessionKey value
4. Paste session key into setup
5. Setup validates and saves to `~/.claude/config.json`
6. Session available to all projects

### Using in Projects
```bash
# In any project script
source /path/to/workBenches/scripts/claude-session-helper.sh

if has_claude_session; then
    SESSION_KEY=$(get_claude_session_key)
    # Use SESSION_KEY for Claude API calls
else
    echo "Claude not configured. Run setup."
fi
```

## Integration Points

### For Project Scripts
Projects can use the helper script by:
1. Sourcing: `source ./scripts/claude-session-helper.sh`
2. Calling functions: `has_claude_session`, `get_claude_session_key()`

### For Applications
Applications can read `~/.claude/config.json` directly:
- Python: Use `json.load()`
- Node.js: Use `JSON.parse(fs.readFileSync())`
- Bash: Use `jq` or grep parsing

## Benefits

1. **Single Setup**: Configure once, use everywhere on the machine
2. **No Environment Variables**: No need to pollute shell profiles with session keys
3. **Secure Storage**: Proper file permissions and isolation
4. **Easy Updates**: Re-run setup to update expired sessions
5. **Cross-Project**: All projects share the same authentication
6. **Developer Friendly**: Helper script makes integration trivial

## Differences from API Keys

| Feature | API Keys | Session Tokens |
|---------|----------|----------------|
| Storage | `~/.zshrc` / `~/.bashrc` | `~/.claude/config.json` |
| Format | Environment variable | JSON file |
| Expiration | Long-lived | 30-90 days |
| Renewal | Manual key generation | Browser login |
| Visibility | All shell sessions | On-demand access |
| Security | Plain text in profile | Restricted file (600) |

## Testing

Verify installation:
```bash
# Check helper script
./scripts/claude-session-helper.sh help

# Check if configured (will show "not configured" initially)
./scripts/claude-session-helper.sh check

# After setup, verify
./scripts/claude-session-helper.sh info
```

## Future Enhancements

Potential improvements:
1. Automatic session refresh/renewal
2. Multiple profile support
3. Session expiration warnings
4. Integration with Claude CLI tools
5. Encrypted storage option
6. Session sharing across dev environments (with encryption)

## Maintenance

### Updating Session
Users can update session anytime by:
```bash
./scripts/setup-workbenches.sh
# Select option 3 again
```

### Removing Session
```bash
rm -rf ~/.claude/
```

## Documentation Links

- Full Setup Guide: `docs/claude-session-setup.md`
- Helper Script: `scripts/claude-session-helper.sh`
- Main README: `README.md` (Claude Session Authentication section)

## Implementation Notes

- Session key format: Starts with `sk-ant-sid`
- Warning given for non-standard formats but allows continuation
- Browser auto-open attempted on Linux (xdg-open) and macOS (open)
- Fallback to manual URL if browser can't be opened
- Compatible with both jq and non-jq environments (fallback parsing)
