#!/usr/bin/env python3
"""Prepare a stopped disposable Arch QA image; never register a GitHub runner."""
import argparse
import base64
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
IMAGE_SHA256 = '08754e28d91b1680086c6211ef4df13559e766fff7cdb4006489b14b5d281f08'


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): value.update(chunk)
    return value.hexdigest()


def cloud_config(public_key, reset_id, wrapper):
    encoded = base64.b64encode(wrapper).decode()
    config = dict(enabled=True, disposable=True, resetId=reset_id, adapters={
        'arch-native': dict(argv=['/opt/workbenches/qa-native'], sha256=hashlib.sha256(wrapper).hexdigest())})
    files = [
        dict(path='/etc/workbenches/disposable-qa-id', content=reset_id + '\n', permissions='0644'),
        dict(path='/etc/workbenches/native-qa.json', content=json.dumps(dict(kind='arch', cleanPath='/usr/local/sbin:/usr/local/bin:/usr/bin')), permissions='0644'),
        dict(path='/etc/workbenches/release-qa.json', content=json.dumps(config), permissions='0644'),
        dict(path='/opt/workbenches/qa-native', content=encoded, encoding='b64', permissions='0755'),
        dict(path='/var/lib/cloud/scripts/per-boot/workbenches-qa-ready', permissions='0755', content=
             '#!/bin/sh\nif test -f /var/lib/workbenches-qa-reboot; then\n'
             '  rm -- /var/lib/workbenches-qa-reboot\n'
             '  if systemctl start docker && docker info >/dev/null 2>&1; then\n'
             '    echo WB_QA_READY_AFTER_REBOOT\n'
             '  else echo WB_QA_BOOTSTRAP_FAILED; exit 1; fi\nfi\n'),
    ]
    for file in files: file['owner'] = 'root:root'
    data = dict(hostname='workbenches-arch-qa', disable_root=True, ssh_pwauth=False,
        users=[dict(name='qa', lock_passwd=True, shell='/bin/bash', groups=['docker'],
                    sudo=['ALL=(ALL) NOPASSWD:ALL'], ssh_authorized_keys=[public_key])],
        groups=['docker'], package_update=True, package_upgrade=True,
        package_reboot_if_required=False,
        packages=['docker', 'docker-compose', 'docker-buildx', 'git', 'python', 'nodejs', 'npm', 'zsh', 'sudo', 'openssh', 'curl', 'jq'],
        # A rolling Arch upgrade can replace the running kernel's modules.
        # The per-boot final-stage script runs after network-online. Starting
        # Docker in bootcmd would deadlock against that target's ordering.
        write_files=files, runcmd=[
            ['sh', '-c', 'printf "WB_QA_HOST_KEY="; cat /etc/ssh/ssh_host_ed25519_key.pub'],
            ['systemctl', 'enable', 'docker'], ['touch', '/var/lib/workbenches-qa-reboot']],
        power_state=dict(mode='reboot', delay='now', condition=['test', '-f', '/var/lib/workbenches-qa-reboot']),
        final_message='WB_QA_CLOUD_INIT_FINISHED')
    return '#cloud-config\n' + json.dumps(data, indent=2) + '\n'


class PrivateHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_): pass


def power_off(process, ssh):
    result = subprocess.run([*ssh, 'sudo systemctl poweroff'], capture_output=True, timeout=30)
    # SSH may lose its channel before receiving exit status during shutdown.
    # Accept that only if QEMU subsequently confirms the guest actually exited.
    if result.returncode not in (0, 255): raise ValueError('Guest shutdown request failed')
    process.wait(timeout=90)
    if process.returncode: raise ValueError('QA VM shutdown failed')


