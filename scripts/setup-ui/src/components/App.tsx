import { createSignal, onMount, createMemo, createEffect, batch, type Component as SolidComponent } from 'solid-js';
import { useRenderer, useKeyboard } from '@opentui/solid';
import type { Component } from '../types';
import { initializeComponents } from '../utils/config';
import { loadAllStatuses } from '../utils/statusChecks';
import { Header } from './Header';
import { StatusBar } from './StatusBar';
import { processSelections } from '../utils/installers';
import { writeFileSync } from 'fs';
import type { KeyEvent } from '@opentui/core';

const DEBUG_FILE = '/home/brett/setup-ui-debug.log';
let rendererStarted = false;
let keyInputInitialized = false;

function debugLog(msg: string) {
  try {
    const timestamp = new Date().toISOString();
    writeFileSync(DEBUG_FILE, `[${timestamp}] ${msg}\n`, { flag: 'a' });
  } catch (e) {
    // Silently fail if we can't write
  }
}

/**
 * Format component for select option display
 */
function formatOption(comp: Component): { name: string; description: string; value: Component } {
  const checkbox = comp.checked
    ? (comp.action === 'uninstall' ? '[X]' : '[✓]')
    : '[ ]';
  const status = comp.status === 'installed' ? '✓'
    : comp.status === 'needs_creds' ? '⚠'
    : '✗';
  return {
    name: `${checkbox} ${status} ${comp.name}`,
    description: comp.status === 'installed' ? 'Installed'
      : comp.status === 'needs_creds' ? 'Needs credentials'
      : 'Not installed',
    value: comp,
  };
}

/**
 * Main App component - uses native OpenTUI select for keyboard navigation
 */
