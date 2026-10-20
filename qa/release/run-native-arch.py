#!/usr/bin/env python3
"""One-use native Arch acceptance VM with fresh reset ID and both SSH identities.

Never registers a runner. Exact git bundles and strict pinned SSH are the only
host/guest transfer paths; no host directories, agent or Docker sockets mount.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time
import uuid

SPEC = importlib.util.spec_from_file_location('private_vm', Path(__file__).with_name('raven-qa-vm.py'))
VM = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(VM)


def stage(state, manifest, repo, name):
    commit = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    bundle = state / (name + '.bundle')
    subprocess.run(['git', '-C', str(repo), 'bundle', 'create', str(bundle), 'HEAD'], check=True)
    try:
        with bundle.open('rb') as stream:
            remote = ('cat > /home/qa/' + name + '.bundle && git clone --no-checkout /home/qa/' + name +
                      '.bundle /home/qa/' + name + ' && git -C /home/qa/' + name + ' checkout --detach ' + commit)
            subprocess.run([*VM.ssh(state, manifest), remote], stdin=stream, check=True, timeout=180)
    finally:
        bundle.unlink(missing_ok=True)
    manifest[name + 'Commit'] = commit
    VM.write(state / 'vm.json', manifest)


def fresh_identity(state, manifest):
    key = state / 'job-ssh-key'
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
    job = {'resetId': manifest['resetId'], 'operatorKey': key.with_suffix('.pub').read_text().strip()}
    # The original trusted channel delivers the new identity; no network scan.
    code = '''import json,subprocess,sys
from pathlib import Path
job=json.load(sys.stdin)
config=Path('/etc/workbenches/release-qa.json')
value=json.loads(config.read_text());value['resetId']=job['resetId']
config.write_text(json.dumps(value));config.chmod(0o644)
Path('/etc/workbenches/disposable-qa-id').write_text(job['resetId']+'\\n')
authorized=Path('/home/qa/.ssh/authorized_keys')
authorized.write_text(job['operatorKey']+'\\n');authorized.chmod(0o600)
for suffix in ('','.pub'):Path('/etc/ssh/ssh_host_ed25519_key'+suffix).unlink()
subprocess.run(['ssh-keygen','-q','-t','ed25519','-N','','-f','/etc/ssh/ssh_host_ed25519_key'],check=True)
print(Path('/etc/ssh/ssh_host_ed25519_key.pub').read_text().strip(),flush=True)
subprocess.run(['systemctl','reload','sshd'],check=True)
'''
    result = subprocess.run([*VM.ssh(state, manifest), 'sudo python3 -c ' + shlex.quote(code)],
                            input=json.dumps(job).encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    if result.returncode:
        raise ValueError('Fresh guest identity initialization failed')
    match = re.fullmatch(rb'(ssh-ed25519 [A-Za-z0-9+/=]+)(?: [^\n]*)?\n?', result.stdout)
    if not match:
        raise ValueError('Fresh guest host key missing')
    os.replace(key, state / 'ssh-key')
    (state / 'known_hosts').write_text('[127.0.0.1]:' + str(manifest['sshPort']) + ' ' + match[1].decode() + '\n')
    subprocess.run([*VM.ssh(state, manifest), 'true'], check=True, timeout=15)


def run(golden, state, candidate, automation):
    if state.exists() or any(p.is_symlink() for p in [state, *state.parents]) or any(c in str(state) for c in ',\n'):
        raise ValueError('New private nonsymlink state path required')
    prepared = json.loads((golden / 'prepared.json').read_text())
    if prepared['state'] != 'prepared-not-registered' or prepared['cleanup'] != 'vm-stopped':
        raise ValueError('Validated stopped golden image required')
    if not os.access('/dev/kvm', os.R_OK | os.W_OK):
        raise ValueError('KVM access required')
    state.mkdir(mode=0o700, parents=True)
    for source, target in [('golden.qcow2', 'qa.qcow2'), ('ssh-key', 'ssh-key')]:
        subprocess.run(['cp', '--reflink=auto', str(golden / source), str(state / target)], check=True)
    port = VM.port()
    match = re.search(r'(ssh-ed25519 [A-Za-z0-9+/=]+)', (golden / 'known_hosts').read_text())
    if not match: raise ValueError('Trusted bootstrap host key missing')
    (state / 'known_hosts').write_text(f'[127.0.0.1]:{port} {match[1]}\n')
    reset_id = str(uuid.uuid4())
    manifest = dict(state='starting', vmName='wb-arch-job-' + reset_id, sshPort=port,
                    resetId=reset_id, kind='one-shot-native', registeredRunner=False)
    process = VM.launch(state, manifest)
    try:
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            if process.poll() is not None: raise ValueError('QA VM exited')
            if subprocess.run([*VM.ssh(state, manifest), 'true'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0: break
            time.sleep(2)
        else: raise ValueError('QA SSH readiness timed out')
        fresh_identity(state, manifest)
        stage(state, manifest, candidate, 'candidate')
        stage(state, manifest, automation, 'automation')
        manifest['state'] = 'native-adapter-running'; VM.write(state / 'vm.json', manifest)
        command = ('export WB_AUTOMATION_ROOT=/home/qa/automation WB_AUTOMATION_SHA=' + manifest['automationCommit'] +
                   '; python3 /home/qa/automation/scripts/release-validation.py run --root /home/qa/candidate '
                   '--suite arch-native --commit ' + manifest['candidateCommit'] +
                   ' --ref local-native-candidate --qa-config /etc/workbenches/release-qa.json --reports /home/qa/evidence')
        with (state / 'adapter.log').open('wb') as log:
            result = subprocess.run([*VM.ssh(state, manifest), command], stdout=log, stderr=log, timeout=8000)
        report = subprocess.run([*VM.ssh(state, manifest), 'cat /home/qa/evidence/arch-native.json'], capture_output=True, timeout=15)
        if report.returncode: raise ValueError('Native adapter report missing')
        value = json.loads(report.stdout)
        VM.write(state / 'arch-native.json', value)
        manifest.update(adapterExitCode=result.returncode, status=value['status'])
        print(json.dumps(value), flush=True)
        return 0 if value['status'] == 'passed' and result.returncode == 0 else 1
    finally:
        try:
            VM.stop(state, manifest)
        finally:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=15)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
            manifest['state'] = 'stopped'
            if manifest.get('status') == 'passed':
                (state / 'qa.qcow2').unlink(missing_ok=True)
                (state / 'ssh-key').unlink(missing_ok=True)
                manifest['disposal'] = 'disk-and-private-key-removed'
            else:
                manifest['disposal'] = 'private-failed-disk-retained'
            VM.write(state / 'vm.json', manifest)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('golden', 'state', 'candidate', 'automation'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    return run(args.golden.expanduser().resolve(), args.state.expanduser().absolute(),
               args.candidate.resolve(), args.automation.resolve())


if __name__ == '__main__':
    raise SystemExit(main())
