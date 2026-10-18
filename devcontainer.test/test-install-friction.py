#!/usr/bin/env python3
"""Source compatibility and first-start lifecycle regressions, no real credentials."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('shared', ROOT / 'scripts/shared-images.py')
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)

class ImageTests(unittest.TestCase):
    def test_publisher_loads_the_same_shared_image_contract(self):
        spec=importlib.util.spec_from_file_location('publisher',ROOT/'scripts/publish-shared-images.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        self.assertEqual(module.shared.release_tag(),shared.release_tag())


    def test_publisher_retries_reuse_matching_public_images_without_building(self):
        spec=importlib.util.spec_from_file_location('publisher',ROOT/'scripts/publish-shared-images.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        row={'Id':'base-id','Os':'linux','Architecture':'amd64','Config':{'Labels':{shared.LABEL:shared.fingerprint('base')}}}
        with patch.object(module.shared,'inspect',return_value=row), patch.object(module.subprocess,'run',return_value=subprocess.CompletedProcess([],0)) as command:
            module.prepare_image('base','linux/amd64')
        self.assertFalse(any(call.args[0][0]=='bash' for call in command.call_args_list))
        self.assertTrue(any(call.args[0][:2]==['docker','tag'] for call in command.call_args_list))

    def test_source_hash_is_path_independent_and_changes_with_helpers(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = [Path(directory)/name for name in ('one','two')]
            for root in roots:
                for path in ('base-image/Dockerfile','base-image/helper.sh','devBenches/base-image/Dockerfile','scripts/lib/image-names.sh'):
                    file=root/path;file.parent.mkdir(parents=True,exist_ok=True);file.write_text(path)
            self.assertEqual(shared.fingerprint('dev',roots[0]),shared.fingerprint('dev',roots[1]))
            before=shared.fingerprint('dev',roots[0])
            (roots[0]/'base-image/helper.sh').write_text('changed')
            self.assertNotEqual(before,shared.fingerprint('dev',roots[0]))
            cache_before=shared.fingerprint('base',roots[1])
            (roots[1]/'base-image/__pycache__').mkdir()
            (roots[1]/'base-image/__pycache__/unrelated.pyc').write_text('ignored')
            self.assertEqual(cache_before,shared.fingerprint('base',roots[1]))

    def test_publisher_preserves_the_exported_digest_without_a_second_push(self):
        spec=importlib.util.spec_from_file_location('publisher',ROOT/'scripts/publish-shared-images.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        ref=shared.REGISTRIES['dev']+'@sha256:'+'d'*64
        with patch.object(module.shared,'inspect',return_value={'RepoDigests':[ref]}), patch.object(module,'run') as command:
            self.assertEqual(module.published_digest('dev','dev-tag'),ref)
            command.assert_not_called()

    def test_publisher_exports_directly_and_rejects_a_changed_parent(self):
        spec=importlib.util.spec_from_file_location('publisher',ROOT/'scripts/publish-shared-images.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        base={'RepoDigests':[shared.REGISTRIES['base']+'@sha256:'+'b'*64]}
        wrong={'Os':'linux','Architecture':'amd64','Config':{'Labels':{shared.LABEL:shared.fingerprint('dev'),'io.workbenches.parent':'wrong'}}}
        with patch.object(module.shared,'inspect',side_effect=[base,wrong]), patch.object(module.subprocess,'run',return_value=subprocess.CompletedProcess([],0)) as command:
            with self.assertRaisesRegex(RuntimeError,'parent validation'):
                module.build_dev_image('release-tag','expected','linux/amd64')
        calls=[call.args[0] for call in command.call_args_list]
        export=next(argv for argv in calls if argv[:3]==['docker','buildx','build'])
        self.assertIn('BASE_IMAGE='+base['RepoDigests'][0],export)
        self.assertIn('type=registry,name=release-tag,compression=gzip,compression-level=1',export)
        self.assertTrue(any(argv[:3]==['docker','buildx','rm'] for argv in calls))
        self.assertFalse(any(argv[:2]==['docker','tag'] for argv in calls))

    def exercise(self, manifest=None, local=False, force=False, pull_failure=False, bad_label=False):
        calls=[]
        source=shared.fingerprint('base')
        ref=shared.REGISTRIES['base']+'@sha256:'+'a'*64
        row={'Id':'sha256:config','Os':'linux','Architecture':'amd64','Config':{'Labels':{shared.LABEL:source}}}
        def command(argv, **kwargs):
            calls.append((argv,kwargs))
            if argv[1]=='context': return subprocess.CompletedProcess(argv,0,'unix:///test/docker.sock','')
            if argv[1]=='info': return subprocess.CompletedProcess(argv,0,'linux/x86_64','')
            if argv[1:3]==['image','inspect']:
                payload=row if (argv[3]==ref or local) else None
                if bad_label and argv[3]==ref: payload=dict(row,Config={'Labels':{shared.LABEL:'wrong'}})
                return subprocess.CompletedProcess(argv,0 if payload else 1,json.dumps([payload]) if payload else '', '')
            return subprocess.CompletedProcess(argv,1 if pull_failure and argv[1]=='pull' else 0)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'manifest.json'
            default={'schemaVersion':1,'images':{'base':{'linux/amd64':{'sourceHash':source,'image':ref}}}}
            path.write_text(json.dumps(manifest or default))
            with patch.dict(os.environ, {'WORKBENCHES_IMAGE_MANIFEST':str(path),'WORKBENCHES_BUILD_LOCAL':'1' if force else '0'}), patch.object(shared.subprocess,'run',side_effect=command):
                code=shared.ensure('base')
        return code,calls

    def test_anonymous_pinned_pull_tags_only_verified_image(self):
        code,calls=self.exercise();self.assertEqual(code,0)
        pull=[x for x in calls if x[0][1]=='pull'][0]
        self.assertIn('@sha256:',pull[0][-1]);self.assertIn('DOCKER_CONFIG',pull[1]['env'])
        self.assertTrue(any(x[0][1]=='tag' for x in calls))

    def test_matching_cache_needs_no_network_and_explicit_local_build_overrides_it(self):
        code,calls=self.exercise(local=True);self.assertEqual(code,0)
        self.assertFalse(any(x[0][1]=='pull' for x in calls))
        self.assertEqual(self.exercise(local=True,force=True)[0],1)

    def test_wrong_source_registry_architecture_and_metadata_fall_back_without_retagging(self):
        for manifest in (
            {'schemaVersion':1,'images':{'base':{'linux/amd64':{'sourceHash':'wrong','image':'bad'}}}},
            {'schemaVersion':1,'images':{'base':{'linux/amd64':{'sourceHash':shared.fingerprint('base'),'image':'evil.example/image@sha256:'+'a'*64}}}},
            {'schemaVersion':1,'images':{'base':{'linux/arm64':{}}}},
        ):
            code,calls=self.exercise(manifest);self.assertEqual(code,1)
            self.assertFalse(any(x[0][1]=='tag' for x in calls))
        for kwargs in ({'pull_failure':True},{'bad_label':True}):
            code,calls=self.exercise(**kwargs);self.assertEqual(code,1)
            self.assertFalse(any(x[0][1]=='tag' for x in calls))

    def test_developer_cache_requires_the_exact_parent(self):
        row={'Os':'linux','Architecture':'amd64','Config':{'Labels':{shared.LABEL:'recipe','io.workbenches.parent':'old'}}}
        self.assertFalse(shared.compatible(row,'dev','recipe','linux/amd64','new'))
        self.assertTrue(shared.compatible(row,'dev','recipe','linux/amd64','old'))

class BenchTests(unittest.TestCase):
    def exercise(self, existing=False, raced=False, fail_check=False, builder=False, fail_build=False):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);repo=root/'repo';setup=repo/'devBenches/pyBench/setup.sh';setup.parent.mkdir(parents=True)
            compose=setup.parent/'.devcontainer/docker-compose.yml';compose.parent.mkdir();compose.write_text('services: {}')
            setup.write_text('#!/bin/bash\ndocker-compose -f .devcontainer/docker-compose.yml up -d\n')
            if builder:
                build_dir=setup.parent/'scripts';build_dir.mkdir()
                (build_dir/'build-layer2.sh').write_text('#!/bin/bash\necho build-layer2 >> "$BENCH_LOG"\nexit "${FAIL_BUILD:-0}"\n')
            scripts=repo/'scripts';scripts.mkdir()
            (scripts/'wave-container-shell.sh').write_text('''#!/bin/bash
if [[ "$*" == *--prepare-compose* ]]; then
  while [[ "$1" != --prepare-compose ]]; do shift; done
  echo 'services: {py-bench: {init: true}}' > "$2"
else
  echo check >> "$BENCH_LOG"
  exit "${FAIL_CHECK:-0}"
fi
''')
            binary=root/'bin';binary.mkdir();docker=binary/'docker'
            docker.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:]
if args[:2]==['container','inspect']:
 p=Path(os.environ['COUNT']);count=int(p.read_text()) if p.exists() else 0;p.write_text(str(count+1))
 if os.environ['EXISTING']=='1' or (os.environ['RACED']=='1' and count>0):
  print(json.dumps([{'Id':'existing','State':{'Running':True}}]));sys.exit(0)
 sys.exit(1)
if 'config' in args: print(json.dumps({'services':{'py-bench':{'container_name':'py-bench'}}}));sys.exit(0)
if 'up' in args:
 with Path(os.environ['BENCH_LOG']).open('a') as stream: stream.write(' '.join(args)+'\\n')
sys.exit(0)
''');docker.chmod(0o700)
            spec=importlib.util.spec_from_file_location('bench',ROOT/'scripts/setup-bench-runtime.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            log=root/'actions';env=dict(os.environ,HOME=str(root/'home'),PATH=str(binary)+os.pathsep+os.environ['PATH'],BENCH_LOG=str(log),COUNT=str(root/'count'),EXISTING=str(int(existing)),RACED=str(int(raced)),FAIL_CHECK=str(int(fail_check)),FAIL_BUILD='42' if fail_build else '0')
            with patch.dict(os.environ,env),patch.object(module,'ROOT',repo),patch.object(module.sys,'argv',['setup','--bench','pyBench','--setup',str(setup)]): code=module.main()
            return code,log.read_text() if log.exists() else ''

    def test_first_creation_includes_wave_override_and_requires_launch_check(self):
        code,log=self.exercise();self.assertEqual(code,0)
        self.assertIn('py-bench.override.yml up -d',log);self.assertIn('check',log)
        self.assertEqual(self.exercise(fail_check=True)[0],1)

    def test_existing_and_racing_live_containers_are_preserved(self):
        for kwargs in ({'existing':True},{'raced':True}):
            code,log=self.exercise(**kwargs);self.assertEqual(code,1);self.assertEqual(log,'')

    def test_declared_image_builder_refreshes_before_startup(self):
        code,log=self.exercise(builder=True)
        self.assertEqual(code,0)
        self.assertLess(log.index('build-layer2'),log.index('up -d'))
        self.assertLess(log.index('up -d'),log.index('check'))
        code,log=self.exercise(builder=True,fail_build=True)
        self.assertEqual(code,42);self.assertEqual(log,'build-layer2\n')
        code,log=self.exercise(builder=True,existing=True)
        self.assertEqual(code,1);self.assertEqual(log,'')

if __name__=='__main__': unittest.main()
