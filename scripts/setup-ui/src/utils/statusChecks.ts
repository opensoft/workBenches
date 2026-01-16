import { resolve } from 'path';
import type { ComponentStatus, Component } from '../types';
import { getProjectRoot, AI_CLI_DEFINITIONS } from './config';

/**
 * Check if running in WSL environment
 */
export function isWSL(): boolean {
  return !!process.env.WSL_DISTRO_NAME ||
         (process.platform === 'linux' &&
          Bun.file('/proc/version').exists() !== false);
}

/**
 * Check if a command exists in PATH
 */
async function commandExists(command: string): Promise<boolean> {
  try {
    const proc = Bun.spawn(['which', command], {
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const exitCode = await proc.exited;
    return exitCode === 0;
  } catch {
    return false;
  }
}

/**
 * Check if a file exists
 */
async function fileExists(path: string): Promise<boolean> {
  try {
    return await Bun.file(path).exists();
  } catch {
    return false;
  }
}

/**
 * Check if a directory exists
 */
async function dirExists(path: string): Promise<boolean> {
  try {
    const proc = Bun.spawn(['test', '-d', path], {
      stdout: 'pipe',
      stderr: 'pipe',
    });
    return (await proc.exited) === 0;
  } catch {
    return false;
  }
}

/**
 * Get git remote URL for a directory
 */
async function getGitRemote(dir: string): Promise<string | null> {
  try {
    const proc = Bun.spawn(['git', 'remote', 'get-url', 'origin'], {
      cwd: dir,
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const output = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;
    return exitCode === 0 ? output.trim() : null;
  } catch {
    return null;
  }
}

/**
 * Check Claude CLI status
 */
async function checkClaudeCli(): Promise<ComponentStatus> {
  const hasCommand = await commandExists('claude');
  if (!hasCommand) return 'not_installed';

  // Check for credentials
  const hasApiKey = !!process.env.ANTHROPIC_API_KEY;
  const hasConfig = await fileExists(`${process.env.HOME}/.claude/config.json`);

  if (hasApiKey || hasConfig) {
    return 'installed';
  }
  return 'needs_creds';
}

/**
 * Check Codex CLI status
 */
async function checkCodexCli(): Promise<ComponentStatus> {
  const hasCommand = await commandExists('codex');
  if (!hasCommand) return 'not_installed';

  // Check for credentials
  const hasApiKey = !!process.env.OPENAI_API_KEY;
  const hasAuth = await fileExists(`${process.env.HOME}/.codex/auth.json`);

  if (hasApiKey || hasAuth) {
    return 'installed';
  }
  return 'needs_creds';
}

/**
 * Check VS Code status (WSL-aware)
 */
async function checkVSCode(): Promise<ComponentStatus> {
  if (isWSL()) {
    // Check for Windows VS Code
    const hasCode = await commandExists('code');
    const hasWindowsCode = await fileExists('/mnt/c/Program Files/Microsoft VS Code/Code.exe');

    if (!hasCode && !hasWindowsCode) {
      return 'not_installed';
    }

    // Check for vscode-server (WSL extension)
    const hasVscodeServer = await dirExists(`${process.env.HOME}/.vscode-server`);
    if (!hasVscodeServer) {
      return 'needs_creds'; // Using needs_creds to indicate missing WSL extension
    }

    return 'installed';
  } else {
    // Native Linux
    const hasCode = await commandExists('code');
    return hasCode ? 'installed' : 'not_installed';
  }
}

/**
 * Check Warp Terminal status (WSL-aware)
 */
async function checkWarp(): Promise<ComponentStatus> {
  if (isWSL()) {
    // Check common Windows Warp locations
    const locations = [
      '/mnt/c/Program Files/Warp/Warp.exe',
    ];

    for (const loc of locations) {
      if (await fileExists(loc)) {
        return 'installed';
      }
    }

    // Check user's AppData
    const proc = Bun.spawn(['find', '/mnt/c/Users', '-maxdepth', '4', '-name', 'Warp.exe', '-type', 'f'], {
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const output = await new Response(proc.stdout).text();
    if (output.trim()) {
      return 'installed';
    }

    return 'not_installed';
  } else {
    // Native Linux
    const hasWarp = await commandExists('warp-terminal');
    const hasWarpDir = await dirExists(`${process.env.HOME}/.warp`);
    return (hasWarp || hasWarpDir) ? 'installed' : 'not_installed';
  }
}

/**
 * Check Wave Terminal status (WSL-aware)
 */
async function checkWave(): Promise<ComponentStatus> {
  if (isWSL()) {
    // Check common Windows Wave locations
    const hasWindowsWave = await fileExists('/mnt/c/Program Files/Wave/Wave.exe');
    if (hasWindowsWave) {
      return 'installed';
    }

    // Check user's AppData for waveterm
    const proc = Bun.spawn(['find', '/mnt/c/Users', '-maxdepth', '5', '-path', '*waveterm*Wave.exe', '-type', 'f'], {
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const output = await new Response(proc.stdout).text();
    if (output.trim()) {
      return 'installed';
    }

    return 'not_installed';
  } else {
    // Native Linux
    const hasWave = await commandExists('wave');
    const hasWaveDir = await dirExists(`${process.env.HOME}/.waveterm`);
    return (hasWave || hasWaveDir) ? 'installed' : 'not_installed';
  }
}

/**
 * Check bench installation status
 */
async function checkBench(benchName: string, expectedUrl?: string): Promise<ComponentStatus> {
  const projectRoot = getProjectRoot();

  // Try common locations
  const possiblePaths = [
    resolve(projectRoot, benchName),
    resolve(projectRoot, `devBenches/${benchName}`),
    resolve(projectRoot, `adminBenches/${benchName}`),
  ];

  for (const benchPath of possiblePaths) {
    if (await dirExists(benchPath)) {
      // Check if it's a git repo
      const gitDir = resolve(benchPath, '.git');
      if (await dirExists(gitDir)) {
        // Verify git remote if URL is provided
        if (expectedUrl) {
          const remote = await getGitRemote(benchPath);
          if (remote !== expectedUrl) {
            return 'not_installed'; // Wrong remote
          }
        }

        // Check if setup commands exist
        const benchNameLower = benchName.toLowerCase().replace('bench', '');
        const expectedCommand = `new-${benchNameLower}-project`;
        const hasCommand = await commandExists(expectedCommand);

        if (hasCommand) {
          return 'installed';
        }
        return 'needs_creds'; // Installed but not set up
      }
    }
  }

  return 'not_installed';
}

/**
 * Check status for a component by ID
 */
export async function checkComponentStatus(component: Component): Promise<ComponentStatus> {
  const { id } = component;

  // Handle separators
  if (component.isSeparator) {
    return 'unknown';
  }

  // Bench components
  if (id.startsWith('bench_')) {
    const benchName = id.replace('bench_', '');
    return checkBench(benchName);
  }

  // AI CLI components
  switch (id) {
    case 'claude_cli':
      return checkClaudeCli();
    case 'codex_cli':
      return checkCodexCli();
    case 'copilot_cli':
    case 'gemini_cli':
    case 'opencode_cli':
    case 'spec_kit':
    case 'openspec': {
      const def = AI_CLI_DEFINITIONS.find(d => d.id === id);
      if (def && def.command) {
        const exists = await commandExists(def.command);
        return exists ? 'installed' : 'not_installed';
      }
      return 'unknown';
    }
    default:
      break;
  }

  // Tool components
  switch (id) {
    case 'vscode':
      return checkVSCode();
    case 'warp':
      return checkWarp();
    case 'wave':
      return checkWave();
    default:
      return 'unknown';
  }
}

/**
 * Load statuses for all components
 */
export async function loadAllStatuses(
  benches: Component[],
  aiTools: Component[],
  tools: Component[]
): Promise<void> {
  // Check all in parallel for speed
  const allComponents = [...benches, ...aiTools, ...tools];

  await Promise.all(
    allComponents.map(async (component) => {
      component.status = await checkComponentStatus(component);

      // Auto-check if installed
      if (component.status === 'installed' || component.status === 'needs_creds') {
        component.checked = true;
      }
    })
  );
}
