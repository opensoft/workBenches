/**
 * WorkBenches Setup UI - Entry Point
 *
 * Interactive terminal UI for configuring workbenches using OpenTUI with SolidJS
 */

import { render } from '@opentui/solid';
import { App } from './src/components/App';
import { processSelections } from './src/utils/installers';

/**
 * Main entry point
 */
async function main() {
  // Check for TTY
  if (!process.stdin.isTTY) {
    console.error('This program requires an interactive terminal.');
    process.exit(1);
  }

  // Handle uncaught errors
  process.on('uncaughtException', (error) => {
    console.error('Uncaught error:', error);
    process.exit(1);
  });

  try {
    // Render the app using OpenTUI's render function
    // The render function handles terminal setup, input, and rendering
    await render(() => <App />);

  } catch (error) {
    console.error('Failed to initialize UI:', error);

    // Fallback: Run the original Bash script
    console.log('\nFalling back to Bash UI...');
    const proc = Bun.spawn(['bash', '../interactive-setup.sh'], {
      cwd: import.meta.dir,
      stdin: 'inherit',
      stdout: 'inherit',
      stderr: 'inherit',
    });
    await proc.exited;
    process.exit(0);
  }
}

// Run main
main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
