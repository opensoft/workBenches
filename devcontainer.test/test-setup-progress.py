#!/usr/bin/env python3
"""Exercise the install panel in a real PTY, without Docker or host changes."""
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'scripts/lib/setup-progress.sh'


class SetupProgressTests(unittest.TestCase):
    def run_terminal(self, body, *, rows=18, columns=80, answer=b'', interrupt=None, resize=None):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', rows, columns, 0, 0))
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(('WORKBENCHES_PROGRESS_', 'WORKBENCHES_SETUP_PROGRESS'))}
        env['TERM'] = 'xterm'
        driver = f'''source "{HELPER}"
trap 'setup_progress_finish "$?"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
{body}
'''
        process = subprocess.Popen(['bash', '-c', driver], env=env, stdin=slave,
                                   stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)
        output = b''
        try:
            if answer:
                os.write(master, answer)
            deadline = time.monotonic() + 5
            acted = False
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], .05)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                if b'READY_FOR_SIGNAL' in output and not acted:
                    acted = True
                    if resize:
                        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', *resize, 0, 0))
                        os.kill(process.pid, signal.SIGWINCH)
                        os.write(master, b'\n')
                    elif interrupt:
                        os.kill(process.pid, interrupt)
            process.wait(timeout=1)
            return process.returncode, output
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            os.close(master)

    def test_progress_reserves_header_and_preserves_prompt_input(self):
        status, output = self.run_terminal('''setup_progress_start 3
setup_progress_stage 'Installing tools'
setup_progress_component 'Codex: install' 1 0
for ((i=0; i<30; i++)); do echo "build log $i"; done
read -r -p 'Fixture prompt: ' answer
echo "Received: $answer"
''', answer=b'fixture-answer\n')
        self.assertEqual(status, 0, output)
        self.assertIn(b'\033[6;18r', output)
        self.assertIn(b'Stage: Installing tools', output)
        self.assertIn(b'Current: Codex: install', output)
        self.assertIn(b'Completed: 1/3  Failed: 0', output)
        self.assertIn(b'build log 29', output)
        self.assertIn(b'Received: fixture-answer', output)
        self.assertIn(b'Status: Finished', output)
        self.assertTrue(output.endswith(b'\033[r\0338\033[0m\033[?25h\r\n'))

    def test_child_updates_parent_panel_without_clearing_logs_or_restoring_margins(self):
        status, output = self.run_terminal(f'''setup_progress_start 2
echo PARENT_LOG
bash -c 'source "$1"; setup_progress_start 2; setup_progress_component "Second tool" 1 0;
setup_progress_finish 0; echo CHILD_LOG' child "{HELPER}"
echo PARENT_RESUMED
''')
        self.assertEqual(status, 0, output)
        self.assertEqual(output.count(b'\033[2J'), 1)
        self.assertEqual(output.count(b'\033[r'), 1)
        self.assertIn(b'Current: Second tool', output)
        self.assertLess(output.index(b'PARENT_RESUMED'), output.index(b'\033[r'))

    def test_failure_and_cancellation_restore_normal_terminal_scrolling(self):
        for interrupt, expected, label in ((signal.SIGINT, 130, b'Cancelled'),
                                           (signal.SIGTERM, 143, b'Cancelled'),
                                           (None, 7, b'Needs attention')):
            with self.subTest(interrupt=interrupt):
                body = 'setup_progress_start 2\n'
                body += 'echo READY_FOR_SIGNAL\nread -r answer\n' if interrupt else 'exit 7\n'
                status, output = self.run_terminal(body, interrupt=interrupt)
                self.assertEqual(status, expected, output)
                self.assertIn(b'Status: ' + label, output)
                self.assertTrue(output.endswith(b'\033[r\0338\033[0m\033[?25h\r\n'))

    def test_resize_reconfigures_scroll_area(self):
        status, output = self.run_terminal('''setup_progress_start 2
echo READY_FOR_SIGNAL
read -r answer || true
setup_progress_component 'Resized tool' 1 1
''', resize=(14, 45))
        self.assertEqual(status, 0, output)
        self.assertIn(b'\033[6;14r', output)
        self.assertIn(b'Current: Resized tool', output)
        self.assertIn(b'Completed: 1/2  Failed: 1', output)

    def test_small_terminal_and_redirected_output_remain_plain(self):
        body = '''setup_progress_start 2
setup_progress_stage 'Installing tools'
setup_progress_component 'Codex' 1 0
echo ordinary-output
'''
        status, output = self.run_terminal(body, rows=8, columns=30)
        self.assertEqual(status, 0, output)
        self.assertEqual(output, b'ordinary-output\r\n')
        result = subprocess.run(['bash', '-c', f'source "{HELPER}"\n{body}\nsetup_progress_finish 0'],
                                capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'ordinary-output\n')

    def test_component_labels_cannot_clear_the_panel_or_wrap_into_logs(self):
        status, output = self.run_terminal('''setup_progress_start 2
setup_progress_component $'tool\\033[2J\\nwith an extremely long label that must be clipped before it wraps' 0 0
''', columns=40)
        self.assertEqual(status, 0, output)
        self.assertEqual(output.count(b'\033[2J'), 1)
        self.assertNotIn(b'before it wraps', output)


if __name__ == '__main__':
    unittest.main()
