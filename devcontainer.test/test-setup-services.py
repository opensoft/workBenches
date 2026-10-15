#!/usr/bin/env python3
"""Service readiness and ownership checks without touching a Docker engine."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'scripts/lib/tools-container.sh'


class ServiceTests(unittest.TestCase):
    def shell(self, body):
        result = subprocess.run(['bash', '-c', f'source "$1"\n{body}', 'test', str(LIB)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_docker_unreachable_and_windows_engine_are_down(self):
        for answer in ('return 1', 'echo windows'):
            with self.subTest(answer=answer):
                self.assertEqual(self.shell(f'docker() {{ {answer}; }}; workbenches_docker_state'), 'down')

    def test_managed_container_requires_owner_home_and_health(self):
        for role in ('tools', 'vault'):
            for owner, uid, home, running, health, expected in (
                (role, str(os.getuid()), os.environ['HOME'], 'true', 'healthy', 'up'),
                (role, str(os.getuid()), os.environ['HOME'], 'false', 'healthy', 'down'),
                (role, str(os.getuid()), os.environ['HOME'], 'true', 'unhealthy', 'down'),
                ('foreign', str(os.getuid()), os.environ['HOME'], 'true', 'healthy', 'down'),
                (role, '987654', os.environ['HOME'], 'true', 'healthy', 'down'),
                (role, str(os.getuid()), '/other-home', 'true', 'healthy', 'down'),
            ):
                with self.subTest(role=role, expected=expected, health=health, owner=owner, uid=uid, home=home):
                    record = '|'.join((owner, uid, running, health, home))
                    self.assertEqual(self.shell(f'''workbenches_docker_state() {{ echo up; }}
workbenches_runtime_docker() {{ printf '%s' "$RECORD"; }}
RECORD={record!r}
workbenches_managed_state sample {role}'''), expected)

    def test_missing_is_distinct_from_inspect_failure(self):
        for error, expected in (('Error: No such container: sample', 'missing'), ('permission denied', 'down')):
            with self.subTest(error=error):
                self.assertEqual(self.shell(f'''workbenches_docker_state() {{ echo up; }}
workbenches_runtime_docker() {{ echo {error!r} >&2; return 1; }}
workbenches_managed_state sample tools'''), expected)

    def test_foreign_name_never_causes_build_stop_or_delete(self):
        for role in ('tools', 'vault'):
            output = self.shell(f'''workbenches_docker_state() {{ echo up; }}
workbenches_pin_docker() {{ :; }}
workbenches_runtime_docker() {{
    if [[ "$1 $2" == 'container inspect' ]]; then echo 'foreign|0|fingerprint|/somewhere'; return; fi
    echo "UNEXPECTED:$*"; return 99
}}
workbenches_{role}_start && exit 20
:''')
            self.assertNotIn('UNEXPECTED', output)

    def test_remote_engine_is_rejected(self):
        self.assertEqual(self.shell('DOCKER_HOST=tcp://remote:2376; unset DOCKER_CONTEXT; workbenches_pin_docker && exit 20; echo rejected'), 'rejected')


if __name__ == '__main__':
    unittest.main()
