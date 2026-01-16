/**
 * Component status - matches the Bash script's status values
 */
export type ComponentStatus = 'installed' | 'not_installed' | 'needs_creds' | 'unknown';

/**
 * Action to take on a component
 */
export type ComponentAction = 'install' | 'uninstall' | null;

/**
 * Component category for grouping in the UI
 */
export type ComponentCategory = 'bench' | 'ai' | 'tool';

/**
 * Represents a selectable component in the setup UI
 */
export interface Component {
  /** Unique identifier (e.g., 'bench_flutterBench', 'claude_cli', 'vscode') */
  id: string;
  /** Display name shown in the UI */
  name: string;
  /** Longer description for tooltips/details */
  description: string;
  /** Category for column placement */
  category: ComponentCategory;
  /** Current installation status */
  status: ComponentStatus;
  /** Whether the item is checked/selected */
  checked: boolean;
  /** Action to perform (determined by toggle logic) */
  action: ComponentAction;
  /** Whether this is a separator (for AI section) */
  isSeparator?: boolean;
}

/**
 * Bench configuration from bench-config.json
 */
export interface BenchConfig {
  path: string;
  url?: string;
  description?: string;
}

/**
 * Full configuration file structure
 */
export interface WorkbenchConfig {
  benches: Record<string, BenchConfig>;
}

/**
 * Navigation state for the UI
 */
export interface NavigationState {
  /** Current section: 0=Benches, 1=AI, 2=Tools */
  currentSection: number;
  /** Current selection index within the section */
  currentIndex: number;
}

/**
 * AI CLI definitions with install commands
 */
export interface AICliDefinition {
  id: string;
  name: string;
  description: string;
  command: string; // Command to check if installed
  installCmd: string; // npm install command
  uninstallCmd: string; // npm uninstall command
  credentialCheck?: () => Promise<boolean>; // Check if credentials are configured
}

/**
 * Tool definitions
 */
export interface ToolDefinition {
  id: string;
  name: string;
  description: string;
  checkInstalled: () => Promise<boolean>;
  installInstructions: string;
}

/**
 * Installation result
 */
export interface InstallResult {
  success: boolean;
  message: string;
  needsCredentials?: boolean;
}

/**
 * Colors used in the UI (matches Bash script)
 */
export const COLORS = {
  red: '#FF6B6B',
  green: '#69FF94',
  yellow: '#FFFF6B',
  blue: '#6BB5FF',
  cyan: '#6BFFFF',
  magenta: '#FF6BFF',
  white: '#FFFFFF',
  dim: '#888888',
} as const;

/**
 * Unicode symbols used in the UI
 */
export const SYMBOLS = {
  checkmark: '✓',
  cross: '✗',
  warning: '⚠',
  arrow: '▶',
  unchecked: '[ ]',
  checked: '[✓]',
  uninstall: '[X]',
} as const;
