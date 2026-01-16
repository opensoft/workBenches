import { resolve } from 'path';
import type { Component, InstallResult } from '../types';
import { getProjectRoot, AI_CLI_DEFINITIONS, TOOL_DEFINITIONS } from './config';

/**
 * Run a shell command and return result
 */
async function runCommand(
  cmd: string[],
  options: { cwd?: string; sudo?: boolean } = {}
): Promise<{ success: boolean; output: string }> {
  try {
    const args = options.sudo ? ['sudo', ...cmd] : cmd;
    const proc = Bun.spawn(args, {
      cwd: options.cwd,
      stdout: 'pipe',
      stderr: 'pipe',
    });

    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();
    const exitCode = await proc.exited;

    return {
      success: exitCode === 0,
      output: stdout + stderr,
    };
  } catch (error) {
    return {
      success: false,
      output: String(error),
    };
  }
}

/**
 * Show a spinner while running an async operation
 */
async function withSpinner<T>(
  message: string,
  operation: () => Promise<T>
): Promise<T> {
  const spinnerChars = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏';
  let i = 0;
  let running = true;

  // Start spinner
  const interval = setInterval(() => {
    process.stdout.write(`\r  ${spinnerChars[i % spinnerChars.length]} ${message}`);
    i++;
  }, 100);

  try {
    const result = await operation();
    running = false;
    clearInterval(interval);
    process.stdout.write('\r' + ' '.repeat(message.length + 10) + '\r');
    return result;
  } catch (error) {
    running = false;
    clearInterval(interval);
    process.stdout.write('\r' + ' '.repeat(message.length + 10) + '\r');
    throw error;
  }
}

/**
 * Install a bench from git
 */
async function installBench(benchName: string): Promise<InstallResult> {
  const projectRoot = getProjectRoot();

  // Try to get URL from config
  const configPath = resolve(projectRoot, 'config/bench-config.json');
  let benchUrl = '';
  let benchPath = '';

  try {
    const config = await Bun.file(configPath).json();
    const benchConfig = config.benches?.[benchName];
    if (benchConfig) {
      benchUrl = benchConfig.url || '';
      benchPath = benchConfig.path || benchName;
    }
  } catch {
    benchPath = benchName;
  }

  if (!benchUrl) {
    return {
      success: false,
      message: `No URL configured for ${benchName}`,
    };
  }

  const fullPath = resolve(projectRoot, benchPath);

  // Clone the repo
  console.log(`  Cloning ${benchName}...`);
  const cloneResult = await withSpinner(
    `Cloning ${benchName}`,
    () => runCommand(['git', 'clone', benchUrl, fullPath])
  );

  if (!cloneResult.success) {
    return {
      success: false,
      message: `Failed to clone: ${cloneResult.output}`,
    };
  }

  // Run setup.sh if it exists
  const setupScript = resolve(fullPath, 'setup.sh');
  const hasSetup = await Bun.file(setupScript).exists();

  if (hasSetup) {
    console.log(`  Running setup for ${benchName}...`);
    const setupResult = await withSpinner(
      `Setting up ${benchName}`,
      () => runCommand(['bash', setupScript], { cwd: fullPath })
    );

    if (!setupResult.success) {
      console.warn(`  Warning: Setup script had issues: ${setupResult.output}`);
    }
  }

  return {
    success: true,
    message: `Installed ${benchName}`,
  };
}

/**
 * Uninstall a bench
 */
async function uninstallBench(benchName: string): Promise<InstallResult> {
  const projectRoot = getProjectRoot();

  // Find the bench directory
  const possiblePaths = [
    resolve(projectRoot, benchName),
    resolve(projectRoot, `devBenches/${benchName}`),
    resolve(projectRoot, `adminBenches/${benchName}`),
  ];

  for (const path of possiblePaths) {
    const exists = await Bun.file(path).exists().catch(() => false);
    // Check if directory exists using test -d
    const proc = Bun.spawn(['test', '-d', path], { stdout: 'pipe', stderr: 'pipe' });
    if ((await proc.exited) === 0) {
      console.log(`  Removing ${benchName}...`);
      const result = await runCommand(['rm', '-rf', path]);
      return {
        success: result.success,
        message: result.success ? `Uninstalled ${benchName}` : `Failed: ${result.output}`,
      };
    }
  }

  return {
    success: false,
    message: `Could not find ${benchName} to uninstall`,
  };
}

/**
 * Install an AI CLI tool
 */
