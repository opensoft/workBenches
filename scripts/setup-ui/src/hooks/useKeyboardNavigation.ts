import { useKeyboard } from '@opentui/solid';

/**
 * Hook to set up keyboard navigation using OpenTUI's event system
 *
 * This hook integrates with OpenTUI's keyboard event handling by using the
 * useKeyboard hook which is provided by @opentui/solid.
 */
export function useKeyboardNavigation(navigation: any) {
  // Use OpenTUI's keyboard hook to capture all keyboard events
  useKeyboard((event: any) => {
    let key = '';
    let ctrl = false;
    let shift = false;

    // Debug: log raw event structure
    if (event) {
      console.log('Raw keyboard event keys:', Object.keys(event));
      if (event.key) console.log('  - event.key:', event.key);
      if (event.name) console.log('  - event.name:', event.name);
      if (event.char) console.log('  - event.char:', event.char);
    } else {
      console.log('Raw keyboard event: null/undefined');
    }

    // Extract key information from OpenTUI's KeyEvent structure
    if (event) {
      // Try multiple ways to get the key name
      if (event.key) {
        const keyInfo = event.key;

        // Get the key name
        if (keyInfo.name) {
          key = keyInfo.name.toLowerCase();
        } else if (keyInfo.char) {
          key = keyInfo.char.toLowerCase();
        }

        // Check modifiers
        ctrl = !!(keyInfo.ctrl || keyInfo.meta);
        shift = !!keyInfo.shift;
      } else if (event.name) {
        // Direct name property
        key = event.name.toLowerCase();
        ctrl = !!event.ctrl;
        shift = !!event.shift;
      } else if (event.char) {
        // Direct char property
        key = event.char.toLowerCase();
      } else if (typeof event === 'string') {
        // String directly
        key = event.toLowerCase();
      }
    }

    // Normalize arrow key names from OpenTUI format
    const keyMap: Record<string, string> = {
      'arrowup': 'up',
      'arrowdown': 'down',
      'arrowleft': 'left',
      'arrowright': 'right',
      'up': 'up',
      'down': 'down',
      'left': 'left',
      'right': 'right',
      'return': 'enter',
      'enter': 'enter',
      'space': ' ',
      ' ': ' ',
      'q': 'q',
    };

    if (keyMap[key]) {
      key = keyMap[key];
    }

    // Skip empty keys
    if (!key) {
      return;
    }

    // Log for debugging (temporary - to verify key detection)
    console.log(`Key pressed: '${key}', ctrl: ${ctrl}, shift: ${shift}`);

    // Call the navigation handler
    if (navigation && navigation.handleKeyPress) {
      navigation.handleKeyPress(key, ctrl, shift);
    }
  });
}
