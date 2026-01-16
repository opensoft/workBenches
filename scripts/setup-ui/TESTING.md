# Setup-UI Testing Guide

## Overview

The setup-ui app has been fixed to properly integrate with OpenTUI's rendering and keyboard input system. The app now uses:

- **@opentui/solid render()** - OpenTUI's native renderer instead of manual setup
- **useKeyboard hook** - OpenTUI's keyboard event system for capturing input
- **Proper JSX** - Uses `fg` (foreground) color props instead of `color`

## Testing the App

### From the Root Setup Script

The recommended way to test is through the full setup flow:

```bash
cd /home/brett/projects/workBenches
./setup.sh
```

This will:
1. Check for Docker and build base image if needed
2. Automatically launch the setup-ui app if Bun is installed
3. Show the interactive 3-column interface

### Direct Testing

For faster iteration:

```bash
cd /home/brett/projects/workBenches/scripts/setup-ui
bun run start
```

## Expected Behavior

When the app starts, you should see:

```
   ___                            __ _
  / _ \ _ __    ___  _ __   ___ / _| |_
 | | | | '_ \  / _ \| '_ \ / __| |_| __|
 | |_| | |_) ||  __/| | | |\__ \  _| |_
  \___/| .__/  \___||_| |_||___/_|  \__|
       |_|

╔══════════════════════════════════════════════════════════════════════════════╗
║               WorkBenches Configuration Manager                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

Navigation: ↑/↓ Move  ←/→: Switch Section  Space: Toggle  Enter: Apply Changes  Q: Quit

┌─ DEV BENCHES ──────┐ ┌─ AI ASSISTANTS ────┐ ┌─ TOOLS ─────────────┐
│ [ ] ✗ Item1        │ │ [ ] ✗ Item1        │ │ [ ] ✗ Item1        │
│ [ ] ✗ Item2        │ │ [ ] ✗ Item2        │ │ [ ] ✗ Item2        │
└────────────────────┘ └────────────────────┘ └────────────────────┘
```

## Testing Keyboard Input

### Arrow Keys

Press arrow keys and check the console output:

- **Up Arrow (↑)**: Should show `Key pressed: 'up'` and move selection up
- **Down Arrow (↓)**: Should show `Key pressed: 'down'` and move selection down
- **Left Arrow (←)**: Should show `Key pressed: 'left'` and switch to previous column
- **Right Arrow (→)**: Should show `Key pressed: 'right'` and switch to next column

### Other Keys

- **Space**: Should show `Key pressed: ' '` and toggle item selection
- **Enter**: Should show `Key pressed: 'enter'` and apply changes
- **Q**: Should show `Key pressed: 'q'` and exit without changes
- **Ctrl+C**: Should exit gracefully

## Diagnostic Output

The app includes diagnostic logging. When running, you should see console output like:

```
Raw keyboard event keys: [ 'key' ]
  - event.key: { name: 'ArrowUp', ctrl: false, shift: false, meta: false }
Key pressed: 'up', ctrl: false, shift: false
```

### If Arrow Keys Don't Work

If arrow keys aren't detected, the diagnostic output will show:

1. **Raw keyboard event structure** - What OpenTUI is actually sending
2. **Key name extraction** - What the app detected from the event
3. **Final key press** - What the navigation handler received

Report these diagnostics if arrow keys still don't work.

## What's Fixed

1. ✅ **Replaced manual renderer creation** with OpenTUI's `render()` function
2. ✅ **Integrated useKeyboard hook** for proper keyboard capture
3. ✅ **Fixed JSX props** - All `color` changed to `fg`
4. ✅ **Created jsx-runtime shim** for Bun/SolidJS compatibility
5. ✅ **Proper component lifecycle** - Using Solid.js signals correctly
6. ✅ **Enhanced keyboard event detection** - Multiple extraction methods

## Troubleshooting

### App exits with "This program requires an interactive terminal"

This is expected when running outside a TTY. Always run interactively in a terminal.

### Keyboard events show but navigation doesn't work

Check the console output:
- Are key names being detected correctly?
- Are they matching the expected names ('up', 'down', 'left', 'right', etc.)?
- Is handleKeyPress being called?

### Selection doesn't move on arrow keys

1. Check if keys are being detected (look for console logs)
2. Check if the navigation state is being updated
3. Verify the display is showing the correct highlight position

## Debug Mode

To enable more detailed debugging, uncomment the log line in `src/hooks/useKeyboardNavigation.ts`:

```typescript
// console.log('Raw keyboard event:', event);  // <- Uncomment this
```

This will show the raw OpenTUI event structure for every key press.

## Next Steps

After confirming keyboard input works:

1. Test status detection (should see ✓/✗/⚠ symbols)
2. Test item toggling (Space to select/deselect)
3. Test applying changes (Enter to process selections)
4. Test exit (Q to quit)
5. Run through full setup.sh flow
