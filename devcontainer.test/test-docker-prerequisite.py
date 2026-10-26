#!/usr/bin/env python3
"""Exercise Docker prerequisite prompts and setup ordering with mocked commands."""

from __future__ import annotations

import os
from pathlib import Path
import pty
import shutil
import subprocess
import sys
import tempfile
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
source "$TEST_HELPER"
trap 'exit 130' INT
trap 'exit 143' TERM
workbenches_docker_os() { printf '%s\\n' "$TEST_OS"; }
# These package-manager cases model native Linux even on a WSL test host.
workbenches_is_wsl() { return 1; }
command() {
    if [[ "${1:-}" == -v && "${2:-}" == docker ]]; then
        [[ "$TEST_INSTALLED" == 1 || -f "$TEST_STATE/installed" ]]
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
    else
        [[ "$TEST_INSTALL_CLI" != 1 ]] || touch "$TEST_STATE/installed"
    fi
}
if ensure_docker "${TEST_SELECTED_ACTION:-}"; then exit 0; else exit $?; fi
''')
        self.env = {
            **os.environ,
            "TEST_HELPER": str(ROOT / "scripts/lib/docker-prerequisite.sh"),
            "TEST_LOG": str(self.actions), "TEST_STATE": str(self.directory),
            "TEST_OS": "arch", "TEST_INSTALLED": "1", "TEST_ACCESS": "1",
            "TEST_ENDPOINT": "unix:///var/run/docker.sock", "TEST_SERVICE_ACTIVE": "0",
            "TEST_SUDO_EXIT": "0", "TEST_INSTALL_CLI": "1", "TEST_START_ACCESS": "1",
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

    def test_full_setup_checks_docker_before_any_host_onboarding_or_build(self):
        fixture = self.directory / "workBenches"
        (fixture / "scripts/lib").mkdir(parents=True)
        (fixture / "base-image").mkdir()
        (fixture / "config").mkdir()
        (self.directory / "home/.config/workbenches").mkdir(parents=True)
        (self.directory / "home/.config/workbenches/claude-profiles.json").write_text('{"profiles":[{}]}')
        for name in ("setup.sh", "bootstrap.sh"):
            shutil.copy(ROOT / name, fixture / name)
        for name in ("docker-prerequisite.sh", "setup-prerequisites.sh", "setup-prompts.sh", "tools-container.sh", "setup-status-loader.sh", "openbenches-compat.sh"):
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
