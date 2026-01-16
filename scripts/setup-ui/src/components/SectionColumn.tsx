import { For, type Component } from 'solid-js';
import type { Component as ComponentType } from '../types';
import { SelectableItem } from './SelectableItem';

interface SectionColumnProps {
  title: string;
  items: ComponentType[];
  currentIndex: number;
  isActive: boolean;
  width?: number;
}

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

  const borderColor = () => props.isActive ? '#FFFF6B' : '#888888';

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
            isSelected={index() === props.currentIndex}
            isActive={props.isActive}
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
