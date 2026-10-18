#!/usr/bin/env python3
"""Exercise service readiness without invoking the hanging server CLI."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class VibeReadinessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.commands = self.directory / "commands"
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        for name, script in {
            "docker": '''#!/usr/bin/env bash
printf 'docker %s\\n' "$*" >> "$TEST_COMMANDS"
# A regression must fail rather than invoke the server CLI or real Docker.
if [[ "$1" == exec ]]; then
    [[ "$TEST_CONTAINER_TOOLS" == 1 && "$3" == node && "$4" == -e ]] || exit 99
    [[ "$5" == *'AbortSignal.timeout(2000)'* && "$5" == *'/health'* ]] || exit 99
    printf '%s' "$TEST_HEALTH"
    exit "$TEST_CURL_STATUS"
fi
''',
            "curl": '''#!/usr/bin/env bash
printf 'curl %s\\n' "$*" >> "$TEST_COMMANDS"
printf '%s' "$TEST_HEALTH"
exit "$TEST_CURL_STATUS"
''',
            "sleep": "#!/usr/bin/env bash\nexit 0\n",
        }.items():
            path = self.bin / name
            path.write_text(script)
            path.chmod(0o755)

    def run_setup(self, health, curl_status=0, container_tools=False):
        env = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "VIBE_ANNOTATIONS_HOME_DIR": str(self.directory / "vibe"),
            "VIBE_ANNOTATIONS_VERSION": "0.5.1",
            "TEST_COMMANDS": str(self.commands),
            "TEST_HEALTH": health,
            "TEST_CURL_STATUS": str(curl_status),
            "TEST_CONTAINER_TOOLS": '1' if container_tools else '0',
            "WORKBENCHES_CONTAINER_TOOLS": '1' if container_tools else '0',
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/ensure-vibe-annotations.sh")],
            env=env, capture_output=True, text=True, timeout=10,
        )
        commands = self.commands.read_text().splitlines()
        curls = [command for command in commands if command.startswith("curl ")]
        probes = [command for command in commands if command.startswith("docker exec ")]
        if container_tools:
            self.assertFalse(curls, 'Tools must not probe its own loopback for the host service')
            self.assertTrue(probes)
        else:
            self.assertFalse(probes)
            self.assertTrue(curls)
            self.assertTrue(all("--max-time 2" in command for command in curls))
            probes = curls
        return result, probes

    def test_matching_running_server_finishes_without_cli(self):
        result, curls = self.run_setup(json.dumps({"status": "ok", "version": "0.5.1"}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("v0.5.1 is ready", result.stderr)
        self.assertEqual(len(curls), 1)

    def test_wrong_running_version_is_rejected(self):
        result, _ = self.run_setup(json.dumps({"status": "ok", "version": "0.4.0"}))
        self.assertEqual(result.returncode, 1)
        self.assertIn("Version mismatch", result.stderr)

    def test_invalid_or_unhealthy_responses_have_bounded_retries(self):
        for health in ("not JSON", "[]", '{"status":"ok"}',
                       '{"status":"ok","version":null}',
                       '{"status":"starting","version":"0.5.1"}'):
            with self.subTest(health=health):
                self.commands.unlink(missing_ok=True)
                result, curls = self.run_setup(health)
                self.assertEqual(result.returncode, 1)
                self.assertIn("Service did not become healthy", result.stderr)
                self.assertEqual(len(curls), 30)

    def test_http_failure_never_reports_ready(self):
        result, curls = self.run_setup('{"status":"ok","version":"0.5.1"}', 7)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(curls), 30)
        self.assertNotIn("is ready", result.stderr)

    def test_tools_mode_queries_running_service_without_host_curl(self):
        result, probes = self.run_setup('{"status":"ok","version":"0.5.1"}', container_tools=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('v0.5.1 is ready', result.stderr)
        self.assertEqual(len(probes), 1)

    def test_tools_mode_rejects_wrong_version_and_bounds_http_failures(self):
        result, _ = self.run_setup('{"status":"ok","version":"0.4.0"}', container_tools=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Version mismatch', result.stderr)
        self.commands.unlink()
        result, probes = self.run_setup('', 7, container_tools=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(probes), 30)
        self.assertNotIn('is ready', result.stderr)


if __name__ == "__main__":
    unittest.main()
