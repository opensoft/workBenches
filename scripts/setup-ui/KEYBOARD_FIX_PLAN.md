# Plan: Fix Keyboard Navigation in Setup UI

## Problem Summary

Keyboard navigation only works after holding keys down for several seconds. Single keypresses don't move the cursor visually, even though the internal state updates correctly.

## Root Cause Analysis

Based on review of [OpenTUI source code](https://github.com/sst/opentui) and debug logs:

### Issue 1: Wrong Keyboard API
**Current code** uses private internal API:
```typescript
renderer._keyHandler.onInternal('keypress', handler)
```

**Correct approach** per [OpenTUI hooks.ts](https://github.com/sst/opentui/blob/main/packages/solid/src/elements/hooks.ts):
```typescript
renderer.keyInput.on('keypress', handler)  // Public API
```

The `useKeyboard` hook uses `renderer.keyInput`, not `_keyHandler`.

### Issue 2: useKeyboard Hook Not Firing
Debug logs show `useKeyboard` fired 0 events while `_keyHandler.onInternal` fired 1092 events. This suggests either:
- The hook isn't registering (component lifecycle issue)
- The `keyInput` EventEmitter path differs from `_keyHandler`

### Issue 3: SolidJS Reactivity Outside Reactive Context
When using `_keyHandler.onInternal` directly (bypassing OpenTUI's intended flow), signal updates happen outside SolidJS's reactive tracking. The renderer doesn't get notified to redraw.

### Issue 4: Mouse Event Noise
The terminal sends SGR mouse tracking events (`<35;26;9M` format) that flood the key handler. These are being parsed character-by-character, creating noise.

## Proposed Solutions

### Solution A: Use OpenTUI's useKeyboard Properly (Recommended)

1. **Remove** the manual `_keyHandler.onInternal` keyboard attachment
2. **Keep** only the `useKeyboard` hook
3. **Debug** why `useKeyboard` isn't firing:
   - Check if `renderer.keyInput` exists and is the correct EventEmitter
   - Verify the callback is being registered in `onMount`
   - Check if there's a timing issue with component mounting

```typescript
// In App.tsx - simplified approach
useKeyboard((event) => {
  const key = event.name?.toLowerCase() || '';
  const ctrl = !!event.ctrl;
  const shift = !!event.shift;

  // Map arrow keys
  const keyMap: Record<string, string> = {
    'arrowup': 'up', 'arrowdown': 'down',
    'arrowleft': 'left', 'arrowright': 'right',
    'return': 'enter', 'space': ' ',
  };

  const mappedKey = keyMap[key] || key;
  if (mappedKey) {
    navigation.handleKeyPress(mappedKey, ctrl, shift);
  }
});
```

### Solution B: Fix the Direct Handler Approach

If `useKeyboard` truly doesn't work, fix the direct approach:

1. **Use correct public API**: `renderer.keyInput` instead of `_keyHandler`
2. **Trigger SolidJS reactivity**: Use `batch()` from solid-js to group updates
3. **Force renderer update**: Call `requestRender()` after state changes

```typescript
import { batch } from 'solid-js';

// In keyboard handler
batch(() => {
  navigation.handleKeyPress(key, ctrl, shift);
});
rendererRef.root?.requestRender();
```

### Solution C: Use OpenTUI's Built-in Components

OpenTUI has built-in interactive components with keyboard support:
- `<select>` - List with up/down/j/k navigation
- `<tab_select>` - Tabs with left/right navigation

These handle focus and keyboard automatically. Consider refactoring to use:

```tsx
<select
  focused
  options={items.map(i => ({ label: i.name, value: i.id }))}
  onChange={(e) => handleSelection(e.index)}
/>
```

## Implementation Steps

### Phase 1: Diagnose useKeyboard (30 min)

1. Add debug logging to verify `renderer.keyInput` exists
2. Check if `onMount` callback fires
3. Verify the EventEmitter is receiving events
4. Compare `keyInput` vs `_keyHandler` - are they the same object?

```typescript
// Diagnostic code
const renderer = useRenderer();
debugLog(`keyInput exists: ${!!renderer.keyInput}`);
debugLog(`keyInput === _keyHandler: ${renderer.keyInput === (renderer as any)._keyHandler}`);

onMount(() => {
  debugLog('onMount fired - registering keypress listener');
  renderer.keyInput.on('keypress', (e) => {
    debugLog(`keyInput event: ${e.name}`);
  });
});
```

### Phase 2: Fix Keyboard Handler

Based on Phase 1 findings, either:
- Fix `useKeyboard` if it's a registration issue
- Switch to `renderer.keyInput.on()` if that's the working path
- Ensure `requestRender()` is called after state changes

### Phase 3: Filter Mouse Events

Add filtering to ignore SGR mouse tracking sequences:

```typescript
// Skip mouse event sequences
if (key === '[' || /^[0-9;<mM]$/.test(key)) {
  // Likely part of mouse tracking sequence
  return;
}
```

### Phase 4: Test & Verify

1. Clear debug log
2. Run app, press single down arrow
3. Verify:
   - Key event logged immediately
   - State changes (currentIndex updates)
   - UI redraws (cursor visually moves)

## Files to Modify

1. `/src/components/App.tsx` - Main keyboard handler setup
2. `/src/hooks/useNavigation.ts` - Navigation state management
3. Possibly `/src/components/SectionColumn.tsx` - If focus is needed

## References

- [OpenTUI GitHub](https://github.com/sst/opentui)
- [OpenTUI Solid Hooks Source](https://github.com/sst/opentui/blob/main/packages/solid/src/elements/hooks.ts)
- [OpenTUI Getting Started](https://github.com/sst/opentui/blob/main/packages/core/docs/getting-started.md)
- [Issue #313 - Keyboard Input Mapping](https://github.com/sst/opentui/issues/313)
