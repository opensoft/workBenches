# Migration Plan: interactive-setup.sh to OpenTUI (TypeScript/Bun)

## Overview

Migrate the current Bash-based terminal UI (`scripts/interactive-setup.sh`) to a TypeScript application using the OpenTUI framework with Bun runtime.

## Current System Analysis

The existing `interactive-setup.sh` is a ~1100 line Bash script providing:
- **3-column layout**: Dev Benches | AI Assistants | Tools
- **Keyboard navigation**: Arrow keys, Space toggle, Enter confirm, Q quit
- **State tracking**: Checked status, install/uninstall actions, component status
- **Status detection**: WSL-aware checks for installed tools, CLIs, credentials
- **Installation flows**: git clone, npm install, credential prompts
- **Visual elements**: ASCII banner, bordered sections, spinners, color coding

## Target Architecture

```
scripts/
├── interactive-setup.ts      # Main entry point
├── package.json              # Bun/OpenTUI dependencies
├── tsconfig.json
└── src/
    ├── components/
    │   ├── App.tsx                # Root component
    │   ├── Header.tsx             # Banner + title
    │   ├── SectionColumn.tsx      # Reusable column with items
    │   ├── SelectableItem.tsx     # Checkbox + status + label
    │   ├── StatusBar.tsx          # Bottom status display
    │   └── CredentialPrompt.tsx   # API key input dialogs
    ├── hooks/
    │   ├── useComponentStatus.ts  # Status detection logic
    │   ├── useInstaller.ts        # Installation orchestration
    │   └── useNavigation.ts       # Keyboard navigation state
    ├── utils/
    │   ├── statusChecks.ts        # Platform-aware status detection
    │   ├── installers.ts          # npm/git/uvx install functions
    │   └── config.ts              # Load bench-config.json
    └── types.ts                   # Shared type definitions
```

## Implementation Steps

### Phase 1: Project Setup

1. **Create package.json**
   ```json
   {
     "name": "workbenches-setup",
     "type": "module",
     "scripts": {
       "start": "bun run interactive-setup.ts",
       "dev": "bun --watch run interactive-setup.ts"
     },
     "dependencies": {
       "@opentui/core": "latest",
       "@opentui/solid": "latest"
     }
   }
   ```

2. **Create tsconfig.json** with JSX support for Solid

3. **Update setup.sh** to check for Bun and run TypeScript version

### Phase 2: Core Types & Config

1. **Define types** in `src/types.ts`:
   ```typescript
   interface Component {
     id: string;
     name: string;
     description: string;
     category: 'bench' | 'ai' | 'tool';
     status: 'installed' | 'not_installed' | 'needs_creds';
     checked: boolean;
     action: 'install' | 'uninstall' | 'keep' | null;
   }
   ```

2. **Port config loading** from `bench-config.json`

### Phase 3: Status Detection

Port `check_component_status()` logic to TypeScript:
- CLI detection via `Bun.spawn(['which', 'command'])`
- File existence checks via `Bun.file().exists()`
- WSL detection via environment variables
- Git remote verification

### Phase 4: UI Components

1. **App.tsx** - Main layout with 3 columns using flexbox
   ```tsx
   <box flexDirection="row" gap={2}>
     <SectionColumn title="DEV BENCHES" items={benches} />
     <SectionColumn title="AI ASSISTANTS" items={aiTools} />
     <SectionColumn title="TOOLS" items={tools} />
   </box>
   ```

2. **SectionColumn.tsx** - Bordered column with selectable items
   - Use `BoxRenderable` with border
   - Map items to `SelectableItem` components

3. **SelectableItem.tsx** - Individual toggleable item
   - Checkbox: `[ ]`, `[✓]`, `[X]`
   - Status indicator: `✓`, `✗`, `⚠`
   - Label with truncation

4. **Header.tsx** - ASCII banner + navigation help

5. **StatusBar.tsx** - Selected count + current action

### Phase 5: Navigation & Input

1. **useNavigation hook**:
   - Track `currentSection` (0-2) and `currentIndex`
   - Arrow key handlers for movement
   - Section boundary logic
   - Separator skipping for AI section

2. **Keyboard bindings**:
   - Up/Down: Move within section
   - Left/Right: Switch section
   - Space: Toggle selection
   - Enter: Process selections
   - Q: Quit

### Phase 6: Installation Logic

1. **useInstaller hook**:
   - Queue management for install/uninstall actions
   - Progress tracking with Timeline animation
   - Error handling and rollback

2. **Port installation commands**:
   - Benches: `git clone` + run `setup.sh`
   - AI CLIs: `npm install -g` or `uvx`
   - Tools: Display instructions or trigger installers

3. **Credential prompts**:
   - Use `InputRenderable` for API key entry
   - Validation via API test calls
   - Save to shell profile or config files

### Phase 7: Integration

1. **Update wrapper script** (`setup.sh`):
   ```bash
   # Check for Bun
   if command -v bun &> /dev/null; then
       cd "$SCRIPT_DIR/scripts" && bun run start
   else
       echo "Installing Bun..."
       curl -fsSL https://bun.sh/install | bash
       # Re-run with bun
   fi
   ```

2. **Fallback**: Keep Bash version as backup for systems without Bun

## Key Files to Modify

| File | Changes |
|------|---------|
| `scripts/package.json` | New file - dependencies |
| `scripts/interactive-setup.ts` | New file - entry point |
| `scripts/src/**` | New directory - all components |
| `setup.sh` | Add Bun check, call TS version |

## Key Files to Reference (Read-Only)

| File | Purpose |
|------|---------|
| `scripts/interactive-setup.sh` | Source of all logic to port |
| `config/bench-config.json` | Bench definitions |

## Verification

1. **Visual parity**: UI should look identical to Bash version
2. **Navigation**: All keyboard shortcuts work as before
3. **Status detection**: Same results as Bash version
4. **Installation**: All install/uninstall flows work
5. **Cross-platform**: Test on WSL, native Linux, macOS

### Test Commands
```bash
# Run new TypeScript version
cd scripts && bun run start

# Compare status detection
./interactive-setup.sh  # Old
bun run start           # New - should show same statuses
```

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| OpenTUI not production-ready | Keep Bash fallback, pin specific version |
| Bun not installed | Auto-install Bun in setup.sh |
| Complex WSL detection | Port existing Bash logic carefully, test thoroughly |
| Missing OpenTUI features | Use @opentui/core directly for custom components |

## Timeline Estimate

Not providing time estimates per user preference. Work is broken into 7 phases above.
