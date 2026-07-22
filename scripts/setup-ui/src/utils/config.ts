import { resolve, dirname } from 'path';
import type { WorkbenchConfig, Component, AICliDefinition, ToolDefinition } from '../types';

/**
 * Get the root directory of the workBenches project
 */
export function getProjectRoot(): string {
  // Navigate up from scripts/setup-ui/src/utils to project root
  return resolve(dirname(import.meta.path), '../../../../');
}

/**
 * Load bench configuration from bench-config.json
 */
export async function loadBenchConfig(): Promise<WorkbenchConfig> {
  const configPath = resolve(getProjectRoot(), 'config/bench-config.json');

  try {
    const file = Bun.file(configPath);
    const exists = await file.exists();

    if (!exists) {
      console.warn(`Config file not found: ${configPath}`);
      return { benches: {} };
    }

    const content = await file.text();
    return JSON.parse(content) as WorkbenchConfig;
  } catch (error) {
    console.error('Failed to load bench config:', error);
    return { benches: {} };
  }
}

/**
 * Default AI CLI definitions
 */
export const AI_CLI_DEFINITIONS: AICliDefinition[] = [
  {
    id: 'claude_cli',
    name: 'Claude Code CLI',
    description: 'Anthropic Claude Code terminal assistant (native installer)',
    command: 'claude',
    installCmd: 'curl -fsSL https://claude.ai/install.sh | bash',
    uninstallCmd: 'rm -f ~/.local/bin/claude && rm -rf ~/.local/share/claude',
  },
  {
    id: 'copilot_cli',
    name: 'GitHub Copilot CLI',
    description: 'GitHub Copilot command line interface',
    command: 'copilot',
    installCmd: 'npm install -g @github/copilot',
    uninstallCmd: 'npm uninstall -g @github/copilot',
  },
  {
    id: 'codex_cli',
    name: 'Codex CLI',
    description: 'OpenAI Codex terminal assistant',
    command: 'codex',
    installCmd: 'npm install -g @openai/codex',
    uninstallCmd: 'npm uninstall -g @openai/codex',
  },
  {
    id: 'antigravity_cli',
    name: 'Antigravity CLI',
    description: 'Google Antigravity terminal assistant',
    command: 'agy',
    installCmd: 'curl -fsSL https://antigravity.google/cli/install.sh | bash',
    uninstallCmd: 'rm -f ~/.local/bin/agy',
  },
  {
    id: 'opencode_cli',
    name: 'OpenCode CLI',
    description: 'OpenCode terminal assistant',
    command: 'opencode',
    installCmd: 'npm install -g opencode-ai',
    uninstallCmd: 'npm uninstall -g opencode-ai',
  },
  {
    id: 'pi_cli',
    name: 'Pi Coding Agent',
    description: 'Minimal terminal coding harness with provider login support',
    command: 'pi',
    installCmd: 'npm install -g --ignore-scripts @earendil-works/pi-coding-agent',
    uninstallCmd: 'npm uninstall -g @earendil-works/pi-coding-agent',
  },
  // Separator marker
  {
    id: 'separator1',
    name: '',
    description: '',
    command: '',
    installCmd: '',
    uninstallCmd: '',
  },
  {
    id: 'spec_kit',
    name: 'spec-kit',
    description: 'GitHub spec-kit for specifications',
    command: 'specify',
    installCmd: 'uvx --from git+https://github.com/github/spec-kit.git specify',
    uninstallCmd: '', // Manual uninstall
  },
  {
    id: 'openspec',
    name: 'OpenSpec',
    description: 'Fission OpenSpec CLI',
    command: 'openspec',
    installCmd: 'npm install -g @fission-ai/openspec@latest',
    uninstallCmd: 'npm uninstall -g @fission-ai/openspec',
  },
];

/**
 * Default tool definitions
 */
export const TOOL_DEFINITIONS: ToolDefinition[] = [
  {
    id: 'vscode',
    name: 'Visual Studio Code',
    description: 'VS Code with Dev Containers extension',
    checkInstalled: async () => {
      // Will be implemented in statusChecks.ts
      return false;
    },
    installInstructions: 'Windows/WSL: winget install -e --id Microsoft.VisualStudioCode; Linux: install from https://code.visualstudio.com/',
  },
  {
    id: 'warp',
    name: 'Warp Terminal',
    description: 'Modern terminal with AI features',
    checkInstalled: async () => false,
    installInstructions: 'Windows/WSL: winget install -e --id Warp.Warp; otherwise install from https://www.warp.dev/',
  },
  {
    id: 'wave',
    name: 'Wave Terminal',
    description: 'Open source AI terminal',
    checkInstalled: async () => false,
    installInstructions: 'Windows/WSL: winget install -e --id CommandLine.Wave; otherwise install from https://www.waveterm.dev/',
  },
];

/**
 * Initialize components from config and defaults
 */
export async function initializeComponents(): Promise<{
  benches: Component[];
  aiTools: Component[];
  tools: Component[];
}> {
  const config = await loadBenchConfig();

  // Create bench components from config
  const benches: Component[] = Object.entries(config.benches).map(([name, benchConfig]) => ({
    id: `bench_${name}`,
    name,
    description: benchConfig.description || name,
    category: 'bench' as const,
    status: 'unknown' as const,
    checked: false,
    action: null,
  }));

  // If no benches found, use defaults
  if (benches.length === 0) {
    const defaultBenches = ['flutterBench', 'javaBench', 'dotNetBench', 'pyBench'];
    benches.push(...defaultBenches.map(name => ({
      id: `bench_${name}`,
      name,
      description: name,
      category: 'bench' as const,
      status: 'unknown' as const,
      checked: false,
      action: null,
    })));
  }

  // Create AI CLI components
  const aiTools: Component[] = AI_CLI_DEFINITIONS.map(def => ({
    id: def.id,
    name: def.name,
    description: def.description,
    category: 'ai' as const,
    status: 'unknown' as const,
    checked: false,
    action: null,
    isSeparator: def.id.startsWith('separator'),
  }));

  // Create tool components
  const tools: Component[] = TOOL_DEFINITIONS.map(def => ({
    id: def.id,
    name: def.name,
    description: def.description,
    category: 'tool' as const,
    status: 'unknown' as const,
    checked: false,
    action: null,
  }));

  return { benches, aiTools, tools };
}
