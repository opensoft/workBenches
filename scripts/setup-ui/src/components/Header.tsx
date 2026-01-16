import type { Component } from 'solid-js';

/**
 * Header component - renders the ASCII banner and navigation instructions
 */
export const Header: Component = () => {
  return (
    <box flexDirection="column">
      {/* ASCII Art Banner - Opensoft */}
      <text fg="#6BFFFF">
        {'   ___                            __ _   '}
      </text>
      <text fg="#6BFFFF">
        {'  / _ \\ _ __    ___  _ __   ___ / _| |_ '}
      </text>
      <text fg="#6BFFFF">
        {' | | | | \'_ \\  / _ \\| \'_ \\ / __| |_| __|'}
      </text>
      <text fg="#6BFFFF">
        {' | |_| | |_) ||  __/| | | |\\__ \\  _| |_ '}
      </text>
      <text fg="#6BFFFF">
        {'  \\___/| .__/  \\___||_| |_||___/_|  \\__|'}
      </text>
      <text fg="#6BFFFF">
        {'       |_|                               '}
      </text>

      {/* Empty line */}
      <text></text>

      {/* Header Box */}
      <text fg="#6BB5FF">
        {'╔══════════════════════════════════════════════════════════════════════════════╗'}
      </text>
      <text fg="#6BB5FF">
        {'║               WorkBenches Configuration Manager                              ║'}
      </text>
      <text fg="#6BB5FF">
        {'╚══════════════════════════════════════════════════════════════════════════════╝'}
      </text>

      {/* Empty line */}
      <text></text>

      {/* Navigation Instructions */}
      <box flexDirection="row">
        <text fg="#6BFFFF">{'Navigation:'}</text>
        <text fg="#FFFFFF">{' ↑/↓/j/k or I Move  '}</text>
        <text fg="#6BFFFF">{'←/→/h/l or U/O:'}</text>
        <text fg="#FFFFFF">{' Switch  '}</text>
        <text fg="#6BFFFF">{'Space:'}</text>
        <text fg="#FFFFFF">{' Toggle  '}</text>
        <text fg="#6BFFFF">{'Enter:'}</text>
        <text fg="#FFFFFF">{' Apply  '}</text>
        <text fg="#6BFFFF">{'Q:'}</text>
        <text fg="#FFFFFF">{' Quit'}</text>
      </box>

      {/* Empty line */}
      <text></text>
    </box>
  );
};

export default Header;
