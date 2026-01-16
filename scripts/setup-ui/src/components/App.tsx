import { createSignal, onMount, createMemo, Show, type Component as SolidComponent } from 'solid-js';
import { useRenderer, useKeyboard } from '@opentui/solid';
import type { Component } from '../types';
import { initializeComponents } from '../utils/config';
import { loadAllStatuses } from '../utils/statusChecks';
import { Header } from './Header';
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
  debugLog('Setting up onMount callback...');

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

  // Handle keyboard for column switching and quit using proper hook
  useKeyboard((event) => {
    const key = event?.name?.toLowerCase() || '';
    debugLog(`Key pressed: ${key}`);

    if (key === 'q') {
      console.log('\nExiting without changes.');
      process.exit(0);
    }

    if (key === 'return' || key === 'enter') {
      handleConfirm();
    }

    // Tab or right arrow to switch columns
    if (key === 'tab' || key === 'right' || key === 'l') {
      setActiveColumn(c => {
        const newCol = (c + 1) % 3;
        debugLog(`Switched to column ${newCol}`);
        return newCol;
      });
    }

    // Shift+tab or left arrow to switch columns back
    if (key === 'left' || key === 'h') {
      setActiveColumn(c => {
        const newCol = (c + 2) % 3;
        debugLog(`Switched to column ${newCol}`);
        return newCol;
      });
    }
  });

  // Convert components to select options using createMemo for reactivity
  const benchOptions = createMemo(() => benches().map(formatOption));
  const aiOptions = createMemo(() => aiTools().filter(t => !t.isSeparator).map(formatOption));
  const toolOptions = createMemo(() => tools().map(formatOption));

  return (
    <box flexDirection="column" height="100%" width="100%">
      <Header />

      <Show
        when={!isLoading()}
        fallback={
          <text fg="#FFFF6B">Loading components...</text>
        }
      >
        <text fg="#888888">Use ↑↓/jk to navigate, Tab/←→ to switch columns, Space to toggle, Enter to confirm, Q to quit</text>

        <box flexDirection="row" gap={2} marginTop={1}>
          {/* Column 1: Dev Benches */}
          <box flexDirection="column" width={28}>
            <text fg={activeColumn() === 0 ? '#FFFF6B' : '#888888'}>
              {activeColumn() === 0 ? '▶ DEV BENCHES ◀' : '─── DEV BENCHES ───'}
            </text>
            <select
              key={`benches-${benches().length}`}
              focused={activeColumn() === 0}
              options={benchOptions()}
              height={10}
              width={26}
              showDescription={false}
              textColor="#FFFFFF"
              focusedTextColor="#000000"
              focusedBackgroundColor="#FFFF6B"
              selectedTextColor="#69FF94"
              onChange={(index) => handleSelectionChange(0, index)}
              onSelect={(index) => handleItemSelected(0, index)}
            />
          </box>

          {/* Column 2: AI Assistants */}
          <box flexDirection="column" width={28}>
            <text fg={activeColumn() === 1 ? '#FFFF6B' : '#888888'}>
              {activeColumn() === 1 ? '▶ AI ASSISTANTS ◀' : '─── AI ASSISTANTS ───'}
            </text>
            <select
              key={`aitools-${aiTools().length}`}
              focused={activeColumn() === 1}
              options={aiOptions()}
              height={10}
              width={26}
              showDescription={false}
              textColor="#FFFFFF"
              focusedTextColor="#000000"
              focusedBackgroundColor="#FFFF6B"
              selectedTextColor="#69FF94"
              onChange={(index) => handleSelectionChange(1, index)}
              onSelect={(index) => handleItemSelected(1, index)}
            />
          </box>

          {/* Column 3: Tools */}
          <box flexDirection="column" width={28}>
            <text fg={activeColumn() === 2 ? '#FFFF6B' : '#888888'}>
              {activeColumn() === 2 ? '▶ TOOLS ◀' : '─── TOOLS ───'}
            </text>
            <select
              key={`tools-${tools().length}`}
              focused={activeColumn() === 2}
              options={toolOptions()}
              height={10}
              width={26}
              showDescription={false}
              textColor="#FFFFFF"
              focusedTextColor="#000000"
              focusedBackgroundColor="#FFFF6B"
              selectedTextColor="#69FF94"
              onChange={(index) => handleSelectionChange(2, index)}
              onSelect={(index) => handleItemSelected(2, index)}
            />
          </box>
        </box>

        <StatusBar
          benches={benches()}
          aiTools={aiTools()}
          tools={tools()}
        />
      </Show>
    </box>
  );
};

export default App;
