#!/usr/bin/env python3
"""Release source identity, local-work protection, and offline version reporting."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release', ROOT / 'scripts/release-workbenches.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.root = self.directory / 'assembly'; self.root.mkdir()
        self.remote = self.directory / 'source'; self.remote.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null',
                        GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                        GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
        self.git(self.root, 'init', '-q'); self.git(self.remote, 'init', '-q')
        (self.remote / 'source').write_text('frozen')
        self.commit(self.remote)
        self.pin = self.git(self.remote, 'rev-parse', 'HEAD')
        self.path = 'devBenches/fixtureBench'; self.checkout = self.root / self.path
        self.checkout.parent.mkdir()
        self.git(self.root, 'clone', '-q', self.remote.as_uri(), str(self.checkout))
        (self.root / 'config').mkdir()
        (self.root / 'config/bench-config.json').write_text(json.dumps({'benches': {
            'fixtureBench': {'path': self.path, 'url': self.remote.as_uri()}}}))
        (self.root / 'VERSION').write_text('1.5.0\n')
        (self.root / '.gitignore').write_text(self.path + '/\n')
        shutil.copy(ROOT / 'bootstrap.sh', self.root / 'bootstrap.sh')
        self.commit(self.root)
        self.selection = self.directory / 'selection.json'
        self.selection.write_text(json.dumps({'schemaVersion': 1, 'components': [
            {'key': 'bench_fixtureBench', 'action': 'install'}]}))

    def git(self, root, *arguments):
        result = subprocess.run(['git', '-C', str(root), *arguments], env=self.env,
                                capture_output=True, text=True, check=True)
        return result.stdout.strip()

    def commit(self, root):
        self.git(root, 'add', '.')
        self.git(root, 'commit', '-qm', 'fixture')

    def freeze(self):
        manifest = release.freeze(self.root)
        self.commit(self.root)
        return manifest

    def test_version_needs_no_docker_tools_or_log_directory(self):
        shutil.copy(ROOT / 'setup.sh', self.root / 'setup.sh')
        binary = self.directory / 'bin'; binary.mkdir()
        (binary / 'dirname').symlink_to(shutil.which('dirname'))
        result = subprocess.run(['/bin/bash', str(self.root / 'setup.sh'), '--version'],
                                env=dict(self.env, PATH=str(binary)), capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'workBenches v1.5.0\n')
        self.assertFalse((self.root / 'logs').exists())

    def test_freeze_and_annotated_tag_identify_clean_candidate(self):
        manifest = self.freeze()
        self.assertEqual(manifest['version'], '1.5.0')
        self.assertEqual(manifest['repositories'][0]['commit'], self.pin)
        self.git(self.root, 'tag', '-a', 'v1.5.0', '-m', 'fixture release')
        release.validate(self.root, 'v1.5.0')
        result = subprocess.run(['/bin/bash', '-c', 'source "$1/bootstrap.sh"; workbenches_release_checkout',
                                 'release-detection', str(self.root)], env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        with self.assertRaisesRegex(ValueError, 'tag must match'):
            release.validate(self.root, 'v1.5.1')

    def test_lightweight_tags_and_dirty_candidates_are_rejected(self):
        self.freeze()
        self.git(self.root, 'tag', 'v1.5.0')
        with self.assertRaisesRegex(ValueError, 'annotated'):
            release.validate(self.root, 'v1.5.0')
        (self.root / 'local-work').write_text('keep')
        with self.assertRaisesRegex(ValueError, 'local changes'):
            release.validate(self.root)

    def test_prepare_clones_frozen_commit_even_when_remote_moves(self):
        self.freeze()
        shutil.rmtree(self.checkout)
        (self.remote / 'source').write_text('newer')
        self.commit(self.remote)
        release.prepare(self.root, self.selection)
        self.assertEqual(self.git(self.checkout, 'rev-parse', 'HEAD'), self.pin)
        self.assertEqual((self.checkout / 'source').read_text(), 'frozen')

    def test_existing_local_work_or_revision_drift_is_preserved(self):
        self.freeze()
        (self.checkout / 'source').write_text('my edit')
        with self.assertRaisesRegex(ValueError, 'local changes'):
            release.prepare(self.root, self.selection)
        self.assertEqual((self.checkout / 'source').read_text(), 'my edit')
        self.commit(self.checkout)
        changed = self.git(self.checkout, 'rev-parse', 'HEAD')
        with self.assertRaisesRegex(ValueError, 'frozen commit'):
            release.validate(self.root)
        with self.assertRaisesRegex(ValueError, 'frozen commit'):
            release.prepare(self.root, self.selection)
        self.assertEqual(self.git(self.checkout, 'rev-parse', 'HEAD'), changed)

    def test_frozen_tui_install_and_setup_do_not_fetch_or_pull(self):
        shutil.copytree(ROOT / 'scripts', self.root / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
        command = '''source "$1/scripts/interactive-setup.sh"
init_components --loading
bench_items=(fixtureBench)
component_description[bench_fixtureBench]=Fixture
component_checked[bench_fixtureBench]=true
component_action[bench_fixtureBench]=install
export WORKBENCHES_FROZEN=1
git() { printf '%s\\n' "$*" >> "$GIT_CALL_TRACE"; return 99; }
jq() { if [[ "$*" == *.url* ]]; then printf '%s\\n' fixture-url; else printf '%s\\n' devBenches/fixtureBench; fi; }
clear() { :; }
show_pending_authentication() { :; }
refresh_component_statuses() { component_status[bench_fixtureBench]=installed; }
for state in 'needs setup' 'not installed'; do
    component_status[bench_fixtureBench]="$state"
    process_selections || exit "$?"
done
'''
        trace = self.directory / 'git-calls'
        result = subprocess.run(['/bin/bash', '-c', command, 'frozen-tui', str(self.root)],
                                env=dict(self.env, GIT_CALL_TRACE=str(trace)),
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(trace.exists(), trace.read_text() if trace.exists() else '')
        self.assertEqual(self.git(self.checkout, 'rev-parse', 'HEAD'), self.pin)

    def test_uncommitted_submodule_pin_cannot_be_frozen(self):
        (self.root / '.gitmodules').write_text(f'[submodule "{self.path}"]\npath = {self.path}\nurl = {self.remote.as_uri()}\n')
        self.git(self.root, 'update-index', '--add', '--cacheinfo', f'160000,{self.pin},{self.path}')
        self.commit(self.root)
        (self.checkout / 'source').write_text('changed')
        self.commit(self.checkout)
        with self.assertRaisesRegex(ValueError, 'assembly gitlink'):
            release.freeze(self.root)

    def test_frozen_removal_preserves_dirty_submodule_worktree(self):
        (self.root / '.gitmodules').write_text(f'[submodule "{self.path}"]\npath = {self.path}\nurl = {self.remote.as_uri()}\n')
        self.git(self.root, 'update-index', '--add', '--cacheinfo', f'160000,{self.pin},{self.path}')
        self.commit(self.root)
        self.freeze()
        note = self.checkout / 'my-local-work'
        note.write_text('preserve this')
        self.selection.write_text(json.dumps({'schemaVersion': 1, 'components': [
            {'key': 'bench_fixtureBench', 'action': 'uninstall'}]}))
        release.prepare(self.root, self.selection)
        self.assertEqual(note.read_text(), 'preserve this')
        with self.assertRaisesRegex(ValueError, 'local changes'):
            release.validate(self.root)

    def test_missing_benches_are_pinned_and_stale_lock_is_rejected(self):
        shutil.rmtree(self.checkout)
        manifest = self.freeze()
        self.assertEqual(manifest['repositories'][0]['commit'], self.pin)
        (self.root / 'VERSION').write_text('1.5.1\n')
        with self.assertRaisesRegex(ValueError, 'does not match VERSION'):
            release.validate(self.root)

    def test_assembly_gitlink_cannot_drift_from_frozen_revision(self):
        (self.root / '.gitmodules').write_text(f'[submodule "{self.path}"]\npath = {self.path}\nurl = {self.remote.as_uri()}\n')
        self.git(self.root, 'update-index', '--add', '--cacheinfo', f'160000,{self.pin},{self.path}')
        self.commit(self.root)
        self.freeze()
        (self.checkout / 'source').write_text('newer')
        self.commit(self.checkout)
        newer = self.git(self.checkout, 'rev-parse', 'HEAD')
        self.git(self.root, 'update-index', '--cacheinfo', f'160000,{newer},{self.path}')
        self.commit(self.root)
        with self.assertRaisesRegex(ValueError, 'differs from assembly gitlink'):
            release.validate(self.root)


if __name__ == '__main__':
    unittest.main()
