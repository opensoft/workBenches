#!/usr/bin/env python3
"""Workstation lifecycle contracts using fakes; no real host/engine changes."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WorkstationLifecycleTests(unittest.TestCase):
    def shell(self, body, interactive=False):
        with tempfile.TemporaryDirectory() as temporary:
            source = 'scripts/interactive-setup.sh' if interactive else 'scripts/lib/setup-prerequisites.sh'
            result = subprocess.run(['bash', '-c', f'source "{ROOT/source}"\n' + body], cwd=ROOT,
                text=True, capture_output=True, timeout=15, env=dict(os.environ, HOME=temporary,
                WSL_DISTRO_NAME='', WORKBENCHES_SETUP_LOG_FILE='/dev/null'))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout + result.stderr

    def test_all_entries_queue_and_review_without_actions(self):
        text = self.shell(r'''
is_wsl_windows() { return 0; }; init_components --loading; CURRENT_SECTION=3
activate_requirement() { echo UNEXPECTED; return 99; }
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
for current_selection in "${!requirement_items[@]}"; do
    key=${requirement_items[$current_selection]}; handle_input <<< D
    [[ "${component_action[$key]}" == uninstall && "${component_checked[$key]}" == true ]] || exit 30
    handle_input <<< D; [[ "${component_checked[$key]}" == false ]] || exit 31
    handle_input <<< ' '; [[ "${component_action[$key]}" == install ]] || exit 32
done
handle_input <<< ''; [[ "$CURRENT_SECTION" == 5 ]] || exit 33
setup_frame_lines=(); setup_frame_review; printf '%s\n' "${setup_frame_lines[@]}"
''', True)
        self.assertNotIn('UNEXPECTED', text)
        for name in ('WSL 2', 'Docker', 'Tools', 'Vault'): self.assertIn(name+' (Workstation)', text)

    def test_missing_prerequisites_save_without_python(self):
        text = self.shell(r'''
is_wsl_windows() { return 1; }; init_components --loading; status_checks_running=false
for key in docker setup_tools; do component_status[$key]=missing; done
setup_apply_allowed && exit 30
for key in docker setup_tools; do component_checked[$key]=true; component_action[$key]=install; done
setup_apply_allowed || exit 31
python3() { echo UNEXPECTED_PYTHON; return 99; }
selection_file="$HOME/selection.json"; save_selection || exit 32
workstation_plan_read "$selection_file" || exit 33
[[ "$workstation_plan_only" == true && "${workstation_plan_actions[docker]}" == install ]] || exit 34
printf '%s\n' "$(< "$selection_file")"
''', True)
        self.assertNotIn('UNEXPECTED', text)
        self.assertEqual({x['key'] for x in json.loads(text)['components']}, {'docker','setup_tools'})

    def test_private_plan_rejects_invalid_duplicate_and_symlink(self):
        self.shell(r'''
declare -A component_checked=([docker]=true) component_action=([docker]=uninstall)
workstation_save_selection "$HOME/plan" || exit 30
workstation_plan_read "$HOME/plan" || exit 31
chmod 644 "$HOME/plan"; workstation_plan_read "$HOME/plan" && exit 32
chmod 600 "$HOME/plan"; ln -s "$HOME/plan" "$HOME/link"
workstation_save_selection "$HOME/link" && exit 33
workstation_plan_read "$HOME/link" && exit 34
for body in \
 '{"schemaVersion":1,"components":[{"key":"unknown","action":"install"}]}' \
 '{"schemaVersion":1,"components":[{"key":"docker","action":"update"}]}' \
 '{"schemaVersion":1,"components":[{"key":"docker","action":"install"},{"key":"docker","action":"uninstall"}]}' \
 '{"schemaVersion":1,"components":[{"key":"docker","action":"install"},]}' \
 '{"schemaVersion":1,"components":[{"key":"docker","action":"install"}]} trailing'; do
    printf '%s' "$body" > "$HOME/plan"; workstation_plan_read "$HOME/plan" && exit 35
done
printf '\0' >> "$HOME/plan"; workstation_plan_read "$HOME/plan" && exit 36
:
''')

    def test_removal_preflight_and_dependency_order(self):
        output = self.shell(r'''
workstation_plan_actions=([docker]=uninstall [setup_tools]=uninstall [vault]=uninstall)
workstation_remove_preflight() { echo "preflight:$1"; }
workstation_remove_managed() { echo "remove:$1"; }
workstation_remove_docker() { echo remove:docker; }
workstation_plan_prepare || exit 30
echo components-done
workstation_plan_finish || exit 31
''')
        for a,b in zip(('preflight:docker','components-done','remove:vault','remove:setup_tools'),
                       ('components-done','remove:vault','remove:setup_tools','remove:docker')):
            self.assertLess(output.index(a), output.index(b))

    def test_foreign_container_and_unsupported_host_refuse_before_mutation(self):
        output = self.shell(r'''
workbenches_runtime_docker() {
    [[ "$1 $2" == 'container inspect' ]] && { echo 'tools|0|/foreign|true'; return; }
    echo UNEXPECTED; return 99
}
workstation_remove_managed setup_tools && exit 30
workstation_plan_actions=([wsl]=uninstall [setup_tools]=install)
workbenches_tools_activate() { echo UNEXPECTED; return 99; }
workstation_plan_prepare && exit 31
workbenches_is_wsl() { return 0; }; workstation_remove_preflight docker && exit 32
:
''')
        self.assertNotIn('UNEXPECTED', output)
        for text in ('preserved','No distribution was unregistered','Docker Desktop uninstall deletes container data'):
            self.assertIn(text, output)

    def test_linux_engine_removal_avoids_purge_and_autoremove(self):
        output = self.shell(r'''
workbenches_is_wsl() { return 1; }; workbenches_docker_os() { echo arch; }
workbenches_pin_docker() { WORKBENCHES_DOCKER_ENDPOINT=unix:///var/run/docker.sock; }
pacman() { [[ "$1" == -Q ]]; }; sudo() { printf 'HOST:%s\n' "$*"; }
workstation_remove_docker || exit 30
''')
        self.assertIn('HOST:systemctl stop docker.socket docker.service', output)
        self.assertIn('HOST:pacman -R -- docker docker-compose docker-buildx', output)
        for text in ('-Rns','--purge','autoremove','volume rm','image rm','/var/lib/docker'):
            self.assertNotIn(text, output)

    def test_owned_container_removal_uses_verified_id_without_volume_flags(self):
        output=self.shell(r'''
printf -v identity '%064d' 1
workbenches_runtime_docker() {
    if [[ "$1 $2" == 'container inspect' ]]; then printf 'tools|%s|%s|true|%s\n' "$(id -u)" "$HOME" "$identity"; return; fi
    printf '%s\n' "$*" >> "$HOME/commands"
}
workstation_remove_managed setup_tools || exit 30
cat "$HOME/commands"
''')
        identity='0'*63+'1'
        self.assertEqual(output.splitlines(),['container stop --time 10 '+identity,'container rm '+identity])

    def test_component_failure_does_not_run_removal(self):
        output = self.shell(r'''
ensure_setup_platform() { :; }; ensure_workstation_requirements() { :; }
load_statuses() { :; }; workbenches_release_checkout() { return 1; }
ensure_selected_dependencies() { :; }
load_selection() {
    component_checked[vscode]=true; component_action[vscode]=install
    component_checked[docker]=true; component_action[docker]=uninstall
}
workstation_plan_prepare() { echo prepared; }
process_selections() { echo component-failed; return 47; }
workstation_plan_finish() { echo UNEXPECTED_REMOVAL; }
main --apply-plan "$HOME/unused"; result=$?; [[ "$result" == 47 ]] || exit 30
''', True)
        self.assertIn('component-failed', output)
        self.assertNotIn('UNEXPECTED_REMOVAL', output)

    def test_service_only_launcher_skips_python_and_unrelated_setup(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo=Path(temporary); (repo/'scripts/lib').mkdir(parents=True); (repo/'bin').mkdir()
            shutil.copy2(ROOT/'setup.sh',repo/'setup.sh')
            shutil.copy2(ROOT/'scripts/lib/setup-workstation-lifecycle.sh',repo/'scripts/lib/setup-workstation-lifecycle.sh')
            (repo/'bootstrap.sh').write_text('workbenches_version() { echo 1.7.0-dev.1; }\n')
            (repo/'scripts/lib/setup-prerequisites.sh').write_text('''source "$(dirname "${BASH_SOURCE[0]}")/setup-workstation-lifecycle.sh"
ensure_setup_platform() { :; }
ensure_workstation_requirements() { :; }
workstation_remove_preflight() { echo "preflight:$1" >> "$HOME/actions"; }
workstation_remove_managed() { echo "remove:$1" >> "$HOME/actions"; }
''')
            ui=repo/'scripts/interactive-setup.sh'
            ui.write_text('''#!/bin/bash
[[ "$1" == --select-only ]] || exit 99
printf '%s' '{"schemaVersion":1,"components":[{"key":"setup_tools","action":"uninstall"}]}' > "$2"
'''); ui.chmod(0o755)
            python=repo/'bin/python3'; python.write_text('#!/bin/bash\necho UNEXPECTED_PYTHON\nexit 99\n'); python.chmod(0o755)
            result=subprocess.run(['bash',str(repo/'setup.sh')],cwd=repo,text=True,capture_output=True,timeout=10,
                env=dict(os.environ,HOME=temporary,PATH=str(repo/'bin')+':'+os.environ['PATH']))
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertNotIn('UNEXPECTED',result.stdout+result.stderr)
            self.assertIn('Selected workstation changes completed',result.stdout)
            self.assertEqual((repo/'actions').read_text().splitlines(),['preflight:setup_tools','remove:setup_tools'])

    def test_background_checks_do_not_install_missing_tools(self):
        output=self.shell(r'''
status_worker_dir="$HOME/status"; mkdir "$status_worker_dir"
workbenches_requirement_rows() { printf 'docker\tDocker\tup\tReady\nsetup_tools\tTools\tmissing\tMissing\nvault\tVault\tmissing\tOptional\n'; }
workbenches_tools_state() { echo missing; }
workbenches_tools_activate() { echo UNEXPECTED; return 99; }
workbenches_tools_use_shims() { echo UNEXPECTED; return 99; }
unset WORKBENCHES_TEST_NATIVE_TOOLS
status_worker_bootstrap "$status_worker_dir"
[[ -f "$status_worker_dir/done" ]] || exit 30
printf '%s\n' "$(< "$status_worker_dir/setup_tools.row")"
''',True)
        self.assertIn('missing',output)
        self.assertNotIn('UNEXPECTED',output)

    def test_readiness_refresh_preserves_service_selections(self):
        self.shell(r'''
init_components --loading
component_checked[vault]=true; component_action[vault]=uninstall
workbenches_setup_os() { echo Linux; }
workbenches_requirement_rows() { printf 'vault\tVault\tup\tOptional\n'; }
python3() { echo optional; }; check_component_status() { echo optional; }
load_requirements
[[ "${component_checked[vault]}" == true && "${component_action[vault]}" == uninstall ]] || exit 30
''',True)


if __name__ == '__main__': unittest.main()
