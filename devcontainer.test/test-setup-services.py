#!/usr/bin/env python3
"""Service readiness and ownership checks without touching a Docker engine."""
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
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

    def test_desktop_socket_access_uses_wsl_group_and_mac_vm_group(self):
        for system, expected in (('Linux', '1001'), ('Darwin', '0')):
            with self.subTest(system=system), tempfile.TemporaryDirectory() as home:
                output = self.shell(f'''
HOME={home!r}; XDG_CACHE_HOME="$HOME/.cache"
workbenches_docker_state() {{ echo up; }}
workbenches_pin_docker() {{ WORKBENCHES_DOCKER_ENDPOINT=unix:///var/run/docker.sock; }}
workbenches_tools_fingerprint() {{ echo runtime; }}
workbenches_tools_image_fingerprint() {{ echo image; }}
workbenches_services_network() {{ :; }}
workbenches_tools_state() {{ echo up; }}
uname() {{ echo {system}; }}
stat() {{ echo 1001; }}
workbenches_runtime_docker() {{
    case "$1 $2" in
        'container inspect') return 1 ;;
        'image inspect') echo image ;;
        'info --format')
            if [[ "$3" == *OperatingSystem* ]]; then echo 'Docker Desktop'; else echo engine; fi ;;
        'create --name')
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == --group-add ]]; then echo "socket-group:$2" >&2; fi
                shift
            done ;;
        'container start') : ;;
        'exec '*) echo engine ;;
        *) echo "UNEXPECTED:$*" >&2; return 99 ;;
    esac
}}
workbenches_tools_start 2>&1
''')
                self.assertEqual(output, 'socket-group:' + expected)

    def test_launcher_finishes_when_broker_ignores_term(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            scripts = home / 'repo/scripts'
            (scripts / 'lib').mkdir(parents=True)
            shutil.copy(ROOT / 'scripts/tools-command.sh', scripts / 'tools-command.sh')
            (scripts / 'lib/tools-container.sh').write_text('''workbenches_tools_state() { echo up; }
workbenches_runtime_docker() { :; }
''')
            (scripts / 'lib/tools-host-broker.sh').write_text('''trap '' TERM
touch "$1/alive"
printf '%s' "$$" > "$HOME/broker-pid"
while :; do sleep 0.05; done
''')
            env = dict(os.environ, HOME=str(home), XDG_CACHE_HOME=str(home / '.cache'),
                       WORKBENCHES_TOOLS_ROOT=str(scripts.parent), WORKBENCHES_TOOLS_CONTAINER='fixture')
            result = subprocess.run(['bash', str(scripts / 'tools-command.sh'), 'python3', '--version'],
                                    env=env, capture_output=True, text=True, timeout=6)
            self.assertEqual(result.returncode, 0, result.stderr)
            with self.assertRaises(ProcessLookupError):
                os.kill(int((home / 'broker-pid').read_text()), 0)
            self.assertFalse(list((home / '.cache/workbenches/tools/sessions').iterdir()))


if __name__ == '__main__':
    unittest.main()
