#!/usr/bin/env python3
"""Private Raven broker QA VM from a prepared Arch disk; no runner registration.

This persistent provisioning clone is not a per-job reset release worker. It has
no host directory mounts, forwarded agent, host Docker socket or default gh auth.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')
    path.chmod(0o600)


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def ssh(state, manifest):
    return ['ssh', '-F', '/dev/null', '-i', str(state / 'ssh-key'), '-p', str(manifest['sshPort']),
            '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'IdentityAgent=none',
            '-o', 'StrictHostKeyChecking=yes', '-o', 'GlobalKnownHostsFile=/dev/null',
            '-o', 'UserKnownHostsFile=' + str(state / 'known_hosts'), '-o', 'ConnectTimeout=5', 'qa@127.0.0.1']


def running(manifest):
    try:
        raw = Path('/proc/' + str(manifest['pid']) + '/cmdline').read_bytes()
        return manifest['vmName'].encode() in raw and b'qemu-system' in raw
    except FileNotFoundError:
        return False


def provisioning_only(state, manifest):
    # The golden marker must not certify a persistent clone as a reset worker.
    command = "sudo sh -c 'if test -e /etc/workbenches/disposable-qa-id; then mv /etc/workbenches/disposable-qa-id /etc/workbenches/provisioning-golden-id; fi; install -m 644 /dev/null /etc/workbenches/provisioning-only'"
    subprocess.run([*ssh(state, manifest), command], check=True, timeout=30)


def launch(state, manifest):
    disk = state / 'qa.qcow2'
    command = ['qemu-system-x86_64', '-name', manifest['vmName'], '-accel', 'kvm', '-cpu', 'host',
               '-m', '4096', '-smp', '2', '-display', 'none', '-monitor', 'none',
               '-serial', 'file:' + str(state / 'serial.log'),
               '-drive', 'file=' + str(disk) + ',format=qcow2,if=virtio',
               '-netdev', 'user,id=qa,hostfwd=tcp:127.0.0.1:' + str(manifest['sshPort']) + '-:22',
               '-device', 'virtio-net-pci,netdev=qa']
    with (state / 'qemu.log').open('wb') as output:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=output, stderr=output, start_new_session=True)
    manifest['pid'] = process.pid
    write(state / 'vm.json', manifest)
    return process


def start(golden, state):
    if state.exists():
        raise ValueError('New private state directory required; no overwrite')
    if any(c in str(state) for c in ',\n'):
        raise ValueError('Unsafe VM path')
    prepared = json.loads((golden / 'prepared.json').read_text())
    if prepared['state'] != 'prepared-not-registered' or prepared['cleanup'] != 'vm-stopped':
        raise ValueError('Validated stopped golden image required')
    if not os.access('/dev/kvm', os.R_OK | os.W_OK):
        raise ValueError('KVM access required')
    state.mkdir(mode=0o700, parents=True)
    disk = state / 'qa.qcow2'
    subprocess.run(['cp', '--reflink=auto', str(golden / 'golden.qcow2'), str(disk)], check=True)
    subprocess.run(['cp', str(golden / 'ssh-key'), str(state / 'ssh-key')], check=True)
    (state / 'ssh-key').chmod(0o600)
    match = re.search(r'(ssh-ed25519 [A-Za-z0-9+/=]+)', (golden / 'known_hosts').read_text())
    if not match:
        raise ValueError('Trusted golden host key missing')
    manifest = dict(state='starting', vmName='wb-raven-broker-qa-' + uuid.uuid4().hex,
                    sshPort=port(), registeredRunner=False, liveConfigured=False,
                    kind='persistent-provisioning-clone', goldenResetId=prepared['resetId'])
    (state / 'known_hosts').write_text('[127.0.0.1]:' + str(manifest['sshPort']) + ' ' + match[1] + '\n')
    process = launch(state, manifest)
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise ValueError('VM exited; inspect private logs')
        result = subprocess.run([*ssh(state, manifest), 'true'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            provisioning_only(state, manifest)
            manifest['state'] = 'ready-not-configured'
            write(state / 'vm.json', manifest)
            return manifest
        time.sleep(2)
    # Leave a recorded instance available for explicit stop / private diagnosis.
    raise ValueError('SSH readiness timed out; stop the recorded instance before retrying')


def stage(state, manifest):
    if subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain']).strip():
        raise ValueError('Commit source before staging')
    commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    target = '/home/qa/broker-source-' + commit
    archive = state / 'source.tar'
    with archive.open('wb') as output:
        subprocess.run(['git', '-C', str(ROOT), 'archive', commit], stdout=output, check=True)
    try:
        with archive.open('rb') as source:
            subprocess.run([*ssh(state, manifest), 'mkdir -m 700 ' + shlex.quote(target) + ' && tar -xf - -C ' + shlex.quote(target)], stdin=source, check=True, timeout=120)
    finally:
        archive.unlink(missing_ok=True)
    manifest.pop('smoke', None)
    manifest.pop('smokeCommit', None)
    manifest.update(sourceCommit=commit, sourcePath=target)
    write(state / 'vm.json', manifest)
    return manifest


def smoke(state, manifest):
    source = manifest['sourcePath']
    command = ('cd ' + shlex.quote(source) + ' && sudo systemctl start docker && '
               'docker compose -p wb-raven-broker-qa -f devcontainer.test/docker-compose.yml '
               '--profile credential-sync run --build --rm --no-deps credential-sync')
    with (state / 'smoke.log').open('wb') as output:
        result = subprocess.run([*ssh(state, manifest), command], stdout=output, stderr=output, timeout=1800)
    manifest.update(smoke='passed' if result.returncode == 0 else 'failed', smokeCommit=manifest['sourceCommit'], liveConfigured=False)
    write(state / 'vm.json', manifest)
    if result.returncode:
        raise ValueError('Guest smoke failed; inspect private smoke.log')
    return manifest


def stop(state, manifest):
    if running(manifest):
        subprocess.run([*ssh(state, manifest), 'sudo systemctl poweroff'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        deadline = time.monotonic() + 90
        while running(manifest) and time.monotonic() < deadline:
            time.sleep(1)
        if running(manifest):
            raise ValueError('VM still running; no unrelated process was killed')
    manifest['state'] = 'stopped'
    write(state / 'vm.json', manifest)
    return manifest


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['start', 'resume', 'stage', 'smoke', 'status', 'stop'])
    parser.add_argument('--state', required=True, type=Path)
    parser.add_argument('--golden', type=Path)
    args = parser.parse_args()
    state = args.state.expanduser().absolute()
    if any(p.is_symlink() for p in [state, *state.parents]):
        raise ValueError('No symlink state paths')
    if args.action == 'start':
        if args.golden is None:
            raise ValueError('--golden required')
        result = start(args.golden.expanduser().resolve(), state)
    else:
        result = json.loads((state / 'vm.json').read_text())
        if args.action in ('stage', 'smoke') and not running(result):
            raise ValueError('VM is not running')
        if args.action == 'resume':
            if running(result) or result['state'] != 'stopped':
                raise ValueError('Recorded stopped VM required')
            result['state'] = 'starting'
            process = launch(state, result)
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                if process.poll() is not None: raise ValueError('VM exited')
                if subprocess.run([*ssh(state, result), 'true'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                    provisioning_only(state, result)
                    result['state'] = 'ready-not-configured'
                    write(state / 'vm.json', result)
                    break
                time.sleep(2)
            else: raise ValueError('VM readiness timed out')
        elif args.action == 'stage': result = stage(state, result)
        elif args.action == 'smoke': result = smoke(state, result)
        elif args.action == 'stop': result = stop(state, result)
        else: result = dict(result, running=running(result))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
