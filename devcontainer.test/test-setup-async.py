#!/usr/bin/env python3
"""First paint and cancellation must not wait on Docker or setup tools."""
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AsyncSetupTests(unittest.TestCase):
    def test_tui_paints_before_a_slow_docker_probe_and_q_cleans_it_up(self):
        with tempfile.TemporaryDirectory(prefix='workbenches-startup-test-') as temporary:
            home = Path(temporary); binary = home / 'bin'; binary.mkdir()
            for name in ('bash', 'sh', 'uname', 'id', 'dirname', 'basename', 'date', 'mkdir',
                         'mktemp', 'whoami', 'hostname', 'ls', 'tail', 'xargs', 'rm', 'ps',
                         'cat', 'tput', 'sleep', 'grep', 'mv'):
                (binary / name).symlink_to(shutil.which(name))
            docker = binary / 'docker'
            docker.write_text('#!/bin/bash\nprintf "%s" "$$" > "$HOME/docker-pid"\nsleep 8\necho linux\n')
            docker.chmod(0o755)
            for name in ('python3', 'jq', 'git', 'curl'):
                tool = binary / name
                tool.write_text('#!/bin/bash\necho invoked >> "$HOME/forbidden-tool-calls"\nexit 99\n')
                tool.chmod(0o755)
            env = {key: value for key, value in os.environ.items() if not key.startswith('WORKBENCHES_')}
            env.update(HOME=temporary, PATH=str(binary), TERM='xterm', USER='fixture', WSL_DISTRO_NAME='')
            master, slave = pty.openpty()
            started = time.monotonic()
            process = subprocess.Popen(['/bin/bash', str(ROOT / 'setup.sh')], cwd=ROOT, env=env,
                                       stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
            os.close(slave)
            output = b''; probe = None
            try:
                deadline = started + 2
                while b'Navigation:' not in output and time.monotonic() < deadline:
                    readable, _, _ = select.select([master], [], [], .05)
                    if readable:
                        try: output += os.read(master, 65536)
                        except OSError: break
                self.assertIn(b'Navigation:', output, output.decode(errors='replace'))
                self.assertIn(b'Loading', output)
                self.assertIn(b'\x1b[5m', output)
                self.assertFalse((home / 'forbidden-tool-calls').exists())
                # Ensure the deliberately blocked probe really started.
                deadline = time.monotonic() + 1
                while not (home / 'docker-pid').exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue((home / 'docker-pid').exists())
                probe = int((home / 'docker-pid').read_text())
                quit_at = time.monotonic(); os.write(master, b'Q')
                process.wait(timeout=2)
                self.assertEqual(process.returncode, 130)
                self.assertLess(time.monotonic() - quit_at, 2)
                # The loader's probe must not keep running after the TUI closes.
                stat = Path(f'/proc/{probe}/stat')
                if stat.exists():
                    self.assertEqual(stat.read_text().split()[2], 'Z', 'Docker probe survived cancellation')
                self.assertFalse((home / 'forbidden-tool-calls').exists())
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM); process.wait(timeout=5)
                os.close(master)

    def test_loaded_catalog_preserves_selection_and_focus_and_rejects_unknown_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / 'snapshot'; directory.mkdir()
            (directory / 'catalog').write_text('flutterBench\npyBench\n')
            (directory / 'bench_pyBench.row').write_text('installed\t\n')
            (directory / 'unknown.row').write_text('installed\t\n')
            (directory / 'done').touch()
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components --loading
bench_items=(pyBench); CURRENT_SECTION=0; current_selection=0
component_description[bench_pyBench]=pyBench
component_checked[bench_pyBench]=true; component_action[bench_pyBench]=uninstall
component_status[wsl]=up; component_status[docker]=up; component_status[setup_tools]=up
status_loader_dir="$1"; status_checks_running=true
sleep 5 & status_loader_pid=$!
poll_status_loader
[[ "$status_checks_running" == false ]] || exit 20
[[ "${{bench_items[$current_selection]}}" == pyBench ]] || exit 21
[[ "${{component_checked[bench_pyBench]}}" == true && "${{component_action[bench_pyBench]}}" == uninstall ]] || exit 22
[[ "${{component_status[bench_pyBench]}}" == installed ]] || exit 23
[[ -z "${{component_status[unknown]:-}}" ]] || exit 24
'''
            result = subprocess.run(['bash', '-c', command, 'snapshot', str(directory)], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(directory.exists())

    def test_rendering_never_runs_discovery(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components --loading
initialize_loading_statuses
status_checks_running=true
setup_os_label=Linux
check_component_status() {{ echo unexpected-probe >&2; return 99; }}
workbenches_docker_state() {{ echo unexpected-docker >&2; return 99; }}
tput() {{ if [[ "$1" == cols ]]; then echo 80; fi; }}
draw_ui
'''
        result = subprocess.run(['bash', '-c', command], capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        self.assertIn('Loading', result.stdout)
        self.assertNotIn('[V Connect]', result.stdout)

    def test_status_updates_do_not_clear_screen_or_redraw_header(self):
        with tempfile.TemporaryDirectory() as temporary:
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components --loading
initialize_loading_statuses
status_checks_running=true
setup_os_label=Linux
tput() {{ if [[ "$1" == cols ]]; then echo 88; fi; }}
draw_ui > "$1/first"
draw_ui > "$1/unchanged"
component_status[docker]=up
draw_ui > "$1/update"
draw_ui > "$1/repeated"
'''
            result = subprocess.run(['bash', '-c', command, 'render', temporary], capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = {name: (Path(temporary) / name).read_bytes()
                     for name in ('first', 'unchanged', 'update', 'repeated')}
            self.assertEqual(files['first'].count(b'\x1b[2J'), 1)
            self.assertIn(b'workBenches v1.5.0', files['first'])
            self.assertEqual(files['unchanged'], b'')
            self.assertEqual(files['repeated'], b'')
            self.assertIn(b'Docker Up', files['update'])
            self.assertNotIn(b'\x1b[2J', files['update'])
            self.assertNotIn(b'workBenches v1.5.0', files['update'])
            self.assertNotIn('█▀▀█'.encode(), files['update'])
            self.assertLess(len(files['update']), len(files['first']) // 2)

    def test_shorter_frames_erase_stale_lines_and_external_output_invalidates_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
tput() {{ if [[ "$1" == cols ]]; then echo 88; fi; }}
render_setup_frame() {{ printf '%s\\n' "$content"; }}
content=$'header\\nlong status\\nold footer'
draw_ui > "$1/first"
content=$'header\\nup'
draw_ui > "$1/shorter"
setup_ui_painted=false
draw_ui > "$1/return"
'''
            result = subprocess.run(['bash', '-c', command, 'render', temporary], capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            shorter = (Path(temporary) / 'shorter').read_bytes()
            self.assertEqual(shorter, b'\x1b[2;1H\x1b[0mup\x1b[0m\x1b[K'
                                     b'\x1b[3;1H\x1b[0m\x1b[0m\x1b[K')
            self.assertIn(b'\x1b[2J', (Path(temporary) / 'return').read_bytes())

    def test_identical_status_snapshot_does_not_request_redraw(self):
        with tempfile.TemporaryDirectory() as temporary:
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components --loading
component_status[docker]=up
status_loader_dir="$1"; status_checks_running=true; status_loader_pid=$$
printf 'up\\t\\n' > "$1/docker.row"
poll_status_loader
[[ "$status_ui_dirty" == false ]]
'''
            result = subprocess.run(['bash', '-c', command, 'snapshot', temporary], capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
