import type { Component } from 'solid-js';
import type { Component as ComponentType, COLORS, SYMBOLS } from '../types';

interface SelectableItemProps {
  component: ComponentType;
  isSelected: boolean | (() => boolean);
  isActive: boolean | (() => boolean);
  width?: number;
}

// Helper to resolve a value that might be a getter function
const resolve = <T,>(val: T | (() => T)): T =>
  typeof val === 'function' ? (val as () => T)() : val;

/**
 * Get checkbox display based on checked state and action
 */
function getCheckbox(component: ComponentType): string {
  if (!component.checked) {
    return '[ ]';
  }
  if (component.action === 'uninstall') {
    return '[X]'; // Red X for uninstall
  }
  return '[✓]'; // Green checkmark for install/keep
}

/**
 * Get status symbol based on component status
 */
function getStatusSymbol(status: ComponentType['status']): string {
  switch (status) {
    case 'installed':
      return '✓';
    case 'needs_creds':
      return '⚠';
    case 'not_installed':
    default:
      return '✗';
  }
}

/**
 * Get status color based on component status
 */
function getStatusColor(status: ComponentType['status']): string {
  switch (status) {
    case 'installed':
      return '#69FF94'; // Green
    case 'needs_creds':
      return '#FFFF6B'; // Yellow
    case 'not_installed':
    default:
      return '#FF6B6B'; // Red
  }
}

/**
 * Get checkbox color based on action
 */
function getCheckboxColor(component: ComponentType): string {
  if (!component.checked) {
    return '#FFFFFF';
  }
  if (component.action === 'uninstall') {
    return '#FF6B6B'; // Red for uninstall
  }
  return '#69FF94'; // Green for install/keep
}

/**
 * SelectableItem component - renders a single selectable item with checkbox and status
 *
 * Format: "▶ [✓] ✓ ComponentName" (24 chars total)
 * - Selection indicator: "▶ " or "  " (2 chars)
 * - Checkbox: [✓], [ ], or [X] (3 chars)
 * - Space (1 char)
 * - Status: ✓, ✗, or ⚠ (1 char)
 * - Space (1 char)
 * - Name: truncated to 16 chars
 */
export const SelectableItem: Component<SelectableItemProps> = (props) => {
  const checkbox = () => getCheckbox(props.component);
  const statusSymbol = () => getStatusSymbol(props.component.status);
  const statusColor = () => getStatusColor(props.component.status);
  const checkboxColor = () => getCheckboxColor(props.component);

  // Create reactive getters for props that might be functions
  const isSelected = () => resolve(props.isSelected);
  const isActive = () => resolve(props.isActive);

  // Handle separator
  if (props.component.isSeparator) {
    return (
      <text
        width={props.width || 24}
        fg="#888888"
      >
        {'────────────────────────'}
      </text>
    );
  }

  // Build the display string
  const prefix = () => isSelected() && isActive() ? '▶ ' : '  ';
  const name = () => props.component.name.slice(0, 16).padEnd(16);

  return (
    <box flexDirection="row" width={props.width || 24}>
      {/* Selection indicator */}
      <text fg={isSelected() && isActive() ? '#6BFFFF' : '#FFFFFF'}>
        {prefix()}
      </text>

      {/* Checkbox */}
      <text fg={checkboxColor()}>
        {checkbox()}
      </text>

      {/* Space */}
      <text fg="#FFFFFF">{' '}</text>

      {/* Status symbol */}
      <text fg={statusColor()}>
        {statusSymbol()}
      </text>

      {/* Space */}
      <text fg="#FFFFFF">{' '}</text>

      {/* Component name */}
      <text fg={isActive() ? '#FFFFFF' : '#888888'}>
        {name()}
      </text>
    </box>
  );
};

export default SelectableItem;
