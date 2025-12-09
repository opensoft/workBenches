# Setup Script UI Flow

The workBenches setup script provides a clear, status-driven interface that shows you exactly what's installed and what's available.

## UI Flow

### 1. Dependencies Check
```
Checking Required Dependencies

  ✓ git - installed (version: 2.43.0)
  ✓ jq - installed (version: 1.7)
  ✓ curl - installed (version: 8.5.0)
```

Shows all required dependencies with:
- ✓ Green checkmark for installed
- ✗ Red X for not installed
- Version numbers for installed tools

If dependencies are missing, script offers to auto-install them based on your OS.

### 2. AI Credentials Status
```
AI Credentials Status
  ✗ OpenAI API Key - not configured
  ✗ Anthropic API Key - not configured
  ✗ Claude Session Token - not configured
```

Shows configuration status for all AI services:
- **OpenAI API Key** - For GPT-4 powered features
- **Anthropic API Key** - For Claude API access
- **Claude Session Token** - For Claude CLI access (browser-based auth)

### 3. AI Coding Assistant CLIs
```
AI Coding Assistant CLIs
  ✗ Claude Code CLI - not installed
  ✗ GitHub Copilot CLI - not installed
  ✗ Codex CLI - not installed
  ✗ Gemini CLI - not installed
  ✗ OpenCode CLI - not installed
```

Shows installation status of AI coding assistant command-line interfaces:
- **Claude Code CLI** - Anthropic's terminal-based coding assistant
- **GitHub Copilot CLI** - GitHub's AI pair programmer for terminal
- **Codex CLI** - OpenAI Codex command-line interface
- **Gemini CLI** - Google's Gemini AI coding assistant
- **OpenCode CLI** - Open-source AI coding assistant

### 4. Spec-Driven Development Tools
```
Spec-Driven Development Tools
  ✗ spec-kit (GitHub Spec Kit) - not installed
  ✗ OpenSpec - not installed
```

Shows installation status of spec-driven development tools:
- **spec-kit** - GitHub's spec-driven development framework
- **OpenSpec** - Fission AI's lightweight spec framework

### 5. Interactive Menu
```
=== WorkBenches Setup Menu ===
1) Interactive Selection (TUI) - Select multiple components
2) Install/update benches
3) Setup/update AI credentials
4) Install spec-driven development tools
5) Install commands (onp, launchBench, workbench)
6) View setup summary
7) Exit setup
```

Choose what you want to do - no need to run through everything every time!

## Menu Options Explained

### Option 1: Interactive Selection (TUI)
**NEW: Visual keyboard-driven interface for selecting multiple components at once**

Launches a full-screen interactive text user interface with:
- **Visual navigation** with arrow keys and Tab
- **Multi-select** with spacebar
- **Real-time status** indicators (✓ installed, ✗ not installed)
- **Organized blocks**: AI Credentials, AI Assistants, Spec Tools, Benches

**Keyboard Controls**:
- `↑/↓` - Move selection up/down
- `Tab` - Jump to next block
- `Space` - Toggle selection checkbox
- `Enter` - Confirm and process selected items
- `Q` - Quit without changes

**Features**:
- Select multiple components from different categories
- Visual feedback with highlighted current block
- See installation status while selecting
- Counter shows number of selected items
- Process all selections with one Enter

**Example UI**:
```
╔════════════════════════════════════════════════════════════════╗
║          WorkBenches Interactive Setup Selector           ║
╚════════════════════════════════════════════════════════════════╝

Navigation: ↑/↓ Move  Tab: Next Block  Space: Select  Enter: Confirm  Q: Quit

┌─ AI Credentials ─┐
▶ [✓] ✗ OpenAI API Key - For GPT-4 features
  [ ] ✗ Anthropic API Key - For Claude API
  [✓] ✗ Claude Session Token - Browser-based auth
└─────────────────┘

┌─ AI Coding Assistants ─┐
  [✓] ✗ Claude Code CLI - Terminal coding assistant
  [ ] ✗ GitHub Copilot CLI - AI pair programmer
  ...
└─────────────────┘

Selected items: 3
```

### Option 2: Install/update benches
- View available benches (flutterBench, javaBench, etc.)
- Install all benches at once
- Select benches individually
- Skip if already installed

### Option 2: Setup/update AI credentials
Shows current status, then offers:
- **OpenAI API Key** - Test and validate key
- **Anthropic Claude API** - Test and validate key  
- **Claude Session Token** - Browser-based authentication
- **All services** - Set up everything at once
- **Skip** - Configure later

API keys are:
- Validated before saving
- Stored in your shell profile (~/.zshrc or ~/.bashrc)
- Exported for immediate use

### Option 3: Install spec-driven development tools
Shows current installation status, then offers to install:
- **spec-kit** - Automatically installs `uv` if needed
- **OpenSpec** - Requires Node.js/npm

Prerequisites are checked and installed automatically when possible.

### Option 4: Install commands
Installs global commands:
- **onp** (opensoft new project) - Quick project creation
- **launchBench** - Launch development benches
- **workbench** - Workbench management utilities

