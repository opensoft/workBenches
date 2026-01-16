import { createSignal, onMount, For, type Component as SolidComponent } from 'solid-js';
import { useKeyboard } from '@opentui/solid';
import type { Component } from '../types';
import { initializeComponents } from '../utils/config';
import { loadAllStatuses } from '../utils/statusChecks';
import { useNavigation } from '../hooks/useNavigation';
import { Header } from './Header';
import { SectionColumn } from './SectionColumn';
import { StatusBar } from './StatusBar';
import { processSelections } from '../utils/installers';

/**
 * Main App component - orchestrates the setup UI
 */
export const App: SolidComponent = () => {
  const [benches, setBenches] = createSignal<Component[]>([]);
  const [aiTools, setAiTools] = createSignal<Component[]>([]);
  const [tools, setTools] = createSignal<Component[]>([]);
  const [isLoading, setIsLoading] = createSignal(true);

  /**
   * Toggle item selection and determine action
   */
  const handleToggle = (section: number, index: number) => {
    const updateItem = (items: Component[], idx: number): Component[] => {
      const newItems = [...items];
      const item = { ...newItems[idx] };

      const isInstalled = item.status === 'installed' || item.status === 'needs_creds';

      if (item.checked) {
        // Currently checked
        if (isInstalled) {
          // Installed item: toggle to uninstall
          item.action = 'uninstall';
          // Keep checked but marked for uninstall
        } else {
          // Not installed: uncheck (cancel install)
          item.checked = false;
          item.action = null;
        }
      } else {
        // Currently unchecked
        item.checked = true;
        if (isInstalled) {
          // Installed item: mark to keep (cancel uninstall)
          item.action = null;
        } else {
          // Not installed: mark to install
          item.action = 'install';
        }
      }

      newItems[idx] = item;
      return newItems;
    };

    switch (section) {
      case 0:
        setBenches(updateItem(benches(), index));
        break;
      case 1:
        setAiTools(updateItem(aiTools(), index));
        break;
      case 2:
        setTools(updateItem(tools(), index));
        break;
    }
  };

  /**
   * Handle confirmation - process selected items
   */
  const handleConfirm = async () => {
    // Exit the UI and process selections
    console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
    console.log('║               Applying Configuration Changes                                 ║');
    console.log('╚══════════════════════════════════════════════════════════════════════════════╝\n');

    await processSelections(benches(), aiTools(), tools());
    process.exit(0);
  };

  /**
   * Handle quit action
   */
  const handleQuit = () => {
    console.log('\nExiting without changes.');
    process.exit(0);
  };

  // Navigation hook - must be called at component level
  // Pass functions instead of values so navigation always works with current data
  const navigation = useNavigation({
    benches: benches,
    aiTools: aiTools,
    tools: tools,
    onToggle: handleToggle,
    onConfirm: handleConfirm,
    onQuit: handleQuit,
  });

  // Set up keyboard input directly using OpenTUI's useKeyboard hook
  // This MUST be called at the component level during render
  useKeyboard((event: any) => {
    let key = '';
    let ctrl = false;
    let shift = false;

    // Debug: log raw event structure
    if (event) {
      console.log('🎹 Keyboard event:', {
        keys: Object.keys(event),
        key: event.key,
        name: event.name,
        char: event.char,
      });
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

    console.log(`⌨️  Key mapped to: '${key}', ctrl: ${ctrl}, shift: ${shift}`);

    // Call the navigation handler
    navigation.handleKeyPress(key, ctrl, shift);
  });

  // Initialize components on mount
  onMount(async () => {
    try {
      const { benches: b, aiTools: ai, tools: t } = await initializeComponents();

      // Load statuses
      await loadAllStatuses(b, ai, t);

      setBenches(b);
      setAiTools(ai);
      setTools(t);
      setIsLoading(false);
    } catch (error) {
      console.error('Failed to initialize:', error);
      setIsLoading(false);
    }
  });

  if (isLoading()) {
    return (
      <box flexDirection="column">
        <Header />
        <text color="#FFFF6B">Loading components...</text>
      </box>
    );
  }

  return (
    <box flexDirection="column" height="100%" width="100%">
      {/* Header with banner and navigation help */}
      <Header />

      {/* Three-column layout */}
      <box flexDirection="row" gap={6}>
        {/* Dev Benches */}
        <SectionColumn
          title="DEV BENCHES"
          items={benches()}
          currentIndex={navigation.currentSection() === 0 ? navigation.currentIndex() : -1}
          isActive={navigation.currentSection() === 0}
          width={24}
        />

        {/* AI Assistants */}
        <SectionColumn
          title="AI ASSISTANTS"
          items={aiTools()}
          currentIndex={navigation.currentSection() === 1 ? navigation.currentIndex() : -1}
          isActive={navigation.currentSection() === 1}
          width={24}
        />

        {/* Tools */}
        <SectionColumn
          title="TOOLS"
          items={tools()}
          currentIndex={navigation.currentSection() === 2 ? navigation.currentIndex() : -1}
          isActive={navigation.currentSection() === 2}
          width={24}
        />
      </box>

      {/* Status bar */}
      <StatusBar
        benches={benches()}
        aiTools={aiTools()}
        tools={tools()}
      />
    </box>
  );
};

export default App;
