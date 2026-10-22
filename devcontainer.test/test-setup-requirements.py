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
    def test_inventory_preserves_runtime_states_and_optional_vault(self):
        listing = ('docker\tDocker\tup\tLinux engine\n'
                   'setup_tools\tTools\tup\tContainer tools\n'
                   'vault\tVault\tmissing\tOptional helper\n')
        with patch.object(requirements.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, listing)):
            data = requirements.snapshot()
        self.assertEqual([row['state'] for row in data['requirements']], ['up', 'up', 'missing'])
        self.assertTrue(all(row['ready'] for row in data['requirements'] if row['required']))
        self.assertFalse(data['requirements'][-1]['required'])

    def test_check_ignores_optional_vault_but_requires_tools_up(self):
        for state, expected in (('up', 0), ('down', 1), ('missing', 1)):
            with self.subTest(state=state), patch.object(requirements, 'snapshot', return_value={
                'requirements': [{'ready': state == 'up', 'required': True},
                                 {'ready': False, 'required': False}]}), patch.object(sys, 'argv', ['requirements', 'check']):
                self.assertEqual(requirements.main(), expected)

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
workbenches_tools_activate() {{ :; }}
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

    def test_requirements_navigation_preserves_other_selections_and_queues_removal(self):
        with tempfile.TemporaryDirectory() as temporary:
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
is_wsl_windows() {{ return 1; }}
init_components
component_status[docker]=up
component_checked[codex_cli]=true; component_action[codex_cli]=install
handle_input
[[ "$CURRENT_SECTION" == 3 ]] || exit 20
handle_input
[[ "${{component_checked[docker]}}" == true && "${{component_action[docker]}}" == uninstall ]] || exit 21
[[ "${{component_checked[codex_cli]}}" == true ]] || exit 22
CURRENT_SECTION=4; current_selection=1
activate_profile() {{ [[ "${{profile_items[$current_selection]}}" == workbenches_account ]] || exit 23; }}
handle_input
[[ "${{component_checked[codex_cli]}}" == true ]] || exit 24
'''
            env = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary, WSL_DISTRO_NAME='')
            result = subprocess.run(['bash', '-c', command], input='PD ', env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_service_buttons_follow_runtime_and_identity_state(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
for state in missing down up; do
    for key in docker setup_tools vault; do
        printf '%s:%s:%s\\n' "$key" "$state" "$(workbenches_requirement_action "$key" "$state" 'sign in')"
    done
done
printf 'authenticated:%s\\n' "$(workbenches_requirement_action vault up 'signed in')"
'''
        result = subprocess.run(['bash', '-c', command], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            'docker:missing:Install', 'setup_tools:missing:Install', 'vault:missing:Install',
            'docker:down:Start', 'setup_tools:down:Start', 'vault:down:Start',
            'docker:up:Check', 'setup_tools:up:Check', 'vault:up:Connect', 'authenticated:Sign out'])

    def test_explicit_vault_shortcut_installs_connects_and_signs_out_without_component_apply(self):
        with tempfile.TemporaryDirectory() as temporary:
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
CURRENT_SECTION=3
for current_selection in "${{!requirement_items[@]}}"; do
    [[ "${{requirement_items[$current_selection]}}" != vault ]] || break