Commands are installed to `~/.local/bin` and added to PATH.

### Option 5: View setup summary
Shows complete status of:
- Infrastructure components
- Installed benches
- Total component count

### Option 6: Exit setup
Saves progress and exits. You can re-run anytime to make changes.

## Status Indicators

Throughout the UI, consistent status indicators are used:

| Symbol | Color | Meaning |
|--------|-------|---------|
| ✓ | Green | Installed/Configured |
| ✗ | Red | Not installed/Not configured |
| ⚠️ | Yellow | Warning/Action needed |

## Example: Fresh Installation

```
WorkBenches Setup Script
==========================

Checking Required Dependencies

  ✓ git - installed (version: 2.43.0)
  ✓ jq - installed (version: 1.7)
  ✓ curl - installed (version: 8.5.0)

AI Credentials Status
  ✗ OpenAI API Key - not configured
  ✗ Anthropic API Key - not configured
  ✗ Claude Session Token - not configured

AI Coding Assistant CLIs
  ✗ Claude Code CLI - not installed
  ✗ GitHub Copilot CLI - not installed
  ✗ Codex CLI - not installed
  ✗ Gemini CLI - not installed
  ✗ OpenCode CLI - not installed

Spec-Driven Development Tools
  ✗ spec-kit (GitHub Spec Kit) - not installed
  ✗ OpenSpec - not installed


=== WorkBenches Setup Menu ===
1) Install/update benches
2) Setup/update AI credentials
3) Install spec-driven development tools
4) Install commands (onp, launchBench, workbench)
5) View setup summary
6) Exit setup

Enter your choice (1-6): 2

AI Credentials Status
  ✗ OpenAI API Key - not configured
  ✗ Anthropic API Key - not configured
  ✗ Claude Session Token - not configured

AI-Powered Features Setup
WorkBenches supports AI-powered bench creation with current tech stack information.

AI Features include:
• Current technology and framework discovery
• Up-to-date best practices and tools
• Smart bench generation with latest versions

Would you like to setup or update AI credentials now? [y/N]:
```

## Example: Partially Configured System

```
WorkBenches Setup Script
==========================

Checking Required Dependencies

  ✓ git - installed (version: 2.43.0)
  ✓ jq - installed (version: 1.7)
  ✓ curl - installed (version: 8.5.0)

AI Credentials Status
  ✓ OpenAI API Key - configured
  ✗ Anthropic API Key - not configured
  ✓ Claude Session Token - configured

AI Coding Assistant CLIs
  ✓ Claude Code CLI - installed (version: 2.1.0)
  ✗ GitHub Copilot CLI - not installed
  ✗ Codex CLI - not installed
  ✗ Gemini CLI - not installed
  ✓ OpenCode CLI - installed (version: 0.5.2)

Spec-Driven Development Tools
  ✗ spec-kit (GitHub Spec Kit) - not installed
  ✓ OpenSpec - installed (version: 1.2.3)


=== WorkBenches Setup Menu ===
1) Install/update benches
2) Setup/update AI credentials
3) Install spec-driven development tools
4) Install commands (onp, launchBench, workbench)
5) View setup summary
6) Exit setup

Enter your choice (1-6):
```

## Benefits of New UI

### 1. Immediate Status Visibility
See exactly what's installed before making any choices.

### 2. Non-Destructive
Shows what you have without changing anything until you choose an action.

### 3. Selective Operations
Update just what you need - no need to run through full setup each time.

### 4. Clear Feedback
Every operation shows:
- What's being done
- Success/failure status
- Next steps if needed

### 5. Version Information
Know exactly which versions are installed:
- git 2.43.0
- jq 1.7
- OpenSpec 1.2.3

### 6. Re-runnable
Run the script anytime to:
- Check current status
- Add new components
- Update credentials
- Install missing tools

## Quick Actions

Common tasks made easy:

**Update AI credentials only:**
```bash
./scripts/setup-workbenches.sh
# Choose option 2
```

**Install spec tools only:**
```bash
./scripts/setup-workbenches.sh
# Choose option 3
```

**Check what's installed:**
```bash
./scripts/setup-workbenches.sh
# Review status display, then choose option 6 (exit)
```

**Full setup:**
```bash
./scripts/setup-workbenches.sh
# Choose options 1, 2, 3, 4 in sequence
```

## Design Principles

The UI follows these principles:

1. **Status First** - Show state before asking for changes
2. **Non-Invasive** - Display information without modifying system
3. **Incremental** - Make one change at a time
4. **Reversible** - Easy to modify or undo choices
5. **Informative** - Clear feedback at every step
6. **Accessible** - Color coding + text indicators for clarity

## Additional Resources

- **AI Credentials Management**: Run `./scripts/check-ai-credentials.sh --interactive`
- **Spec Tools Guide**: See [docs/spec-driven-development.md](spec-driven-development.md)
- **Claude Session Setup**: See [docs/claude-session-setup.md](claude-session-setup.md)
