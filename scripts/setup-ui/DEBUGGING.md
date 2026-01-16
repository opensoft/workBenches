# Debugging Arrow Key Issues

## Key Fix Applied

The `useKeyboard` hook has been moved to the **component level** in App.tsx. This is critical because in Solid.js, hooks must be called at the component render phase, not nested inside other functions.

## How to Test

Run the app in an interactive terminal and press arrow keys. Watch the console for debug output.

### From setup.sh:
```bash
./setup.sh
```

### Direct:
```bash
cd scripts/setup-ui
bun run start
```

## What to Look For

When you press **any key**, you should see console output like:

```
🎹 Keyboard event: {
  keys: [ 'key' ],
  key: { name: 'ArrowUp', char: undefined, ctrl: false, shift: false, meta: false },
  name: undefined,
  char: undefined
}
⌨️  Key mapped to: 'up', ctrl: false, shift: false
```

### Debug Markers

- **🎹 Keyboard event:** - Raw event from OpenTUI
- **⌨️ Key mapped to:** - What the app detected and sent to navigation

## If Arrow Keys Still Don't Work

### Check 1: Are keyboard events being detected at all?

Press **q** - you should see:
```
🎹 Keyboard event: { ... key: { name: 'q', ... } ... }
⌨️  Key mapped to: 'q', ctrl: false, shift: false
```

If you see **NO** console output for any key, then:
- OpenTUI's useKeyboard hook isn't working
- The component might not have focus
- OpenTUI's keyboard system might need initialization

### Check 2: Are arrow keys being detected differently than expected?

Looking at the raw event, check if arrow keys show:
- `name: 'ArrowUp'` or `name: 'up'`?
- `char` instead of `name`?
- Something completely different?

Update the keyMap in App.tsx accordingly.

### Check 3: Is navigation being called?

The console should show the mapped key. If it does, then:
- Navigation handler IS being called
- The issue is that navigation state isn't changing the display

To test this, look at the next render - are the selection markers (▶) moving?

### Check 4: Are signals properly reactive?

Add this debugging to check if signals are updating:

In App.tsx, add after `useKeyboard` callback:

```typescript
// Debug signal changes
createEffect(() => {
  console.log('Navigation state changed:', {
    section: navigation.currentSection(),
    index: navigation.currentIndex(),
    benches: benches().length,
  });
});
```

## Potential Issues

### Issue 1: useKeyboard Hook Not Working

**Symptoms:** No keyboard event logs appear

**Solution:**
- The useKeyboard hook requires OpenTUI's RendererContext to be available
- This is set up by OpenTUI's render() function
- If it's not working, OpenTUI's initialization might have failed

**Check:** Look at startup - any errors before the UI appears?

### Issue 2: Component Not Re-rendering on Navigation Change

**Symptoms:** Keyboard events logged, key mapped, but selection doesn't move

**Solution:**
- The signals might not be triggering component updates
- Need to verify that SelectableItem is re-rendering when currentIndex changes

**Check:** In SelectableItem.tsx, verify it's using signals as functions:
```typescript
isSelected={index() === props.currentIndex}  // ← Must call currentIndex as function
```

### Issue 3: Navigation State Not Updating

**Symptoms:** Keyboard mapped correctly but navigation handler not working

**Solution:**
- The navigation.handleKeyPress might not be updating the signals
- The moveUp/moveDown functions might have issues

**Check:** Add logging to useNavigation.ts:
```typescript
const moveUp = () => {
  console.log('moveUp called, current index:', currentIndex());
  // ... rest of function
  console.log('moveUp result, new index:', currentIndex());
};
```

## Getting More Information

### To see raw OpenTUI event structure

Uncomment the detailed logging in App.tsx (line 111):

```typescript
console.log('🎹 Keyboard event:', {
  keys: Object.keys(event),
  key: event.key,
  name: event.name,
  char: event.char,
});
```

### To trace navigation state changes

Add to useNavigation.ts handleKeyPress:

```typescript
const handleKeyPress = (key: string, ctrl: boolean, shift: boolean) => {
  console.log(`🔄 handleKeyPress: key='${key}', section=${currentSection()}, index=${currentIndex()}`);

  // ... existing code ...

  console.log(`✅ After handling: section=${currentSection()}, index=${currentIndex()}`);
};
```

## Testing Sequence

1. **Run the app** - `bun run start`
2. **Press 'q'** - Should see keyboard events in console
3. **Press up arrow** - Should see event + mapped key in console
4. **Observe display** - Does selection marker (▶) move?
5. **Press space** - Should toggle item (if working)

## Report Format

If arrow keys still don't work after this fix, provide:

```
[When you press up arrow, paste the EXACT console output]

What you see on screen:
[Do the selection markers move? Does anything change?]

What you expect:
[Selection should move up, marker should move to previous item]
```

This will help identify exactly where the issue is in the chain:
Event Detection → Key Mapping → Navigation Update → Component Re-render
