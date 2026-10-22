#!/usr/bin/env python3
"""Exercise catalog readers with digit-leading names, without host setup."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    sys.path.insert(0, str(ROOT / 'scripts'))
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'scripts' / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class CatalogLookups(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'config').mkdir()
        (self.root / 'scripts').mkdir()
        self.path = 'sysBenches/365Bench'
        self.url = 'https://github.com/example/365Bench.git'
        self.description = 'Digit-leading fixture description'
        self.catalog = {'benches': {'365Bench': {'path': self.path, 'url': self.url,
                                               'description': self.description}},
                        'infrastructure': {'365Bench': {'path': self.path, 'url': self.url,
                                                      'description': self.description}}}
        (self.root / 'config/bench-config.json').write_text(json.dumps(self.catalog))
        (self.root / self.path).mkdir(parents=True)
        (self.root / '365Bench').mkdir()  # decoy must not be chosen
        self.selection = self.root / 'selection.json'
        self.selection.write_text(json.dumps({'schemaVersion': 1, 'components': [
            {'key': 'bench_365Bench', 'action': 'install'}]}))
        self.selection.chmod(0o600)

    def shell(self, body):
        result = subprocess.run(['bash', '-ec', body], text=True, capture_output=True,
                                env=dict(os.environ, FIXTURE=str(self.root), WORKBENCHES_SETUP_LOG_FILE='/dev/null'),
                                timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def test_no_name_built_lookup_in_tracked_shell(self):
        bad = []
        for name in subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines():
            p = ROOT / name
            if not p.is_file():
                continue
            data = p.read_bytes()
            if not (name.endswith('.sh') or p.name == 'launchBench' or
                    re.match(rb'#![^\n]*\b(?:bash|sh)\b', data)):
                continue
            text = data.decode('utf-8', errors='replace')
            for line, s in enumerate(text.splitlines(), 1):
                # Single-quoted jq variables are data bindings, not shell expansion.
                shell_expanded = re.sub(r"'[^']*'", '', s)
                if re.search(r'\.(benches|infrastructure)\s*(\.|\[)\s*"?\\?"?\$', shell_expanded):
                    bad.append(f'{name}:{line}: {s.strip()}')
            # Catalog jq programs are quoted strings; inspect those after jq,
            # including programs continued onto the following line.
            for match in re.finditer(r'\bjq\b[^\n]*(?:\\\n[^\n]*)*', text):
                for quoted in re.finditer(r'''(["'])(.*?)(?<!\\)\1''', match.group(), re.S):
                    program = quoted.group(2)
                    if '${' in program and program.lstrip().startswith(('.', '{', '[')):
                        bad.append(f'{name}:{text.count(chr(10), 0, match.start())+1}: interpolated jq program')
        self.assertEqual(bad, [], '\n'.join(bad))

    def test_shell_catalog_sites_resolve_name_as_data(self):
        # Run every production per-name jq expression, including apply, URL,
        # description and infrastructure sites, against the same fixture.
        for filename in ('interactive-setup.sh', 'setup-workbenches.sh', 'update-project.sh', 'launchBench'):
            sites = []
            for line in (ROOT / 'scripts' / filename).read_text().splitlines():
                if 'jq -r ' not in line or not re.search(r'\.(benches|infrastructure)(\.|\[)', line):
                    continue
                start = line.index('jq -r ')
                command = line[start:]
                command = re.split(r'\s+"\$(?:config_file|CONFIG_FILE|catalog_file)"', command)[0]
                field = re.search(r'\.(path|url|description)\b', command)
                if not field:
                    continue
                sites.append(command)
                expected = {'path': self.path, 'url': self.url, 'description': self.description}[field[1]]
                with self.subTest(file=filename, command=command):
                    output = self.shell('bench_name=365Bench; bench=365Bench; infra_name=365Bench; catalog_name=365Bench\n' +
                                        command + ' "$FIXTURE/config/bench-config.json"')
                    self.assertEqual(output, expected)
            self.assertTrue(sites, filename)

    def test_status_checks_real_checkout_not_root_decoy(self):
        shutil.copytree(ROOT / 'scripts', self.root / 'scripts', dirs_exist_ok=True)
        shutil.copy2(ROOT / 'bootstrap.sh', self.root / 'bootstrap.sh')
        directory = self.root / self.path
        subprocess.run(['git', 'init', '-q', str(directory)], check=True)
        subprocess.run(['git', '-C', str(directory), 'remote', 'add', 'origin', self.url], check=True)
        (directory / '.devcontainer').mkdir()
        output = self.shell('source "$FIXTURE/scripts/interactive-setup.sh"\n'
                            'bench_runtime_status[365Bench]=installed\ncheck_component_status bench_365Bench')
        self.assertEqual(output, 'installed')

    def test_workspace_and_update_directory_readers(self):
        for filename, function in (('setup-workbenches.sh', 'is_installed'),
                                   ('update-project.sh', 'is_bench_installed')):
            text = (ROOT / 'scripts' / filename).read_text()
            body = re.search(r'^' + function + r'\(\) \{.*?^\}', text, re.M | re.S).group()
            with self.subTest(file=filename):
                self.shell('SCRIPT_DIR="$FIXTURE/scripts"; CONFIG_FILE="$FIXTURE/config/bench-config.json"\n' +
                           body + '\n' + function + ' 365Bench')
                (self.root / self.path).rmdir()
                try:
                    self.shell(body + '\nSCRIPT_DIR="$FIXTURE/scripts"; CONFIG_FILE="$FIXTURE/config/bench-config.json"\n' +
                               'if ' + function + ' 365Bench; then exit 91; fi')
                finally:
                    (self.root / self.path).mkdir()

    def test_unresolved_paths_fail_closed_before_any_apply(self):
        shutil.copytree(ROOT / 'scripts', self.root / 'scripts', dirs_exist_ok=True)
        shutil.copy2(ROOT / 'bootstrap.sh', self.root / 'bootstrap.sh')
        for path in ('', '/tmp/outside', 'elsewhere/365Bench', 'sysBenches/../365Bench'):
            self.catalog['benches']['365Bench']['path'] = path
            (self.root / 'config/bench-config.json').write_text(json.dumps(self.catalog))
            for action in ('install', 'update', 'uninstall'):
                with self.subTest(path=path, action=action):
                    output = self.shell(r'''source "$FIXTURE/scripts/interactive-setup.sh"
clear() { :; }; log() { :; }
refresh_component_statuses() { :; }; show_pending_authentication() { :; }
git() { printf 'git %s\n' "$PWD" >> "$FIXTURE/calls"; return 90; }
docker() { printf 'docker %s\n' "$PWD" >> "$FIXTURE/calls"; return 90; }
bash() { printf 'bash %s\n' "$PWD" >> "$FIXTURE/calls"; return 90; }
python3() { printf 'python3 %s\n' "$PWD" >> "$FIXTURE/calls"; return 90; }
uninstall_component() { printf 'uninstall %s\n' "$PWD" >> "$FIXTURE/calls"; return 90; }
bench_items=(365Bench); ai_items=(); tool_items=()
component_checked[bench_365Bench]=true
component_action[bench_365Bench]=''' + action + r'''
component_status[bench_365Bench]='needs setup'
component_description[bench_365Bench]=365Bench
if process_selections; then echo UNEXPECTED_SUCCESS; exit 92; fi
''')
                    self.assertIn('cannot resolve 365Bench in the bench catalog', output)
                    self.assertIn('Failed: 1', output)
                    self.assertFalse((self.root / 'calls').exists())
            output = self.shell('source "$FIXTURE/scripts/interactive-setup.sh"\n'
                                'bench_runtime_status[365Bench]=installed\ncheck_component_status bench_365Bench')
            self.assertEqual(output, 'needs check')

    def test_python_selection_reader(self):
        m = module('setup_selection'); m.REPO = self.root
        with patch.object(sys, 'argv', ['setup_selection.py', 'benches', str(self.selection)]), patch('builtins.print') as out:
            self.assertEqual(m.main(), 0)
        out.assert_called_once_with(self.path)

    def test_python_component_reader(self):
        m = module('setup-components'); m.ROOT = self.root
        self.assertEqual(m.bench_identity('365Bench')[0], self.root / self.path)

    def test_python_release_reader(self):
        m = module('release-workbenches')
        with patch.object(m, 'git', return_value=''):
            self.assertEqual(m.sources(self.root), {self.path: {'url': self.url}})
        manifest = {'repositories': [{'path': self.path, 'url': self.url, 'commit': 'abc123'}]}
        (self.root / self.path / '.git').mkdir()
        with patch.object(m, 'validate', return_value=manifest), patch.object(m, 'checkout_identity', return_value='abc123') as identity:
            m.prepare(self.root, self.selection)
        self.assertTrue(identity.call_args_list)
        self.assertTrue(all(call.args == (self.root / self.path,) for call in identity.call_args_list))

    def test_python_removal_reader(self):
        m = module('remove-bench-checkout'); m.ROOT = self.root
        # Refuse at the verification seam before any confirmation/deletion.
        with patch.object(sys, 'argv', ['remove-bench-checkout.py', '--bench', '365Bench']), \
             patch.object(m, 'verify', side_effect=RuntimeError('fixture stop')) as verify:
            with self.assertRaisesRegex(RuntimeError, 'fixture stop'):
                m.main()
        verify.assert_called_once_with(self.root / self.path)


if __name__ == '__main__':
    unittest.main()