def prepare(image, state, memory=4096, cpus=2, timeout=1800):
    if digest(image) != IMAGE_SHA256: raise ValueError('Pinned Arch image checksum mismatch')
    state = state.absolute()
    if any(c in str(state) for c in (',', '\n')): raise ValueError('Unsafe VM state path')
    if not 1024 <= memory <= 32768 or not 1 <= cpus <= 16: raise ValueError('Invalid VM resource limits')
    if state.exists(): raise ValueError('State directory must be new; existing QA disks are never overwritten')
    if not os.access('/dev/kvm', os.R_OK | os.W_OK): raise ValueError('KVM access required')
    os.umask(0o077)
    state.mkdir(parents=True, mode=0o700)
    seed = state / 'seed'; seed.mkdir(mode=0o700)
    reset_id = str(uuid.uuid4())
    key = state / 'ssh-key'
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'disposable-arch-qa', '-f', str(key)], check=True)
    wrapper = (ROOT / 'qa/release/native-adapter').read_bytes()
    (seed / 'user-data').write_text(cloud_config(key.with_suffix('.pub').read_text().strip(), reset_id, wrapper))
    (seed / 'meta-data').write_text(json.dumps({'instance-id': reset_id, 'local-hostname': 'workbenches-arch-qa'}))
    (seed / 'vendor-data').write_text('#cloud-config\n{}\n')
    disk = state / 'golden.qcow2'
    subprocess.run(['cp', '--reflink=auto', str(image), str(disk)], check=True)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(PrivateHandler, directory=str(seed)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0)); port = reservation.getsockname()[1]
    serial = state / 'serial.log'
    ssh = ['ssh', '-F', '/dev/null', '-i', str(key), '-p', str(port), '-o', 'BatchMode=yes',
           '-o', 'IdentitiesOnly=yes', '-o', 'IdentityAgent=none', '-o', 'StrictHostKeyChecking=yes',
           '-o', 'GlobalKnownHostsFile=/dev/null',
           '-o', 'UserKnownHostsFile=' + str(state / 'known_hosts'), '-o', 'ConnectTimeout=5', 'qa@127.0.0.1']
    command = ['qemu-system-x86_64', '-name', 'workbenches-arch-qa-' + reset_id,
        '-accel', 'kvm', '-cpu', 'host', '-m', str(memory), '-smp', str(cpus), '-display', 'none', '-monitor', 'none',
        '-serial', 'file:' + str(serial), '-S',
        '-qmp', 'unix:' + str(state / 'qmp.sock') + ',server=on,wait=off',
        '-drive', 'file=' + str(disk) + ',format=qcow2,if=virtio,id=qa-disk',
        '-netdev', f'user,id=qa,hostfwd=tcp:127.0.0.1:{port}-:22', '-device', 'virtio-net-pci,netdev=qa',
        '-smbios', f'type=1,serial=ds=nocloud;s=http://10.0.2.2:{server.server_port}/']
    process = None
    try:
        with (state / 'qemu.log').open('wb') as log:
            process = subprocess.Popen(command, stdout=log, stderr=log, start_new_session=True)
        # Resize only the new private QCOW disk before the guest sees it. QMP
        # avoids requiring or installing qemu-img on the daily workstation.
        for attempt in range(50):
            try:
                control = socket.socket(socket.AF_UNIX); control.settimeout(5)
                control.connect(str(state / 'qmp.sock')); break
            except OSError:
                control.close()
                if process.poll() is not None or attempt == 49: raise
                time.sleep(.1)
        with control, control.makefile('rwb') as stream:
            json.loads(stream.readline())
            for request in [dict(execute='qmp_capabilities'),
                            dict(execute='block_resize', arguments=dict(device='qa-disk', size=80 * 1024**3)),
                            dict(execute='cont')]:
                stream.write(json.dumps(request).encode() + b'\n'); stream.flush()
                while True:
                    response = json.loads(stream.readline())
                    if 'error' in response: raise ValueError('Private VM disk initialization failed')
                    if 'return' in response: break
        deadline = time.monotonic() + timeout
        pinned = False
        while time.monotonic() < deadline:
            if process.poll() is not None: raise ValueError('QA VM exited before preparation completed; see private qemu.log')
            output = serial.read_text(errors='replace') if serial.exists() else ''
            if not pinned:
                match = re.search(r'WB_QA_HOST_KEY=(ssh-ed25519 [A-Za-z0-9+/=]+)', output)
                if match:
                    # Pin from our VM's private serial channel, never an unverified network scan.
                    (state / 'known_hosts').write_text(f'[127.0.0.1]:{port} {match[1]}\n')
                    pinned = True
            if 'WB_QA_BOOTSTRAP_FAILED' in output: raise ValueError('QA Docker startup failed after guest reboot')
            if pinned and 'WB_QA_READY_AFTER_REBOOT' in output:
                with (state / 'validation.log').open('wb') as log:
                    result = subprocess.run([*ssh, 'sudo cloud-init status --wait --long && sudo docker info >/dev/null && docker buildx version && python --version && git --version && node --version && npm --version && zsh --version && test "$(df --output=size -k / | tail -1)" -gt 60000000'], stdout=log, stderr=log, timeout=120)
                if result.returncode: raise ValueError('Guest configuration failed; see private validation.log')
                power_off(process, ssh)
                manifest = dict(schemaVersion=1, state='prepared-not-registered', imageSha256=IMAGE_SHA256,
                    resetId=reset_id, disk=str(disk), memoryMiB=memory, cpus=cpus,
                    registeredRunner=False, cleanup='vm-stopped', createdAt=int(time.time()))
                (state / 'prepared.json').write_text(json.dumps(manifest, indent=2) + '\n')
                print(json.dumps(manifest, indent=2)); return manifest
            time.sleep(2)
        raise ValueError('QA image preparation timed out; see private serial.log')
    finally:
        server.shutdown(); server.server_close()
        if process is not None and process.poll() is None:
            process.terminate()
            try: process.wait(timeout=15)
            except subprocess.TimeoutExpired: process.kill(); process.wait()


if __name__ == '__main__':
    def terminate(*_): raise SystemExit(143)
    signal.signal(signal.SIGTERM, terminate)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--memory', type=int, default=4096)
    parser.add_argument('--cpus', type=int, default=2)
    args = parser.parse_args()
    prepare(args.image.resolve(), args.state, args.memory, args.cpus)
