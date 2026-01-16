import { createSignal, createEffect, onCleanup } from 'solid-js';
import type { Component } from '../types';

interface NavigationState {
  currentSection: number; // 0=Benches, 1=AI, 2=Tools
  currentIndex: number;
}

interface UseNavigationOptions {
  benches: Component[];
  aiTools: Component[];
  tools: Component[];
  onToggle: (section: number, index: number) => void;
  onConfirm: () => void;
  onQuit: () => void;
}

/**
 * Hook for keyboard navigation in the setup UI
 */
export function useNavigation(options: UseNavigationOptions) {
  const [currentSection, setCurrentSection] = createSignal(0);
  const [currentIndex, setCurrentIndex] = createSignal(0);

  /**
   * Get the items for the current section
   */
  const getCurrentItems = (): Component[] => {
    switch (currentSection()) {
      case 0:
        return options.benches;
      case 1:
        return options.aiTools;
      case 2:
        return options.tools;
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
    const item = options.aiTools[index];
    return item?.isSeparator ?? false;
  };

  /**
   * Move up, skipping separators
   */
  const moveUp = () => {
    let newIndex = currentIndex() - 1;

    // Skip separators
    while (newIndex >= 0 && isOnSeparator(newIndex)) {
      newIndex--;
    }

    if (newIndex >= 0) {
      setCurrentIndex(newIndex);
    }
  };

  /**
   * Move down, skipping separators
   */
  const moveDown = () => {
    const maxIdx = getMaxIndex();
    let newIndex = currentIndex() + 1;

    // Skip separators
    while (newIndex <= maxIdx && isOnSeparator(newIndex)) {
      newIndex++;
    }

    if (newIndex <= maxIdx) {
      setCurrentIndex(newIndex);
    }
  };

  /**
   * Switch to previous section
   */
  const moveLeft = () => {
    if (currentSection() > 0) {
      setCurrentSection(currentSection() - 1);
      setCurrentIndex(0);
    }
  };

  /**
   * Switch to next section
   */
  const moveRight = () => {
    if (currentSection() < 2) {
      setCurrentSection(currentSection() + 1);
      setCurrentIndex(0);
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
  };

  /**
   * Handle keyboard input
   */
  const handleKeyPress = (key: string, ctrl: boolean, shift: boolean) => {
    // Quit
    if (key === 'q' || key === 'Q') {
      options.onQuit();
      return;
    }

    // Confirm
    if (key === 'enter' || key === 'return') {
      options.onConfirm();
      return;
    }

    // Toggle
    if (key === ' ' || key === 'space') {
      toggleCurrent();
      return;
    }

    // Navigation
    switch (key) {
      case 'up':
      case 'k':
        moveUp();
        break;
      case 'down':
      case 'j':
        moveDown();
        break;
      case 'left':
      case 'h':
        moveLeft();
        break;
      case 'right':
      case 'l':
        moveRight();
        break;
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