export const App: SolidComponent = () => {
  debugLog('=== APP COMPONENT RENDERING ===');

  const [benches, setBenches] = createSignal<Component[]>([]);
  const [aiTools, setAiTools] = createSignal<Component[]>([]);
  const [tools, setTools] = createSignal<Component[]>([]);
  const [isLoading, setIsLoading] = createSignal(true);
  const [activeColumn, setActiveColumn] = createSignal(0);

  const renderer = useRenderer();
  debugLog(`Renderer obtained: ${!!renderer}`);
  debugLog(`keyInput exists: ${!!renderer?.keyInput}`);
  debugLog(`Renderer controlState: ${(renderer as any)?.controlState}`);
  debugLog(`solid onMount impl: ${onMount.toString().replace(/\s+/g, ' ').slice(0, 80)}...`);
  debugLog(`stdin.isTTY: ${process.stdin.isTTY}`);
  debugLog(`stdin.isRaw: ${(process.stdin as any).isRaw}`);

  if (!rendererStarted) {
    rendererStarted = true;
    debugLog('Ensuring renderer is running');
    if (!renderer.isRunning) {
      renderer.start();
    }
  }

  if (!keyInputInitialized) {
    keyInputInitialized = true;
    debugLog('Registering direct keyInput logger');
    renderer.keyInput.on('keypress', (event) => {
      const key = event?.name || '';
      const sequence = event?.sequence || '';
      debugLog(`(direct) keypress: "${key}" seq="${sequence.replace(/\x1b/g, 'ESC')}"`);
    });
  }

  // Track the current selected index per column
  const [selectedIndices, setSelectedIndices] = createSignal<[number, number, number]>([0, 0, 0]);

  // Direct keyboard event listener for comprehensive debugging
  onMount(() => {
    debugLog('onMount fired - setting up keyboard handlers');
    const keyInput = renderer?.keyInput;
    if (keyInput) {
      debugLog('keyInput EventEmitter found, registering handler');
      debugLog(`keyInput listeners before: ${keyInput.listenerCount?.('keypress') ?? 'unknown'}`);

      // Also check the internal key input
      const internalKeyInput = (renderer as any)?._internalKeyInput;
      debugLog(`_internalKeyInput exists: ${!!internalKeyInput}`);
    } else {
      debugLog('ERROR: keyInput is null/undefined');
    }

    // Check stdin state
    debugLog(`stdin.isTTY: ${process.stdin.isTTY}`);
    debugLog(`stdin.isRaw: ${(process.stdin as any).isRaw}`);

    // Ensure the renderer runs so key-driven updates repaint immediately.
    if (!renderer.isRunning) {
      debugLog('Renderer was idle; starting render loop');
      renderer.start();
    }
  });

  debugLog('Setting up component...');

  const handleConfirm = async () => {
    console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
    console.log('║               Applying Configuration Changes                                 ║');
    console.log('╚══════════════════════════════════════════════════════════════════════════════╝\n');

    await processSelections(benches(), aiTools(), tools());
    process.exit(0);
  };

  // Handle selection change in a column
  const handleSelectionChange = (column: number, index: number) => {
    debugLog(`Selection changed: column=${column}, index=${index}`);
  };

  // Handle item selected (space/enter pressed)
  const handleItemSelected = (column: number, index: number) => {
    debugLog(`Item selected: column=${column}, index=${index}`);

    const toggleItem = (items: Component[], idx: number): Component[] => {
      const newItems = [...items];
      const item = { ...newItems[idx] };
      const isInstalled = item.status === 'installed' || item.status === 'needs_creds';

      if (item.checked) {
        if (isInstalled) {
          item.action = 'uninstall';
        } else {
          item.checked = false;
          item.action = null;
        }
      } else {
        item.checked = true;
        item.action = isInstalled ? null : 'install';
      }

      newItems[idx] = item;
      return newItems;
    };

    switch (column) {
      case 0:
        setBenches(toggleItem(benches(), index));
        break;
      case 1:
        setAiTools(toggleItem(aiTools(), index));
        break;
      case 2:
        setTools(toggleItem(tools(), index));
        break;
    }
  };

  // Initialize components immediately (don't wait for onMount)
  debugLog('Starting immediate initialization...');
  (async () => {
    try {
      debugLog('Calling initializeComponents...');
      const { benches: b, aiTools: ai, tools: t } = await initializeComponents();
      debugLog(`Loaded: ${b.length} benches, ${ai.length} aiTools, ${t.length} tools`);

      debugLog('Calling loadAllStatuses...');
      await loadAllStatuses(b, ai, t);
      debugLog('loadAllStatuses completed');

      setBenches(b);
      setAiTools(ai);
      setTools(t);
      setIsLoading(false);
      
      // Force a re-render after data loads
      debugLog('Requesting render after data load');
      renderer?.requestRender();

      debugLog('=== Initialization COMPLETE ===');
    } catch (error) {
      debugLog(`Initialization FAILED: ${error}`);
      console.error('Failed to initialize:', error);
      setIsLoading(false);
    }
  })();

  // Handle ALL keyboard events - the select's native handling isn't working reliably
  useKeyboard((event: KeyEvent) => {
    const key = event?.name?.toLowerCase() || '';
    const sequence = event?.sequence || '';
    debugLog(`🎹 Key: "${key}", sequence: "${sequence.replace(/\x1b/g, 'ESC')}", ctrl: ${event?.ctrl}, shift: ${event?.shift}`);

    // Quit
    if (key === 'q') {
      console.log('\nExiting without changes.');
      process.exit(0);
    }

    // Confirm
    if (key === 'return' || key === 'enter') {
      handleConfirm();
      return;
    }

    // Toggle selection with space
    if (key === 'space' || key === ' ') {
      const col = activeColumn();
      const indices = selectedIndices();
      handleItemSelected(col, indices[col]);
      renderer?.requestRender();
      return;
    }

    // Tab / Shift+Tab to switch columns
    if (key === 'tab') {
      batch(() => {
        if (event?.shift) {
          setActiveColumn(c => (c + 2) % 3); // Go backwards
        } else {
          setActiveColumn(c => (c + 1) % 3);
        }
      });
      renderer?.requestRender();
      event?.preventDefault?.();
      return;
    }

    // Left/Right arrows to switch columns
    if (key === 'left' || key === 'h') {
      batch(() => {
        setActiveColumn(c => (c + 2) % 3);
      });
      renderer?.requestRender();
      event?.preventDefault?.();
      return;
    }
    if (key === 'right' || key === 'l') {
      batch(() => {
        setActiveColumn(c => (c + 1) % 3);
      });
      renderer?.requestRender();
      event?.preventDefault?.();
      return;
    }

    // Up/Down navigation is handled by the focused select renderable.
  });

  // Convert components to select options using createMemo for reactivity
  const benchOptions = createMemo(() => benches().map(formatOption));
  const aiOptions = createMemo(() => aiTools().filter(t => !t.isSeparator).map(formatOption));
  const toolOptions = createMemo(() => tools().map(formatOption));

  return (
    <box flexDirection="column" height="100%" width="100%">
      <Header />

      {isLoading() ? (
        <text fg="#FFFF6B">Loading components...</text>
      ) : (
        <text fg="#888888">Use ↑↓/jk to navigate, Tab to switch columns, Space to toggle, Enter to confirm, Q to quit</text>
      )}

      {!isLoading() && (
        <box flexDirection="row" gap={2} marginTop={1}>
          {/* Column 1: Dev Benches */}
          <box flexDirection="column" width={28}>
            <text fg={activeColumn() === 0 ? '#FFFF6B' : '#888888'}>
              {activeColumn() === 0 ? '▶ DEV BENCHES ◀' : '─── DEV BENCHES ───'}
            </text>
            <select
              focused={activeColumn() === 0}
              options={benchOptions()}
              selectedIndex={selectedIndices()[0]}
              height={10}
              width={26}
              showDescription={false}
              textColor="#FFFFFF"
              focusedTextColor="#000000"
              focusedBackgroundColor="#FFFF6B"
              selectedTextColor="#69FF94"
              onChange={(index: number) => {
                handleSelectionChange(0, index);
                setSelectedIndices(prev => {
                  const newIndices = [...prev] as [number, number, number];
                  newIndices[0] = index;
                  return newIndices;
                });
              }}
              onSelect={(index: number) => handleItemSelected(0, index)}
            />
          </box>

          {/* Column 2: AI Assistants */}
          <box flexDirection="column" width={28}>
            <text fg={activeColumn() === 1 ? '#FFFF6B' : '#888888'}>
              {activeColumn() === 1 ? '▶ AI ASSISTANTS ◀' : '─── AI ASSISTANTS ───'}
            </text>
            <select
              focused={activeColumn() === 1}
              options={aiOptions()}
              selectedIndex={selectedIndices()[1]}
              height={10}
              width={26}
              showDescription={false}
              textColor="#FFFFFF"
              focusedTextColor="#000000"
              focusedBackgroundColor="#FFFF6B"
              selectedTextColor="#69FF94"
              onChange={(index: number) => {
                handleSelectionChange(1, index);
                setSelectedIndices(prev => {
                  const newIndices = [...prev] as [number, number, number];
                  newIndices[1] = index;
                  return newIndices;
                });
              }}
              onSelect={(index: number) => handleItemSelected(1, index)}
            />
          </box>

          {/* Column 3: Tools */}
          <box flexDirection="column" width={28}>
            <text fg={activeColumn() === 2 ? '#FFFF6B' : '#888888'}>
              {activeColumn() === 2 ? '▶ TOOLS ◀' : '─── TOOLS ───'}
            </text>
            <select
              focused={activeColumn() === 2}
              options={toolOptions()}
              selectedIndex={selectedIndices()[2]}
              height={10}
              width={26}
              showDescription={false}
              textColor="#FFFFFF"
              focusedTextColor="#000000"
              focusedBackgroundColor="#FFFF6B"
              selectedTextColor="#69FF94"
              onChange={(index: number) => {
                handleSelectionChange(2, index);
                setSelectedIndices(prev => {
                  const newIndices = [...prev] as [number, number, number];
                  newIndices[2] = index;
                  return newIndices;
                });
              }}
              onSelect={(index: number) => handleItemSelected(2, index)}
            />
          </box>
        </box>
      )}

      {!isLoading() && (
        <StatusBar
          benches={benches()}
          aiTools={aiTools()}
          tools={tools()}
        />
      )}
    </box>
  );
};

export default App;