async function installAiCli(id: string): Promise<InstallResult> {
  const def = AI_CLI_DEFINITIONS.find(d => d.id === id);
  if (!def || !def.installCmd) {
    return { success: false, message: `Unknown AI CLI: ${id}` };
  }

  console.log(`  Installing ${def.name}...`);

  // Parse install command
  const parts = def.installCmd.split(' ');
  const cmd = parts[0];
  const args = parts.slice(1);

  // Check if sudo is needed (npm global installs)
  const needsSudo = cmd === 'npm' && args.includes('-g');

  const result = await withSpinner(
    `Installing ${def.name}`,
    () => runCommand([cmd, ...args], { sudo: needsSudo })
  );

  if (result.success) {
    return {
      success: true,
      message: `Installed ${def.name}`,
      needsCredentials: ['claude_cli', 'codex_cli', 'copilot_cli', 'gemini_cli'].includes(id),
    };
  }

  return {
    success: false,
    message: `Failed to install ${def.name}: ${result.output}`,
  };
}

/**
 * Uninstall an AI CLI tool
 */
async function uninstallAiCli(id: string): Promise<InstallResult> {
  const def = AI_CLI_DEFINITIONS.find(d => d.id === id);
  if (!def || !def.uninstallCmd) {
    return { success: false, message: `Cannot uninstall ${id}` };
  }

  console.log(`  Uninstalling ${def.name}...`);

  const parts = def.uninstallCmd.split(' ');
  const cmd = parts[0];
  const args = parts.slice(1);
  const needsSudo = cmd === 'npm' && args.includes('-g');

  const result = await withSpinner(
    `Uninstalling ${def.name}`,
    () => runCommand([cmd, ...args], { sudo: needsSudo })
  );

  return {
    success: result.success,
    message: result.success ? `Uninstalled ${def.name}` : `Failed: ${result.output}`,
  };
}

/**
 * Handle tool installation (usually just display instructions)
 */
async function installTool(id: string): Promise<InstallResult> {
  const def = TOOL_DEFINITIONS.find(d => d.id === id);
  if (!def) {
    return { success: false, message: `Unknown tool: ${id}` };
  }

  console.log(`\n  ${def.name} Installation:`);
  console.log(`  ${def.installInstructions}`);

  return {
    success: true,
    message: `See instructions above for ${def.name}`,
  };
}

/**
 * Process all selected items
 */
export async function processSelections(
  benches: Component[],
  aiTools: Component[],
  tools: Component[]
): Promise<void> {
  console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
  console.log('║               Applying Configuration Changes                                 ║');
  console.log('╚══════════════════════════════════════════════════════════════════════════════╝\n');

  let successCount = 0;
  let failCount = 0;
  const needsCreds: string[] = [];

  // Process benches
  for (const bench of benches) {
    if (!bench.action) continue;

    const benchName = bench.id.replace('bench_', '');

    if (bench.action === 'install') {
      const result = await installBench(benchName);
      if (result.success) {
        console.log(`  ✓ ${result.message}`);
        successCount++;
      } else {
        console.log(`  ✗ ${result.message}`);
        failCount++;
      }
    } else if (bench.action === 'uninstall') {
      const result = await uninstallBench(benchName);
      if (result.success) {
        console.log(`  ✓ ${result.message}`);
        successCount++;
      } else {
        console.log(`  ✗ ${result.message}`);
        failCount++;
      }
    }
  }

  // Process AI tools
  for (const item of aiTools) {
    if (item.isSeparator || !item.action) continue;

    if (item.action === 'install') {
      const result = await installAiCli(item.id);
      if (result.success) {
        console.log(`  ✓ ${result.message}`);
        successCount++;
        if (result.needsCredentials) {
          needsCreds.push(item.id);
        }
      } else {
        console.log(`  ✗ ${result.message}`);
        failCount++;
      }
    } else if (item.action === 'uninstall') {
      const result = await uninstallAiCli(item.id);
      if (result.success) {
        console.log(`  ✓ ${result.message}`);
        successCount++;
      } else {
        console.log(`  ✗ ${result.message}`);
        failCount++;
      }
    }
  }

  // Process tools
  for (const item of tools) {
    if (!item.action) continue;

    if (item.action === 'install') {
      const result = await installTool(item.id);
      if (result.success) {
        successCount++;
      }
    }
  }

  // Summary
  console.log('\n────────────────────────────────────────────────────────────────────────────────');
  console.log(`  Summary: ${successCount} succeeded, ${failCount} failed`);

  // Credential setup prompts
  if (needsCreds.length > 0) {
    console.log('\n  Some tools need credential setup:');
    for (const id of needsCreds) {
      switch (id) {
        case 'claude_cli':
          console.log('    - Claude CLI: Run `claude login` or set ANTHROPIC_API_KEY');
          break;
        case 'codex_cli':
          console.log('    - Codex CLI: Run `codex login` or set OPENAI_API_KEY');
          break;
        case 'copilot_cli':
          console.log('    - Copilot CLI: Run `copilot auth login`');
          break;
        case 'gemini_cli':
          console.log('    - Gemini CLI: Run `gemini` and follow Google login prompts');
          break;
      }
    }
  }

  console.log('');
}
