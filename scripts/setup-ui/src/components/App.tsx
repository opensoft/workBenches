import { createSignal, For, type Component as SolidComponent } from 'solid-js';
import { useKeyboard, useRenderer } from '@opentui/solid';
import type { Component } from '../types';
import { initializeComponents } from '../utils/config';
import { loadAllStatuses } from '../utils/statusChecks';
import { useNavigation } from '../hooks/useNavigation';
import { Header } from './Header';
import { SectionColumn } from './SectionColumn';
import { StatusBar } from './StatusBar';
import { processSelections } from '../utils/installers';
import { writeFileSync } from 'fs';

const DEBUG_FILE = '/home/brett/setup-ui-debug.log';

function debugLog(msg: string) {
  try {
    const timestamp = new Date().toISOString();
    writeFileSync(DEBUG_FILE, `[${timestamp}] ${msg}\n`, { flag: 'a' });
  } catch (e) {
    // Silently fail if we can't write
  }
}

/**
 * Main App component - orchestrates the setup UI
 */
export const App: SolidComponent = () => {
  // Debug: confirm component is rendering
  debugLog('=== APP COMPONENT RENDERING ===');

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

  // Queue for keypresses that come in before initialization is complete
  const keyPressQueue: Array<{ key: string; ctrl: boolean; shift: boolean }> = [];
  let isInitComplete = false;

  // Get renderer reference early so we can force re-renders
  debugLog('=== Getting renderer for requestRender ===');
  let rendererRef: any = null;
  try {
    rendererRef = useRenderer();
    debugLog(`Renderer for requestRender: ${rendererRef ? 'obtained' : 'null'}`);
  } catch (e) {
    debugLog(`Failed to get renderer for requestRender: ${e}`);
  }

  // Function to force renderer to redraw
  const forceRender = () => {
    debugLog('🔄 forceRender called');
    if (rendererRef?.root) {
      debugLog('  Calling root.requestRender()');
      rendererRef.root.requestRender();
    } else if (rendererRef?._root) {
      debugLog('  Calling _root.requestRender()');
      rendererRef._root.requestRender();
    } else {
      debugLog('  No root found on renderer');
    }
  };

  // Navigation hook - must be called at component level FIRST
  // Pass functions instead of values so navigation always works with current data
  const navigation = useNavigation({
    benches: benches,
    aiTools: aiTools,
    tools: tools,
    onToggle: handleToggle,
    onConfirm: handleConfirm,
    onQuit: handleQuit,
    requestRender: forceRender,
  });

  // Initialize components immediately
  let initPromise: Promise<void> | null = null;
  debugLog('=== Starting immediate component initialization ===');

  initPromise = (async () => {
    try {
      debugLog('Calling initializeComponents (IMMEDIATE)...');
      const { benches: b, aiTools: ai, tools: t } = await initializeComponents();
      debugLog(`initializeComponents returned: ${b.length} benches, ${ai.length} aiTools, ${t.length} tools`);

      debugLog('Calling loadAllStatuses (IMMEDIATE)...');
      await loadAllStatuses(b, ai, t);
      debugLog('loadAllStatuses completed');

      debugLog('Setting state with loaded components (IMMEDIATE)...');
      debugLog(`  Before setState: benches()=${benches().length}, aiTools()=${aiTools().length}, tools()=${tools().length}`);
      setBenches(b);
      setAiTools(ai);
      setTools(t);
      setIsLoading(false);

      // Force a small delay to allow SolidJS to update signals
      await new Promise(resolve => setTimeout(resolve, 10));
      debugLog(`  After setState: benches()=${benches().length}, aiTools()=${aiTools().length}, tools()=${tools().length}`);

      // Mark initialization as complete
      isInitComplete = true;
      debugLog('=== IMMEDIATE initialization COMPLETED - Components loaded! ===');

      // Process any queued keypresses
      debugLog(`Queue length: ${keyPressQueue.length}`);
      if (keyPressQueue.length > 0) {
        debugLog(`Processing ${keyPressQueue.length} queued keypresses...`);
        while (keyPressQueue.length > 0) {
          const queued = keyPressQueue.shift()!;
          debugLog(`  About to replay queued: key='${queued.key}', available items: benches()=${benches().length}, aiTools()=${aiTools().length}, tools()=${tools().length}`);
          navigation.handleKeyPress(queued.key, queued.ctrl, queued.shift);
          debugLog(`  After replay: key='${queued.key}'`);
        }
      } else {
        debugLog('No queued keypresses to process');
      }
    } catch (error) {
      debugLog(`=== IMMEDIATE initialization FAILED: ${error} ===`);
      console.error('Failed to initialize:', error);
      setIsLoading(false);
      isInitComplete = true; // Mark as complete even on error to unblock queue
    }
  })();

  // Buffer for escape sequences
  let escapeBuffer = '';

  // Use the renderer we already obtained to attach keyboard handler
  debugLog('=== Attaching keyboard handler to renderer ===');
  if (rendererRef) {
    debugLog(`Renderer type: ${rendererRef.constructor?.name}`);

    // Try to access keyboard handler
    if ((rendererRef as any)._keyHandler) {
      debugLog(`Found _keyHandler on renderer`);
      const keyHandler = (rendererRef as any)._keyHandler;

      // Try to listen to keypress events using onInternal for InternalKeyHandler
      try {
        const handler = (event: any) => {
          let key = event?.name?.toLowerCase?.() || '';
          let ctrl = !!event?.ctrl;
          let shift = !!event?.shift;

          debugLog(`🎹 RAW EVENT from _keyHandler: name='${key}', shift=${shift}, isInitComplete=${isInitComplete}, queueLen=${keyPressQueue.length}`);

          // Handle escape sequences for arrow keys
          // Arrow keys come as: [ (escape) followed by a/b/c/d (case-insensitive)
          if (key === '[') {
            // Start of escape sequence
            escapeBuffer = '[';
            debugLog(`   Escape sequence started`);
            return;
          } else if (escapeBuffer === '[' && key.length === 1 && /[abcd]/i.test(key)) {
            // Complete escape sequence (normalize to lowercase)
            const normalizedKey = key.toLowerCase();
            const arrowMap: Record<string, string> = {
              'a': 'up',    // ESC [ A = up
              'b': 'down',  // ESC [ B = down
              'c': 'right', // ESC [ C = right
              'd': 'left',  // ESC [ D = left
            };
            key = arrowMap[normalizedKey] || key;
            escapeBuffer = '';
            debugLog(`   Escape sequence complete: [${normalizedKey} -> ${key}`);
          } else {
            // Not part of escape sequence, clear buffer
            if (escapeBuffer) {
              debugLog(`   Escape sequence cancelled (got: ${key})`);
            }
            escapeBuffer = '';
          }

          // Normalize other key names
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
            'i': 'i',
            'j': 'j',
            'k': 'k',
            'l': 'l',
            'u': 'u',
            'o': 'o',
            'h': 'h',
          };

          if (keyMap[key]) {
            key = keyMap[key];
          }

          if (key) {
            debugLog(`⌨️ KEY: '${key}', ctrl=${ctrl}, shift=${shift}`);
            navigation.handleKeyPress(key, ctrl, shift);
          }
        };

        // Try onInternal first (for InternalKeyHandler)
        if (keyHandler.onInternal) {
          keyHandler.onInternal('keypress', handler);
          debugLog(`Attached keypress listener using onInternal`);
        } else if (keyHandler.on) {
          keyHandler.on('keypress', handler);
          debugLog(`Attached keypress listener using on`);
        }
      } catch (e) {
        debugLog(`Failed to attach keypress listener: ${e}`);
      }
    }
  }

  // Set up keyboard input directly using OpenTUI's useKeyboard hook
  // This MUST be called at the component level during render
  debugLog('=== Setting up useKeyboard hook ===');
  useKeyboard((event: any) => {
    debugLog(`🎹 KEYBOARD EVENT FIRED!!! (isInitComplete=${isInitComplete})`);
    debugLog(`   Full event: ${JSON.stringify(event)}`);
    debugLog(`   event.name: ${event?.name}`);
    debugLog(`   event.ctrl: ${event?.ctrl}`);
    debugLog(`   event.shift: ${event?.shift}`);
    debugLog(`   Queue length: ${keyPressQueue.length}`);

    // Extract key name - KeyEvent structure has name directly
    let key = event?.name?.toLowerCase?.() || '';
    let ctrl = !!event?.ctrl;
    let shift = !!event?.shift;

    debugLog(`   Raw extracted key: '${key}'`);

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
      'i': 'i',
      'j': 'j',
      'k': 'k',
      'l': 'l',
      'u': 'u',
      'o': 'o',
      'h': 'h',
    };

    const mappedKey = keyMap[key];
    if (mappedKey) {
      debugLog(`   Mapped: '${key}' → '${mappedKey}'`);
      key = mappedKey;
    } else {
      debugLog(`   No mapping for: '${key}'`);
    }

    // Skip empty keys
    if (!key) {
      debugLog('   ⚠️  SKIPPING: Empty key!');
      return;
    }

    debugLog(`⌨️  Key mapped to: '${key}', ctrl: ${ctrl}, shift: ${shift}`);

    // If initialization is not complete yet, queue this keypress for later replay
    if (!isInitComplete) {
      debugLog(`   ⏳ Initialization not complete, queueing keypress: '${key}'`);
      keyPressQueue.push({ key, ctrl, shift });
      return;
    }

    // Call the navigation handler
    navigation.handleKeyPress(key, ctrl, shift);
  });


  if (isLoading()) {
    return (
      <box flexDirection="column">
        <Header />
        <text fg="#FFFF6B">Loading components...</text>
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
          currentIndex={() => navigation.currentSection() === 0 ? navigation.currentIndex() : -1}
          isActive={() => navigation.currentSection() === 0}
          width={24}
        />

        {/* AI Assistants */}
        <SectionColumn
          title="AI ASSISTANTS"
          items={aiTools()}
          currentIndex={() => navigation.currentSection() === 1 ? navigation.currentIndex() : -1}
          isActive={() => navigation.currentSection() === 1}
          width={24}
        />

        {/* Tools */}
        <SectionColumn
          title="TOOLS"
          items={tools()}
          currentIndex={() => navigation.currentSection() === 2 ? navigation.currentIndex() : -1}
          isActive={() => navigation.currentSection() === 2}
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
