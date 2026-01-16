import type { Component } from 'solid-js';
import type { Component as ComponentType } from '../types';

interface StatusBarProps {
  benches: ComponentType[];
  aiTools: ComponentType[];
  tools: ComponentType[];
}

/**
 * StatusBar component - displays selected count and status
 */
export const StatusBar: Component<StatusBarProps> = (props) => {
  // Count selected items (excluding separators)
  const selectedCount = () => {
    let count = 0;

    for (const bench of props.benches) {
      if (bench.checked) count++;
    }

    for (const item of props.aiTools) {
      if (!item.isSeparator && item.checked) count++;
    }

    for (const item of props.tools) {
      if (item.checked) count++;
    }

    return count;
  };

  // Count pending changes
  const pendingChanges = () => {
    let installs = 0;
    let uninstalls = 0;

    const allItems = [...props.benches, ...props.aiTools, ...props.tools];

    for (const item of allItems) {
      if (item.isSeparator) continue;
      if (item.action === 'install') installs++;
      if (item.action === 'uninstall') uninstalls++;
    }

    return { installs, uninstalls };
  };

  return (
    <box flexDirection="column">
      {/* Empty line */}
      <text></text>

      {/* Status line */}
      <box flexDirection="row">
        <text fg="#FF6BFF">
          {`Changes selected: ${selectedCount()}`}
        </text>

        {pendingChanges().installs > 0 && (
          <text fg="#69FF94">
            {`  (+${pendingChanges().installs} install)`}
          </text>
        )}

        {pendingChanges().uninstalls > 0 && (
          <text fg="#FF6B6B">
            {`  (-${pendingChanges().uninstalls} uninstall)`}
          </text>
        )}
      </box>
    </box>
  );
};

export default StatusBar;