done
component_status[vault]=missing
component_status[workbenches_account]='sign in'
component_checked[codex_cli]=true; component_action[codex_cli]=install
refresh_component_statuses() {{ :; }}
draw_ui() {{ :; }}
ensure_workstation_requirements() {{ echo prerequisites >> "$HOME/actions"; }}
workbenches_vault_start() {{ echo vault-start >> "$HOME/actions"; component_status[vault]=up; }}
python3() {{
    [[ "$1" == */setup-workbenches-account.py ]] || return 90
    echo "account ${{2:-login}}" >> "$HOME/actions"
    if [[ "${{2:-}}" == --logout ]]; then component_status[workbenches_account]='sign in'
    else component_status[workbenches_account]='signed in'; fi
}}
handle_input || exit 20
handle_input || exit 21
handle_input || exit 22
[[ "${{component_checked[codex_cli]}}" == true && "${{component_action[codex_cli]}}" == install ]] || exit 23
'''
            result = subprocess.run(['bash', '-c', command], input='VVV', env=dict(os.environ, HOME=temporary, WSL_DISTRO_NAME=''), capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((Path(temporary) / 'actions').read_text().splitlines(), ['prerequisites', 'vault-start', 'account login', 'account --logout'])

    def test_connection_cancel_returns_to_menu_and_preserves_selections(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
CURRENT_SECTION=3
for current_selection in "${{!requirement_items[@]}}"; do
    [[ "${{requirement_items[$current_selection]}}" != vault ]] || break
done
component_status[vault]=up; component_status[workbenches_account]='sign in'
component_checked[codex_cli]=true; component_action[codex_cli]=install
refresh_component_statuses() {{ :; }}
draw_ui() {{ :; }}
python3() {{ return 130; }}
handle_input || exit 20
[[ "$requirements_notice" == 'Connection cancelled.' ]] || exit 21
[[ "${{component_checked[codex_cli]}}" == true ]] || exit 22
handle_input
[[ "$?" == 2 ]] || exit 23
'''
        result = subprocess.run(['bash', '-c', command], input='VQ', capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_install_and_start_resolve_dependencies_without_connecting_or_applying(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
refresh_component_statuses() {{ :; }}
draw_ui() {{ :; }}
ensure_docker() {{ :; }}
ensure_workstation_requirements() {{ echo prerequisites; }}
workbenches_vault_start() {{ echo vault-start; }}
python3() {{ echo unexpected-login; return 99; }}
for state in missing down; do
    for key in docker setup_tools vault; do
        component_status[$key]=$state
        activate_requirement "$key" || exit 20
    done
done
'''
        result = subprocess.run(['bash', '-c', command], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('prerequisites'), 6)
        self.assertEqual(result.stdout.count('vault-start'), 2)
        self.assertNotIn('unexpected-login', result.stdout)

    def test_duplicate_strip_is_blank_and_vault_status_is_in_containers(self):
        import re
        for columns in (36, 60, 80, 100):
            for state, identity, action in (('missing', 'sign in', 'Install'),
                                             ('down', 'sign in', 'Start'),
                                             ('up', 'sign in', 'Connect'),
                                             ('up', 'signed in', 'Sign out')):
                with self.subTest(columns=columns, state=state, identity=identity):
                    command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
setup_ui_width={columns}; CURRENT_SECTION=3
component_description[docker]=Docker; component_status[docker]=up
component_description[setup_tools]=Tools; component_status[setup_tools]=up
component_description[vault]=Vault; component_status[vault]={state}
component_status[workbenches_account]='{identity}'
draw_requirements_summary
draw_requirements
draw_setup_footer
'''
                    result = subprocess.run(['bash', '-c', command], capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    plain = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', result.stdout)
                    self.assertIn('Vault', plain)
                    self.assertIn({'missing':'Not installed','down':'Installed · Down','up':'Installed · Up'}[state], plain)
                    self.assertEqual(plain.splitlines()[1], '')
                    self.assertNotIn('[Check]', plain)
                    self.assertIn('[ ]', plain)
                    self.assertTrue(all(len(line) <= columns for line in plain.splitlines()), plain)

    def test_vault_shortcut_activates_main_screen_button_and_preserves_focus(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
CURRENT_SECTION=1; current_selection=2
component_status[vault]=up; component_status[workbenches_account]='sign in'
component_checked[codex_cli]=true; component_action[codex_cli]=install
refresh_component_statuses() {{ :; }}
draw_ui() {{ :; }}
python3() {{
    [[ "$1" == */setup-workbenches-account.py ]] || return 90
    if [[ "${{2:-}}" == --logout ]]; then component_status[workbenches_account]='sign in'
    else component_status[workbenches_account]='signed in'; fi
}}
handle_input || exit 20
[[ "${{component_status[workbenches_account]}}" == 'signed in' ]] || exit 21
handle_input || exit 22
[[ "${{component_status[workbenches_account]}}" == 'sign in' ]] || exit 23
[[ "$CURRENT_SECTION" == 1 && "$current_selection" == 2 ]] || exit 24
[[ "${{component_checked[codex_cli]}}" == true ]] || exit 25
'''
        result = subprocess.run(['bash', '-c', command], input='Vv', capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_required_rows_render_install_and_start_buttons(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
setup_ui_width=80; current_selection=0
component_description[docker]=Docker; component_status[docker]=missing
component_description[setup_tools]=Tools; component_status[setup_tools]=down
requirement_detail[docker]='Install Docker first.'
draw_requirement_item docker required
draw_requirement_item setup_tools required
'''
        result = subprocess.run(['bash', '-c', command], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Missing  [Install]', result.stdout)
        self.assertIn('Down  [Start]', result.stdout)

    def test_requirements_shortcut_returns_to_the_previous_component(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
CURRENT_SECTION=1; current_selection=2
component_checked[codex_cli]=true; component_action[codex_cli]=install
handle_input
[[ "$CURRENT_SECTION" == 3 && "$current_selection" == 0 ]] || exit 20
handle_input
[[ "$CURRENT_SECTION" == 1 && "$current_selection" == 2 ]] || exit 21
[[ "${{component_checked[codex_cli]}}" == true ]] || exit 22
'''
        result = subprocess.run(['bash', '-c', command], input='PP', capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


def load_tests(loader, tests, pattern):
    lifecycle_spec = importlib.util.spec_from_file_location('workstation_lifecycle', ROOT / 'devcontainer.test/test-workstation-lifecycle.py')
    module = importlib.util.module_from_spec(lifecycle_spec)
    lifecycle_spec.loader.exec_module(module)
    tests.addTests(loader.loadTestsFromModule(module))
    return tests


if __name__ == '__main__':
    unittest.main()
