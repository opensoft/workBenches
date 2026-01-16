import { createSignal, createEffect, onCleanup } from 'solid-js';
import type { Component } from '../types';

interface NavigationState {
  currentSection: number; // 0=Benches, 1=AI, 2=Tools
  currentIndex: number;
}

interface UseNavigationOptions {
  benches: () => Component[];
  aiTools: () => Component[];
  tools: () => Component[];
  onToggle: (section: number, index: number) => void;
  onConfirm: () => void;
  onQuit: () => void;
  requestRender?: () => void;  // Optional callback to force renderer update
}

/**
 * Hook for keyboard navigation in the setup UI
 */
export function useNavigation(options: UseNavigationOptions) {
  const [currentSection, setCurrentSection] = createSignal(0);
  const [currentIndex, setCurrentIndex] = createSignal(0);

  // Debug logging
  const debugLog = (msg: string) => {
    try {
      require('fs').writeFileSync(
        '/home/brett/setup-ui-debug.log',
        `[${new Date().toISOString()}] ${msg}\n`,
        { flag: 'a' }
      );
    } catch (e) {
      // Silently fail
    }
  };

  /**
   * Get the items for the current section
   * Calls the functions to get fresh data every time
   */
  const getCurrentItems = (): Component[] => {
    switch (currentSection()) {
      case 0:
        return options.benches();
      case 1:
        return options.aiTools();
      case 2:
        return options.tools();
      default:
        return [];
    }
  };

  /**
   * Get max index for current section
   */
  const getMaxIndex = (): number => {
    return getCurrentItems().length - 1;
  };

  /**
   * Check if current index is on a separator (AI section only)
   */
  const isOnSeparator = (index: number): boolean => {
    if (currentSection() !== 1) return false;
    const item = options.aiTools()[index];
    return item?.isSeparator ?? false;
  };

  /**
   * Move up, skipping separators
   */
  const moveUp = () => {
    debugLog(`moveUp called: currentIndex=${currentIndex()}`);
    let newIndex = currentIndex() - 1;

    // Skip separators
    while (newIndex >= 0 && isOnSeparator(newIndex)) {
      newIndex--;
    }

    if (newIndex >= 0) {
      debugLog(`  setCurrentIndex(${newIndex})`);
      setCurrentIndex(newIndex);
      debugLog(`  After setCurrentIndex: currentIndex()=${currentIndex()}`);
      options.requestRender?.();
    } else {
      debugLog(`  newIndex=${newIndex} is out of bounds`);
    }
  };

  /**
   * Move down, skipping separators
   */
  const moveDown = () => {
    debugLog(`moveDown called: currentIndex=${currentIndex()}`);
    const maxIdx = getMaxIndex();
    let newIndex = currentIndex() + 1;

    // Skip separators
    while (newIndex <= maxIdx && isOnSeparator(newIndex)) {
      newIndex++;
    }

    if (newIndex <= maxIdx) {
      debugLog(`  setCurrentIndex(${newIndex})`);
      setCurrentIndex(newIndex);
      debugLog(`  After setCurrentIndex: currentIndex()=${currentIndex()}`);
      options.requestRender?.();
    } else {
      debugLog(`  newIndex=${newIndex} exceeds maxIdx=${maxIdx}`);
    }
  };

  /**
   * Switch to previous section
   */
  const moveLeft = () => {
    debugLog(`moveLeft called: currentSection=${currentSection()}`);
    if (currentSection() > 0) {
      debugLog(`  setCurrentSection(${currentSection() - 1})`);
      setCurrentSection(currentSection() - 1);
      setCurrentIndex(0);
      debugLog(`  After move: section=${currentSection()}, index=${currentIndex()}`);
      options.requestRender?.();
    } else {
      debugLog(`  Already at first section`);
    }
  };

  /**
   * Switch to next section
   */
  const moveRight = () => {
    debugLog(`moveRight called: currentSection=${currentSection()}`);
    if (currentSection() < 2) {
      debugLog(`  setCurrentSection(${currentSection() + 1})`);
      setCurrentSection(currentSection() + 1);
      setCurrentIndex(0);
      debugLog(`  After move: section=${currentSection()}, index=${currentIndex()}`);
      options.requestRender?.();
    } else {
      debugLog(`  Already at last section`);
    }
  };

  /**
   * Toggle selection for current item
   */
  const toggleCurrent = () => {
    const items = getCurrentItems();
    const item = items[currentIndex()];

    // Skip separators
    if (item?.isSeparator) return;

    options.onToggle(currentSection(), currentIndex());
    options.requestRender?.();
  };

  /**
   * Handle keyboard input
   */
  const handleKeyPress = (key: string, ctrl: boolean, shift: boolean) => {
    debugLog(`📍 handleKeyPress: key='${key}', section=${currentSection()}, index=${currentIndex()}`);

    // Check if components are loaded before allowing navigation
    const items = getCurrentItems();
    if (items.length === 0) {
      debugLog('   ⚠️  No items available yet (components still loading)');
      return;
    }

    // Quit
    if (key === 'q' || key === 'Q') {
      debugLog('❌ Quit requested');
      options.onQuit();
      return;
    }

    // Confirm
    if (key === 'enter' || key === 'return') {
      debugLog('✅ Confirm requested');
      options.onConfirm();
      return;
    }

    // Toggle
    if (key === ' ' || key === 'space') {
      debugLog('🔄 Toggle requested');
      toggleCurrent();
      debugLog(`   After toggle: section=${currentSection()}, index=${currentIndex()}`);
      return;
    }

    // Navigation - Support arrow keys, vim-style (hjkl), and IJKL
    // Vim keys: h=left, j=down, k=up, l=right
    // IJKL layout: i=up, j=left, k=down, l=right
    switch (key) {
      case 'up':
      case 'k':
      case 'i':
        debugLog('⬆️  Move up');
        moveUp();
        debugLog(`   After moveUp: section=${currentSection()}, index=${currentIndex()}`);
        break;
      case 'down':
      case 'j':
        debugLog('⬇️  Move down');
        moveDown();
        debugLog(`   After moveDown: section=${currentSection()}, index=${currentIndex()}`);
        break;
      case 'left':
      case 'h':
      case 'u':
        debugLog('⬅️  Move left');
        moveLeft();
        debugLog(`   After moveLeft: section=${currentSection()}, index=${currentIndex()}`);
        break;
      case 'right':
      case 'l':
      case 'o':
        debugLog('➡️  Move right');
        moveRight();
        debugLog(`   After moveRight: section=${currentSection()}, index=${currentIndex()}`);
        break;
      default:
        debugLog(`   Unknown key: ${key}`);
    }
  };

  return {
    currentSection,
    currentIndex,
    handleKeyPress,
    moveUp,
    moveDown,
    moveLeft,
    moveRight,
    toggleCurrent,
  };
}

