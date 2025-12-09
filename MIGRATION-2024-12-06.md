# WorkBenches Script Consolidation - December 6, 2024

## Summary
Removed duplicate scripts from root directory and consolidated to use enhanced versions in `scripts/` folder.

## Changes Made

### Files Removed from Root
1. ✅ `new-bench.sh` - Replaced by `scripts/new-bench.sh`
2. ✅ `new-project.sh` - Replaced by `scripts/new-project.sh` (AI-powered version)
3. ✅ `setup-workbenches.sh` - Replaced by `scripts/setup-workbenches.sh` (enhanced version)
4. ✅ `update-bench-config.sh` - Replaced by `scripts/update-bench-config.sh`
5. ✅ `onp` - Replaced by `scripts/onp`
6. ✅ `bench-config.json` - Now using `config/bench-config.json` (more complete version)

### Files Kept in Root
- ✅ `setup.sh` - Wrapper script that calls `scripts/setup-workbenches.sh`

### Configuration Changes
- **Old location**: `bench-config.json` (root)
- **New location**: `config/bench-config.json`
- **Backup created**: `bench-config.json.backup`

### Benefits of scripts/ Folder Versions

#### new-project.sh
- **AI-powered project type detection** using OpenAI or Claude APIs
- Keyword-based fallback analysis
- Better project description analysis
- More comprehensive project creation workflow

#### setup-workbenches.sh
- **AI API key setup and validation**
- Automatic OpenAI and Claude API testing
- Global command installation support
- Enhanced error handling and user prompts
- Better dependency checking with installation instructions

#### config/bench-config.json
- Contains AI keywords for better project matching
- More complete project script definitions
- Additional update scripts for Flutter and DartWing
- Properly organized with `devBenches/` and `adminBenches/` paths

### README Updates
Updated references in:
- `adminBench/README.md` - Lines 19, 34
- `adminBenches/README.md` - Lines 19, 34

Changed from:
```bash
./new-project.sh
./new-bench.sh
```

To:
```bash
./scripts/new-project.sh
./scripts/new-bench.sh
```

## Usage After Migration

### Quick Start (unchanged)
```bash
./setup.sh
```

### Create New Projects
```bash
./scripts/new-project.sh
# or use the global command after setup
onp
```

### Create New Benches
```bash
./scripts/new-bench.sh
```

### Update Configuration
```bash
./scripts/update-bench-config.sh
```

## Rollback Instructions
If needed, restore from backup:
```bash
cp bench-config.json.backup bench-config.json
# Scripts cannot be easily rolled back - recommend git revert if needed
```

## Testing Checklist
- [x] Removed duplicate scripts from root
- [x] Removed old config file from root
- [x] Updated README references in adminBench folders
- [x] Verified setup.sh still points to scripts/
- [x] Verified scripts/ folder has all required files
- [x] Created backup of old config

## Next Steps
1. Test project creation with `./scripts/new-project.sh`
2. Test bench creation with `./scripts/new-bench.sh`
3. Consider installing global commands: `./scripts/install-workbench-commands.sh --install`
4. Remove `bench-config.json.backup` after confirming everything works
