#!/usr/bin/env python3
"""Readiness checks and the requirements-first setup flow, with no host changes."""
import importlib.util
import json
import os
from pathlib import Path
import pty
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('requirements', ROOT / 'scripts/setup-requirements.py')
requirements = importlib.util.module_from_spec(spec)
spec.loader.exec_module(requirements)


class RequirementsTests(unittest.TestCase):
    def test_linux_docker_is_required_even_when_all_accounts_are_absent(self):
        with patch.object(requirements, 'operating_system', return_value=('Linux', False, False, 'linux')), patch.object(requirements.shutil, 'which', return_value='/fake'), patch.object(requirements, 'run', return_value=(0, 'linux')):
            data = requirements.snapshot()
        self.assertTrue(all(row['ready'] for row in data['requirements']))
        self.assertEqual([row['key'] for row in data['requirements']], ['setup_tools', 'docker'])

    def test_missing_docker_and_windows_container_daemon_are_not_ready(self):
        for installed, response in ((False, (0, 'linux')), (True, (1, '')), (True, (0, 'windows'))):
            with self.subTest(installed=installed, response=response), patch.object(requirements, 'operating_system', return_value=('Linux', False, False, 'linux')), patch.object(requirements.shutil, 'which', side_effect=lambda name: '/fake' if installed or name != 'docker' else None), patch.object(requirements, 'run', return_value=response):
                self.assertFalse(requirements.snapshot()['requirements'][-1]['ready'])

    def test_wsl1_fails_and_running_wsl2_passes(self):
        for release, expected in (('4.4.0-Microsoft', False), ('6.6.87-microsoft-standard-WSL2', True)):
            with self.subTest(release=release), patch.object(requirements, 'operating_system', return_value=('Windows / WSL', True, False, release)), patch.object(requirements.shutil, 'which', side_effect=lambda name: None if name == 'wsl.exe' else '/fake'), patch.object(requirements, 'run', return_value=(0, 'linux')):
                self.assertEqual(requirements.snapshot()['requirements'][0]['ready'], expected)

    def test_native_windows_requires_wsl_even_when_docker_is_ready(self):
        with patch.object(requirements, 'operating_system', return_value=('Windows', False, True, 'windows')), patch.object(requirements.shutil, 'which', return_value='/fake'), patch.object(requirements, 'run', return_value=(0, 'linux')):
            self.assertFalse(requirements.snapshot()['requirements'][0]['ready'])

    def test_docker_probe_times_out_without_hanging(self):
        with patch.object(requirements.subprocess, 'run', side_effect=subprocess.TimeoutExpired('docker', 8)):
            self.assertEqual(requirements.run(['docker', 'info']), (1, ''))

    def test_utf16_windows_output_without_bom_is_decoded(self):
        result = subprocess.CompletedProcess([], 0, 'Ubuntu Running 2'.encode('utf-16-le'))
        with patch.object(requirements.subprocess, 'run', return_value=result):
            self.assertEqual(requirements.run(['wsl.exe', '--list', '--verbose']), (0, 'Ubuntu Running 2'))

    def test_os_title_does_not_probe_docker(self):
        with patch.object(requirements, 'snapshot', side_effect=AssertionError('unexpected Docker probe')), patch.object(sys, 'argv', ['requirements', 'os']):
            self.assertEqual(requirements.main(), 0)

    def test_native_windows_setup_guides_to_wsl_before_linux_installers(self):
        command = f'''source "{ROOT}/scripts/lib/setup-prerequisites.sh"
uname() {{ echo MINGW64_NT; }}
ensure_setup_platform
'''
        result = subprocess.run(['bash', '-c', command], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn('workBenches Setup — Windows', result.stdout)
        self.assertIn('wsl --install -d Ubuntu', result.stdout)
        self.assertIn('run ./setup.sh there', result.stdout)

    def test_missing_wsl_docker_offers_desktop_and_preserves_windows_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            powershell = directory / 'powershell.exe'
            powershell.write_text('#!/bin/bash\nprintf "%s" "$*" > "$HOME/command"\nexit 7\n'); powershell.chmod(0o755)
            command = f'source "{ROOT}/scripts/lib/docker-prerequisite.sh"; workbenches_is_wsl() {{ return 0; }}; workbenches_install_docker'
            env = dict(os.environ, HOME=temporary, PATH=temporary + ':' + os.environ['PATH'])
            result = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 7)
            self.assertIn('Docker.DockerDesktop', (directory / 'command').read_text())
            self.assertIn('exit $LASTEXITCODE', (directory / 'command').read_text())
            self.assertIn('WSL Integration', result.stdout)

    def test_setup_stops_before_selection_and_accounts_when_docker_is_missing(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary); repo = home / 'repo'; repo.mkdir()
            shutil.copytree(ROOT / 'scripts', repo / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
            for name in ('setup.sh', 'bootstrap.sh'):
                shutil.copy(ROOT / name, repo / name)
            (repo / 'scripts/interactive-setup.sh').write_text('#!/bin/bash\ntouch "$HOME/selection-ran"\n')
            (repo / 'scripts/interactive-setup.sh').chmod(0o755)
            binary = home / 'bin'; binary.mkdir()
            (binary / 'docker').write_text('#!/bin/bash\nexit 1\n'); (binary / 'docker').chmod(0o755)
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'), PATH=str(binary) + ':' + os.environ['PATH'])
            result = subprocess.run(['bash', str(repo / 'setup.sh')], env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('Requirements', result.stdout)
            self.assertIn('Docker (required)', result.stdout)
            self.assertFalse((home / 'selection-ran').exists())
            self.assertFalse((home / '.config/workbenches/account-session.json').exists())

    def test_requirements_quit_and_configuration_are_ordered_before_menu(self):
        for answer, expected in ((b'Q\n', 130), (b'\n', 0)):
            with self.subTest(answer=answer), tempfile.TemporaryDirectory() as temporary:
                home = Path(temporary); binary = home / 'bin'; binary.mkdir()
                docker = binary / 'docker'
                docker.write_text('#!/bin/bash\nif [[ -f "$HOME/ready" ]]; then echo linux; exit 0; fi\nexit 1\n'); docker.chmod(0o755)
                driver = f'''source "{ROOT}/scripts/lib/setup-prerequisites.sh"
ensure_docker() {{ echo configure >> "$HOME/actions"; touch "$HOME/ready"; }}
ensure_workstation_requirements || exit "$?"
echo menu >> "$HOME/actions"
'''
                master, slave = pty.openpty()
                env = dict(os.environ, HOME=str(home), PATH=str(binary) + ':' + os.environ['PATH'])
                try:
                    process = subprocess.Popen(['bash', '-c', driver], env=env, stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    os.close(slave); os.write(master, answer)
                    out, err = process.communicate(timeout=15)
                    self.assertEqual(process.returncode, expected, (out + err).decode())
                    actions = (home / 'actions').read_text().splitlines() if (home / 'actions').exists() else []
                    self.assertEqual(actions, ['configure', 'menu'] if expected == 0 else [])
                finally:
                    if process.poll() is None: process.kill(); process.wait()
                    os.close(master)

    def test_requirements_navigation_preserves_selections_and_blocks_required_removal(self):
        with tempfile.TemporaryDirectory() as temporary:
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
component_checked[codex_cli]=true; component_action[codex_cli]=install
handle_input
[[ "$CURRENT_SECTION" == 3 ]] || exit 20
handle_input
[[ "${{component_checked[docker]}}" != true ]] || exit 21
[[ "${{component_checked[codex_cli]}}" == true ]] || exit 22
CURRENT_SECTION=3; current_selection=2
component_status[workbenches_account]='not configured'
handle_input
[[ "${{component_action[workbenches_account]}}" == install ]] || exit 23
'''
            env = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary, WSL_DISTRO_NAME='')
            result = subprocess.run(['bash', '-c', command], input='PD ', env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
