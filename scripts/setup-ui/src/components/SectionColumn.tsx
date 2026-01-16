import { For, type Component } from 'solid-js';
import type { Component as ComponentType } from '../types';
import { SelectableItem } from './SelectableItem';

interface SectionColumnProps {
  title: string;
  items: ComponentType[];
  currentIndex: number | (() => number);
  isActive: boolean | (() => boolean);
  width?: number;
}

// Helper to resolve a value that might be a getter function
const resolve = <T,>(val: T | (() => T)): T =>
  typeof val === 'function' ? (val as () => T)() : val;

/**
 * SectionColumn component - renders a bordered column with selectable items
 *
 * Structure:
 * ┌─── TITLE ─────────────┐
 * │ [✓] ✓ Item1           │
 * │ [ ] ✗ Item2           │
 * └───────────────────────┘
 */
export const SectionColumn: Component<SectionColumnProps> = (props) => {
  const width = () => props.width || 24;

  // Create padded title centered in header
  const headerTitle = () => {
    const title = props.title;
    const availableWidth = width() - 4; // Account for corners ┌─ and ─┐
    const titleWithPadding = `─ ${title} `;
    const remainingDashes = availableWidth - titleWithPadding.length;
    return titleWithPadding + '─'.repeat(Math.max(0, remainingDashes));
  };

  // Create reactive getters that resolve the prop values
  const isActive = () => resolve(props.isActive);
  const currentIndex = () => resolve(props.currentIndex);

  const borderColor = () => isActive() ? '#FFFF6B' : '#888888';

  return (
    <box flexDirection="column" width={width()}>
      {/* Header border */}
      <text fg={borderColor()}>
        {`┌${headerTitle()}┐`}
      </text>

      {/* Items */}
      <For each={props.items}>
        {(item, index) => (
          <SelectableItem
            component={item}
            isSelected={() => index() === currentIndex()}
            isActive={isActive}
            width={width()}
          />
        )}
      </For>

      {/* Footer border */}
      <text fg={borderColor()}>
        {`└${'─'.repeat(width() - 2)}┘`}
      </text>
    </box>
  );
};

export default SectionColumn;
