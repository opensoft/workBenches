#!/usr/bin/env python3
"""Exercise Docker prerequisite prompts and setup ordering with mocked commands."""

from __future__ import annotations

import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DockerPrerequisiteTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.actions = self.directory / "actions"
        self.driver = self.directory / "driver.sh"
        self.driver.write_text('''#!/usr/bin/env bash
if [[ "${TEST_TUI:-0}" == 1 ]]; then source "$TEST_UI"; else source "$TEST_HELPER"; fi
trap 'exit 130' INT
trap 'exit 143' TERM
workbenches_docker_os() { printf '%s\\n' "$TEST_OS"; }
# These package-manager cases model native Linux even on a WSL test host.
workbenches_is_wsl() { [[ "$TEST_WSL" == 1 ]]; }
# Model host membership explicitly; never inspect or change the test runner's groups.
getent() {
    [[ "$*" == 'group docker' && "$TEST_DOCKER_GROUP_EXISTS" == 1 ]] || return 2
    echo 'docker:x:999:'
}
id() {
    case "$1" in
        -nG) echo "$TEST_GROUPS" ;;
        -un) echo fixture-user ;;
        *) return 1 ;;
    esac
}
usermod() { echo 'Unexpected direct usermod invocation' >&2; return 99; }
loginctl() {
    printf 'loginctl %s\\n' "$*" >> "$TEST_LOG"
    echo 'Forced session termination is forbidden' >&2
    return 99
}
omarchy() {
    printf 'omarchy %s\\n' "$*" >> "$TEST_LOG"
    return "$TEST_LOGOUT_EXIT"
}
uwsm() {
    printf 'uwsm %s\\n' "$*" >> "$TEST_LOG"
    if [[ "$1" == check ]]; then return "$TEST_UWSM_ACTIVE"; fi
    return "$TEST_LOGOUT_EXIT"
}
command() {
    if [[ "${1:-}" == -v && "${2:-}" == docker ]]; then
        [[ "$TEST_INSTALLED" == 1 || -f "$TEST_STATE/installed" ]]
    elif [[ "${1:-}" == -v && "${2:-}" == omarchy ]]; then
        [[ "$TEST_OMARCHY" == 1 ]]
    elif [[ "${1:-}" == -v && "${2:-}" == uwsm ]]; then
        [[ "$TEST_UWSM" == 1 ]]
    else
        builtin command "$@"
    fi
}
docker() {
    printf 'docker %s\\n' "$*" >> "$TEST_LOG"
    if [[ "$1" == info ]]; then
        [[ "$TEST_ACCESS" == 1 || -f "$TEST_STATE/accessible" ]]
    else
        printf '%s\\n' "$TEST_ENDPOINT"
    fi
}
systemctl() {
    printf 'systemctl %s\\n' "$*" >> "$TEST_LOG"
    case "$1" in
        show) echo loaded ;;
        is-active) [[ "$TEST_SERVICE_ACTIVE" == 1 ]] ;;
    esac
}
sudo() {
    printf 'sudo %s\\n' "$*" >> "$TEST_LOG"
    if [[ "$TEST_SUDO_EXIT" != 0 ]]; then return "$TEST_SUDO_EXIT"; fi
    if [[ "$1" == systemctl ]]; then
        [[ "$TEST_START_ACCESS" != 1 ]] || touch "$TEST_STATE/accessible"
    elif [[ "$1" == usermod ]]; then
        # Account membership changes do not refresh this shell's supplementary groups.
        touch "$TEST_STATE/group-added"
    else
        [[ "$TEST_INSTALL_CLI" != 1 ]] || touch "$TEST_STATE/installed"
    fi
}
if [[ "${TEST_TUI:-0}" == 1 ]]; then
    init_components
    component_status[docker]=down
    stop_status_loader() { :; }
    refresh_component_statuses() { echo STATUS_REFRESH; }
    draw_ui() { echo MENU_REDRAW; }
    activate_requirement docker
else
    if ensure_docker "${TEST_SELECTED_ACTION:-}"; then exit 0; else exit $?; fi
fi
''')
        self.env = {
            **os.environ,
            "TEST_HELPER": str(ROOT / "scripts/lib/docker-prerequisite.sh"),
            "TEST_UI": str(ROOT / "scripts/interactive-setup.sh"),
            "TEST_LOG": str(self.actions), "TEST_STATE": str(self.directory),
            "TEST_OS": "arch", "TEST_INSTALLED": "1", "TEST_ACCESS": "1",
            "TEST_ENDPOINT": "unix:///var/run/docker.sock", "TEST_SERVICE_ACTIVE": "0",
            "TEST_SUDO_EXIT": "0", "TEST_INSTALL_CLI": "1", "TEST_START_ACCESS": "1",
            "TEST_GROUPS": "fixture-user docker", "TEST_DOCKER_GROUP_EXISTS": "1",
            "TEST_WSL": "0",
            "TEST_OMARCHY": "1", "TEST_UWSM": "0", "TEST_UWSM_ACTIVE": "0",
            "TEST_LOGOUT_EXIT": "0", "OMARCHY_PATH": "/fixture/omarchy",
            "HYPRLAND_INSTANCE_SIGNATURE": "fixture-hyprland", "WAYLAND_DISPLAY": "fixture-wayland",
            "XDG_SESSION_ID": "fixture-session", "SSH_CONNECTION": "", "SSH_TTY": "",
        }
        self.env.pop("DOCKER_HOST", None)
        self.env.pop("DOCKER_CONTEXT", None)

    def test_selected_install_does_not_repeat_the_install_question(self):
        status, output, actions = self.run_driver(terminal=True, TEST_INSTALLED='0', TEST_SELECTED_ACTION='--install')
        self.assertEqual(status, 0, output)
        self.assertNotIn('Attempt to install Docker now?', output)
        self.assertTrue(any('sudo pacman' in action for action in actions), actions)

    def test_selected_start_does_not_repeat_the_start_question(self):
        status, output, actions = self.run_driver(terminal=True, TEST_ACCESS='0', TEST_SELECTED_ACTION='--start')
        self.assertEqual(status, 0, output)
        self.assertNotIn('Start the local Docker service now?', output)
        self.assertTrue(any('sudo systemctl start docker.service' in action for action in actions), actions)

    def run_driver(self, *, terminal=False, answer=b"", **changes):
        env = {**self.env, **changes}
        if terminal:
            master, slave = pty.openpty()
            try:
                process = subprocess.Popen(["bash", str(self.driver)], env=env, stdin=slave,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                os.close(slave)
                slave = None
                os.write(master, answer)
                try:
                    stdout, stderr = process.communicate(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate()
                    self.fail("Prerequisite prompt did not finish")
            finally:
                if slave is not None:
                    os.close(slave)
                os.close(master)
            status = process.returncode
            output = (stdout + stderr).decode()
        else:
            result = subprocess.run(["bash", str(self.driver)], env=env, input=answer,
                                    capture_output=True, timeout=10)
            status = result.returncode
            output = (result.stdout + result.stderr).decode()
        actions = self.actions.read_text().splitlines() if self.actions.exists() else []
        return status, output, actions

    def test_accessible_docker_needs_no_install_or_privilege_prompt(self):
        status, _, actions = self.run_driver()
        self.assertEqual(status, 0)
        self.assertEqual(actions, ["docker info"])

    def test_missing_docker_noninteractive_stops_without_installing(self):
        status, output, actions = self.run_driver(TEST_INSTALLED="0")
        self.assertEqual(status, 1)
        self.assertIn("interactive terminal", output)
        self.assertEqual(actions, [])

    def test_decline_quit_and_eof_do_not_install(self):
        for answer in (b"n\n", b"Q\n", b"\n", b"\x04"):
            with self.subTest(answer=answer):
                status, _, actions = self.run_driver(terminal=True, answer=answer, TEST_INSTALLED="0")
                self.assertEqual(status, 130)
                self.assertEqual(actions, [])

    def test_arch_and_omarchy_offer_compose_and_buildx(self):
        for os_id in ("arch", "omarchy"):
            with self.subTest(os_id=os_id):
                (self.directory / "installed").unlink(missing_ok=True)
                self.actions.unlink(missing_ok=True)
                status, _, actions = self.run_driver(terminal=True, answer=b"y\n", TEST_INSTALLED="0", TEST_OS=os_id)
                self.assertEqual(status, 0)
                self.assertEqual(actions, ["sudo pacman -S --needed docker docker-compose docker-buildx", "docker info"])

    def test_other_existing_linux_installers_still_work(self):
        for os_id, expected in (
            ("ubuntu", ["sudo apt update", "sudo apt install -y docker.io"]),
            ("fedora", ["sudo dnf install -y docker"]),
            ("alpine", ["sudo apk add docker"]),
        ):
            with self.subTest(os_id=os_id):
                (self.directory / "installed").unlink(missing_ok=True)
                self.actions.unlink(missing_ok=True)
                status, _, actions = self.run_driver(terminal=True, answer=b"y\n", TEST_INSTALLED="0", TEST_OS=os_id)
                self.assertEqual(status, 0)
                self.assertEqual(actions, expected + ["docker info"])

    def test_install_failure_and_cancellation_stop_before_daemon_check(self):
        for failure in (1, 130, 143):
            with self.subTest(failure=failure):
                self.actions.unlink(missing_ok=True)
                status, _, actions = self.run_driver(terminal=True, answer=b"y\n", TEST_INSTALLED="0", TEST_SUDO_EXIT=str(failure))
                self.assertEqual(status, failure)
                self.assertFalse(any(action.startswith("docker ") for action in actions))

    def test_install_without_cli_and_unsupported_os_stop(self):
        for changes in ({"TEST_INSTALL_CLI": "0"}, {"TEST_OS": "Darwin"}, {"TEST_OS": "unknown"}):
            with self.subTest(changes=changes):
                self.actions.unlink(missing_ok=True)
                status, _, actions = self.run_driver(terminal=True, answer=b"y\n", TEST_INSTALLED="0", **changes)
                self.assertEqual(status, 1)
                self.assertFalse(any(action.startswith("docker ") for action in actions))

    def test_start_stopped_local_daemon_and_recheck_user_access(self):
        status, _, actions = self.run_driver(terminal=True, answer=b"y\n", TEST_ACCESS="0")
        self.assertEqual(status, 0)
        self.assertIn("sudo systemctl start docker.service", actions)
        self.assertEqual(actions[-1], "docker info")

    def test_start_decline_does_not_change_daemon(self):
        status, _, actions = self.run_driver(terminal=True, answer=b"n\n", TEST_ACCESS="0")
        self.assertEqual(status, 130)
        self.assertFalse(any(action.startswith("sudo ") for action in actions))

    def test_daemon_start_failure_or_remaining_permission_failure_stops(self):
        for changes, expected in (({"TEST_SUDO_EXIT": "130"}, 130), ({"TEST_START_ACCESS": "0"}, 1)):
            with self.subTest(changes=changes):
                self.actions.unlink(missing_ok=True)
                status, _, _ = self.run_driver(terminal=True, answer=b"y\n", TEST_ACCESS="0", **changes)
                self.assertEqual(status, expected)

    def test_remote_rootless_and_active_daemon_failures_never_start_system_service(self):
        for changes in (
            {"DOCKER_HOST": "tcp://remote.example:2376"},
            {"TEST_ENDPOINT": "unix:///run/user/1000/docker.sock"},
            {"DOCKER_CONTEXT": "remote", "TEST_ENDPOINT": "ssh://remote.example", "DOCKER_HOST": "unix:///var/run/docker.sock"},
            {"TEST_SERVICE_ACTIVE": "1"},
        ):
            with self.subTest(changes=changes):
                self.actions.unlink(missing_ok=True)
                status, output, actions = self.run_driver(terminal=True, TEST_ACCESS="0", **changes)
                self.assertEqual(status, 1)
                self.assertIn("not accessible", output)
                self.assertFalse(any(action.startswith("sudo ") for action in actions))

    def test_nonmember_can_accept_group_setup_but_must_sign_in_again(self):
        status, output, actions = self.run_driver(
            terminal=True, answer=b"y\n\n", TEST_ACCESS="0",
            TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user")
        self.assertEqual(status, 1, output)
        self.assertIn('administrator-equivalent access', output)
        self.assertIn('Sign out and back in', output)
        self.assertIn('Your current shell still has its old groups', output)
        self.assertIn('You must sign out, sign back in and open a new terminal', output)
        self.assertIn('rerun ./setup.sh', output)
        self.assertEqual(actions, ["docker info", "docker context inspect --format {{.Endpoints.docker.Host}}",
                                   "systemctl show -p LoadState --value docker.service",
                                   "systemctl is-active --quiet docker.service",
                                   "sudo usermod -aG docker fixture-user"])
        self.assertTrue((self.directory / "group-added").exists())
        self.assertNotIn('daemon is accessible', output)

        # Rerunning in the old shell still lacks access, even after usermod succeeds.
        self.actions.unlink()
        status, output, actions = self.run_driver(
            TEST_ACCESS="0", TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user")
        self.assertEqual(status, 1, output)
        self.assertFalse(any(action.startswith("sudo ") for action in actions))

        # Model a fresh login with the new group and working Docker access.
        self.actions.unlink()
        status, output, actions = self.run_driver(TEST_GROUPS="fixture-user docker", TEST_ACCESS="1")
        self.assertEqual(status, 0, output)
        self.assertEqual(actions, ["docker info"])
        self.assertNotIn('Add your user', output)

    def test_nonmember_can_decline_cancel_or_end_group_prompt_without_changes(self):
        for answer, expected in ((b"n\n", 1), (b"\n", 1), (b"Q\n", 130),
                                 (b"q\n", 130), (b"\x04", 130)):
            with self.subTest(answer=answer):
                self.actions.unlink(missing_ok=True)
                status, output, actions = self.run_driver(
                    terminal=True, answer=answer, TEST_ACCESS="0",
                    TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user")
                self.assertEqual(status, expected, output)
                self.assertIn('Add your user to the docker group?', output)
                self.assertFalse(any(action.startswith("sudo ") for action in actions))
                self.assertFalse((self.directory / "group-added").exists())

    def test_group_setup_preserves_sudo_failure_and_cancellation(self):
        for failure in (1, 130, 143):
            with self.subTest(failure=failure):
                self.actions.unlink(missing_ok=True)
                status, output, actions = self.run_driver(
                    terminal=True, answer=b"y\n", TEST_ACCESS="0", TEST_SERVICE_ACTIVE="1",
                    TEST_GROUPS="fixture-user", TEST_SUDO_EXIT=str(failure))
                self.assertEqual(status, failure, output)
                self.assertIn('sudo usermod -aG docker fixture-user', actions)
                self.assertNotIn('Sign out and back in', output)
                self.assertFalse((self.directory / "group-added").exists())

    def test_nonmember_is_offered_group_setup_after_starting_daemon(self):
        status, output, actions = self.run_driver(
            terminal=True, answer=b"y\ny\n\n", TEST_ACCESS="0", TEST_START_ACCESS="0",
            TEST_GROUPS="fixture-user")
        self.assertEqual(status, 1, output)
        self.assertIn('Start the local Docker service now?', output)
        self.assertIn('Add your user to the docker group?', output)
        self.assertEqual(actions, ["docker info", "docker context inspect --format {{.Endpoints.docker.Host}}",
                                   "systemctl show -p LoadState --value docker.service",
                                   "systemctl is-active --quiet docker.service",
                                   "sudo systemctl start docker.service", "docker info",
                                   "sudo usermod -aG docker fixture-user"])
        self.assertIn('Sign out and back in', output)

    def test_group_instruction_waits_for_acknowledgment_before_tui_redraw(self):
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["bash", str(self.driver)], stdin=slave, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env={**self.env, "TEST_TUI": "1", "TEST_ACCESS": "0",
                 "TEST_SERVICE_ACTIVE": "1", "TEST_GROUPS": "fixture-user"})
        os.close(slave)
        output = b""
        try:
            os.write(master, b"y\n")
            deadline = time.monotonic() + 10
            while b'Sign out now so you can sign back in?' not in output:
                remaining = deadline - time.monotonic()
                self.assertGreater(remaining, 0, output.decode())
                ready, _, _ = select.select([process.stdout], [], [], max(0, remaining))
                self.assertTrue(ready, output.decode())
                chunk = os.read(process.stdout.fileno(), 4096)
                self.assertTrue(chunk, output.decode())
                output += chunk
            self.assertIn(b'Sign out and back in', output)
            self.assertNotIn(b'MENU_REDRAW', output)
            self.assertNotIn(b'STATUS_REFRESH', output)
            # Once the prompt is printed, no input means the caller must stay blocked.
            with self.assertRaises(subprocess.TimeoutExpired):
                process.wait(timeout=0.3)
            os.write(master, b"\n")
            tail, _ = process.communicate(timeout=10)
            output += tail
            self.assertEqual(process.returncode, 0, output.decode())
            self.assertIn(b'MENU_REDRAW', output)
            self.assertLess(output.index(b'Sign out and back in'), output.index(b'MENU_REDRAW'))
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
            process.stdout.close()
            os.close(master)

    def test_group_instruction_acknowledgment_can_quit_or_reach_eof(self):
        for answer in (b"y\nQ\n", b"y\nq\n", b"y\n\x04"):
            with self.subTest(answer=answer):
                self.actions.unlink(missing_ok=True)
                status, output, actions = self.run_driver(
                    terminal=True, answer=answer, TEST_ACCESS="0",
                    TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user")
                self.assertEqual(status, 130, output)
                self.assertIn('Sign out and back in', output)
                self.assertIn('Sign out now so you can sign back in?', output)
                self.assertEqual(actions.count('sudo usermod -aG docker fixture-user'), 1)
                self.assertFalse(any(action.startswith('loginctl ') for action in actions))

    def test_explicit_yes_signs_out_only_the_current_session_and_stops_setup(self):
        for answer in (b'y\ny\n', b'y\nyes\n'):
            with self.subTest(answer=answer):
                self.actions.unlink(missing_ok=True)
                status, output, actions = self.run_driver(
                    terminal=True, answer=answer, TEST_TUI="1", TEST_ACCESS="0",
                    TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user")
                self.assertEqual(status, 130, output)
                self.assertIn('Save your work first', output)
                self.assertEqual(actions[-1], 'omarchy system logout')
                self.assertEqual(actions.count('omarchy system logout'), 1)
                self.assertFalse(any(action.startswith('loginctl ') for action in actions))
                self.assertNotIn('MENU_REDRAW', output)
                self.assertNotIn('STATUS_REFRESH', output)

    def test_declining_signout_leaves_session_running_and_docker_unavailable(self):
        for answer in (b'y\nn\n', b'y\n\n', b'y\ninvalid\nno\n'):
            with self.subTest(answer=answer):
                self.actions.unlink(missing_ok=True)
                status, output, actions = self.run_driver(
                    terminal=True, answer=answer, TEST_ACCESS="0",
                    TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user")
                self.assertEqual(status, 1, output)
                self.assertIn('Your current shell still has its old groups', output)
                self.assertFalse(any(action.startswith('loginctl ') for action in actions))

    def test_unavailable_or_failed_signout_keeps_manual_instructions_visible(self):
        for changes, invoked in (({"TEST_OMARCHY": "0"}, False),
                                 ({"OMARCHY_PATH": ""}, False),
                                 ({"HYPRLAND_INSTANCE_SIGNATURE": ""}, False),
                                 ({"SSH_CONNECTION": "fixture remote connection"}, False),
                                 ({"SSH_TTY": "/dev/pts/99"}, False),
                                 ({"TEST_LOGOUT_EXIT": "1"}, True)):
            with self.subTest(changes=changes):
                self.actions.unlink(missing_ok=True)
                status, output, actions = self.run_driver(
                    terminal=True, answer=b'y\ny\n\n', TEST_ACCESS="0",
                    TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user", **changes)
                self.assertEqual(status, 1, output)
                self.assertIn('Sign out manually, then sign back in', output)
                self.assertIn('Press Enter to return to setup', output)
                self.assertEqual('omarchy system logout' in actions, invoked)
                self.assertFalse(any(action.startswith('loginctl ') for action in actions))

    def test_uwsm_logout_requires_an_active_graphical_session(self):
        for active, expected in (("0", 130), ("1", 1)):
            with self.subTest(active=active):
                self.actions.unlink(missing_ok=True)
                status, output, actions = self.run_driver(
                    terminal=True, answer=b'y\ny\n\n', TEST_ACCESS="0",
                    TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user",
                    TEST_OMARCHY="0", TEST_UWSM="1", TEST_UWSM_ACTIVE=active)
                self.assertEqual(status, expected, output)
                self.assertIn('uwsm check is-active', actions)
                self.assertEqual('uwsm stop' in actions, active == "0")
                self.assertFalse(any(action.startswith('loginctl ') for action in actions))

    def test_group_setup_is_not_offered_for_ineligible_contexts_or_users(self):
        for terminal, changes in (
            (False, {}),
            (True, {"DOCKER_HOST": "tcp://remote.example:2376"}),
            (True, {"TEST_ENDPOINT": "unix:///run/user/1000/docker.sock"}),
            (True, {"TEST_GROUPS": "fixture-user docker"}),
            (True, {"TEST_DOCKER_GROUP_EXISTS": "0"}),
            (True, {"TEST_WSL": "1"}),
        ):
            with self.subTest(terminal=terminal, changes=changes):
                self.actions.unlink(missing_ok=True)
                env = {"TEST_ACCESS": "0", "TEST_SERVICE_ACTIVE": "1",
                       "TEST_GROUPS": "fixture-user", **changes}
                status, output, actions = self.run_driver(terminal=terminal, **env)
                self.assertEqual(status, 1, output)
                self.assertNotIn('Add your user', output)
                self.assertFalse(any(action.startswith("sudo ") for action in actions))

    def test_similarly_named_group_does_not_count_as_docker_membership(self):
        status, output, actions = self.run_driver(
            terminal=True, answer=b"n\n", TEST_ACCESS="0",
            TEST_SERVICE_ACTIVE="1", TEST_GROUPS="fixture-user docker-builders")
        self.assertEqual(status, 1, output)
        self.assertIn('Add your user to the docker group?', output)
        self.assertFalse(any(action.startswith("sudo ") for action in actions))

    def test_full_setup_checks_docker_before_any_host_onboarding_or_build(self):
        fixture = self.directory / "workBenches"
        (fixture / "scripts/lib").mkdir(parents=True)
        (fixture / "base-image").mkdir()
        (fixture / "config").mkdir()
        (self.directory / "home/.config/workbenches").mkdir(parents=True)
        (self.directory / "home/.config/workbenches/claude-profiles.json").write_text('{"profiles":[{}]}')
        for name in ("setup.sh", "bootstrap.sh"):
            shutil.copy(ROOT / name, fixture / name)
        for name in ("docker-prerequisite.sh", "setup-prerequisites.sh", "setup-prompts.sh", "setup-progress.sh", "tools-container.sh", "setup-status-loader.sh"):
            shutil.copy(ROOT / "scripts/lib" / name, fixture / "scripts/lib")
        shutil.copy(ROOT / "scripts/setup_selection.py", fixture / "scripts")
        (fixture / "config/bench-config.json").write_text('{"benches":{"dev":{"path":"devBenches/testBench"}}}')
        for name, action in (
            ("setup-shell.sh", "shell"), ("setup-estate-commands.sh", "estate"),
            ("setup-workspace-repo.sh", "workspace"), ("setup-claude-workflows.sh", "workflow"),
            ("setup-ai-profiles.sh", "recovery"), ("interactive-setup.sh", "selected"),
        ):
            path = fixture / "scripts" / name
            path.write_text(f'#!/usr/bin/env bash\necho {action} >> "$TEST_LOG"\n')
            path.chmod(0o755)
        (fixture / "scripts/interactive-setup.sh").write_text('''#!/usr/bin/env bash
if [[ "$1" == --select-only ]]; then
  echo selected >> "$TEST_LOG"
  echo '{"schemaVersion":1,"components":[{"key":"bench_dev","action":"install"},{"key":"claude_cli","action":"install"}]}' > "$2"
fi
if [[ "$1" == --apply-plan ]]; then echo apply >> "$TEST_LOG"; fi
''')
        path = fixture / "base-image/build.sh"
        path.write_text('#!/usr/bin/env bash\necho build >> "$TEST_LOG"\n')
        path.chmod(0o755)
        binaries = self.directory / "bin"
        binaries.mkdir()
        path = binaries / "docker"
        path.write_text('''#!/usr/bin/env bash
echo "docker $1" >> "$TEST_LOG"
if [[ "$1" == info ]]; then echo linux; exit "$TEST_DOCKER_EXIT"; fi
if [[ "$1" == context ]]; then echo tcp://remote.example:2376; exit 0; fi
exit 1
''')
        path.chmod(0o755)
        (binaries / "python3").write_text(f'#!/usr/bin/env bash\ncase "$1" in */shared-images.py) echo "image acquisition" >> "$TEST_LOG"; exit 1 ;; */setup_selection.py|-c|-) exec {sys.executable} "$@" ;; *) exit 0 ;; esac\n')
        (binaries / "python3").chmod(0o755)
        env = {**self.env, "HOME": str(self.directory / "home"),
               "XDG_CONFIG_HOME": str(self.directory / "home/.config"),
               "AGENT_PROTOCOL_ROOT": str(self.directory / "home/.agents"),
               "WORKBENCHES_SKIP_WAVE_WIDGETS": "1", "WORKBENCHES_TEST_NATIVE_TOOLS": "1", "PATH": f"{binaries}:{os.environ['PATH']}"}
        for docker_status in (1, 130, 143, 0):
            with self.subTest(docker_status=docker_status):
                self.actions.unlink(missing_ok=True)
                result = subprocess.run(["bash", str(fixture / "setup.sh")],
                                        env={**env, "TEST_DOCKER_EXIT": str(docker_status)},
                                        stdin=subprocess.DEVNULL, capture_output=True, timeout=10)
                actions = self.actions.read_text().splitlines()
                self.assertEqual(result.returncode, 1 if docker_status else 0, result.stderr.decode())
                if docker_status:
                    self.assertTrue(all(action.startswith("docker ") for action in actions), actions)
                else:
                    self.assertEqual(actions, ["docker info", "selected", "docker info", "recovery", "estate",
                                               "image acquisition", "build", "apply"])


if __name__ == "__main__":
    unittest.main()