/**
 * Parse raw stdin data into key events
 * Based on terminal escape sequences
 */
export function parseKeyInput(data: Buffer): { key: string; ctrl: boolean; shift: boolean } | null {
  const str = data.toString();

  // Ctrl+C
  if (str === '\x03') {
    return { key: 'q', ctrl: true, shift: false };
  }

  // Enter
  if (str === '\r' || str === '\n') {
    return { key: 'enter', ctrl: false, shift: false };
  }

  // Space
  if (str === ' ') {
    return { key: ' ', ctrl: false, shift: false };
  }

  // Escape sequences (arrow keys)
  if (str.startsWith('\x1b[')) {
    const code = str.slice(2);
    switch (code) {
      case 'A':
        return { key: 'up', ctrl: false, shift: false };
      case 'B':
        return { key: 'down', ctrl: false, shift: false };
      case 'C':
        return { key: 'right', ctrl: false, shift: false };
      case 'D':
        return { key: 'left', ctrl: false, shift: false };
      case '1;2A':
        return { key: 'up', ctrl: false, shift: true };
      case '1;2B':
        return { key: 'down', ctrl: false, shift: true };
    }
  }

  // Regular characters
  if (str.length === 1) {
    const char = str.toLowerCase();
    return { key: char, ctrl: false, shift: str !== char };
  }

  return null;
}
