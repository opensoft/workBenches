"""Keyboard Devices inventory within personal/company Profiles."""
import os
from pathlib import Path
import shlex
import subprocess
import time

from company_sync import SyncError, atomic, endpoint, read_json
from device_keys import address, text
from device_trust import Devices, native, signout, start_agent, which
from profile_tui import choose, clean
from setup_prompts import prompt, propagate_cancel
import setup_profiles


def ask(label, default=''):
    return prompt(label + (f' [{default}]' if default else '') + ': ') or default


def confirm(label):
    return ask(label + ' [y/N]').lower() in ('yes', 'y')


def configure(root, company):
    previous = read_json(root / 'device-registry.json', {})
    url = endpoint(ask('Administrator-provided device-registry HTTPS URL', previous.get('url', '')))
    context = ask('Administrator-provided company context ID', previous.get('context', 'company:')) if company else 'personal'
    if company and not context.startswith('company:'): raise ValueError('Use the administrator-provided company: context ID.')
    name = text(ask('Device display name', previous.get('name', native(['hostname']))))
    target_input = ask('SSH hostname/IP (blank initially or - = outgoing only)', previous.get('address', ''))
    target = '' if target_input == '-' else address(target_input)
    port = int(ask('SSH port', str(previous.get('port', 22))))
    if not 1 <= port <= 65535: raise ValueError('SSH port must be 1–65535.')
    print('Registry: ' + url + '\nContext: ' + context)
    print('This registers your signed-in user and a dedicated local public key. Incoming access requires separate approval.')
    if confirm('Enable this registry and renew approved incoming access while signed in?'):
        # Stop extending any previous namespace before switching broker/context.
        signout(root)
        atomic(root / 'device-registry.json', dict(enabled=True, url=url, context=context, name=name, address=target, port=port))
        atomic(root / 'device-session-control.json', {'signedOut': False})
        return True
    return False


def launch(command):
    # New terminal, never put private credentials in argv or use shell evaluation.
    if which('wt.exe') and os.environ.get('WSL_DISTRO_NAME'):
        native(['bash', '-c', 'nohup "$@" </dev/null >/dev/null 2>&1 &', 'wb-device-terminal',
                'wt.exe', 'wsl.exe', '--distribution', os.environ['WSL_DISTRO_NAME'], '--exec', *command]); return True
    for terminal, options in [('x-terminal-emulator', ['-e']), ('kitty', ['--']), ('alacritty', ['-e']),
                              ('foot', ['--']), ('gnome-terminal', ['--']), ('konsole', ['-e'])]:
        if which(terminal):
            native(['bash', '-c', 'nohup "$@" </dev/null >/dev/null 2>&1 &', 'wb-device-terminal', terminal, *options, *command])
            return True
    print('Run in a workstation terminal:\n' + shlex.join(command))
    return False


def manage(scope=None):
    company = scope is not None and scope['id'] != 'personal'
    root = setup_profiles.account_root(scope) if company else setup_profiles.ROOT
    notice = ''
    agent_started = False
    while True:
        try:
            settings = read_json(root / 'device-registry.json', {})
            if not settings.get('enabled'):
                action, selected = choose('DEVICES · ' + (scope['name'] if scope else 'Personal'),
                    [('Configure device registry', 'configure'), ('Sign into this account', 'login')],
                    lambda _: [notice, 'Registration does not grant SSH access.', 'Your private key stays on this workstation.'])
                if action == 'b': return
                if action != 'enter': continue
                if selected == 'configure': configure(root, company)
                elif selected == 'login': signin(root)
                continue
            client = Devices(root).register()
            try:
                client.sync()
                if not agent_started:
                    start_agent(); agent_started = True
            except (SyncError, OSError): notice = 'Incoming sync needs attention; existing grants expire unless refreshed.'
            inventory = client.inventory()
            me = client.state['id']
            connections = inventory['connections']
            def related(peer):
                incoming = next((g['state'] for g in connections if g['source'] == peer['id'] and g['destination'] == me), 'not allowed')
                outgoing = next((g['state'] for g in connections if g['source'] == me and g['destination'] == peer['id']), 'not allowed')
                return incoming, outgoing
            rows = []
            for device in inventory['devices']:
                incoming, outgoing = related(device)
                label = device['name'] + (' · This device' if device['id'] == me else ' · Registered')
                if device['id'] != me and incoming == 'requested': label += ' · Request incoming'
                rows.append((label, device))
            def detail(device):
                if not device: return [notice, 'No registered devices.']
                incoming, outgoing = related(device)
                return [device['username'] + ' on ' + device['name'],
                        'Incoming: ' + incoming + ' · Outgoing: ' + outgoing, notice, device['platform'],
                        'Checked in ' + str(max(0, int(time.time() - device['lastSeen']))) + 's ago (not a reachability test)',
                        'Login key: ' + device['fingerprint'], 'Server key: ' + (device['hostFingerprint'] or 'Not configured'),
                        'SSH: ' + (device['address'] or 'Outgoing only') + ':' + str(device['port'])]
            action, peer = choose('DEVICES · ' + (scope['name'] if scope else 'Personal'), rows, detail,
                'Enter Actions  R Refresh  C Configure  L Sign in  S Start sync  D Disable')
            if action == 'b': return
            if action == 'r': continue
            if action == 'c': configure(root, company)
            elif action == 'l': signin(root)
            elif action == 's': start_agent(); notice = 'Background check-in requested; incoming leases renew while signed in.'
            elif action == 'd' and confirm('Disable this context and remove its managed incoming access here?'):
                signout(root); settings['enabled'] = False; atomic(root / 'device-registry.json', settings)
            elif action == 'enter' and peer:
                if peer['id'] == me:
                    actions = [('Forget this registration', 'forget')]
                else:
                    actions = [('Connect to ' + peer['name'], 'connect'),
                               ('Request permission to connect there', 'request'),
                               ('Allow ' + peer['username'] + ' on ' + peer['name'] + ' to connect here', 'approve'),
                               ('Remove incoming access from this device', 'revoke'),
                               ('Forget this device and all its managed grants', 'forget')]
                key, selected = choose(peer['username'] + ' on ' + peer['name'], actions, lambda _: detail(peer))
                if key != 'enter': continue
                if selected == 'connect':
                    launch(client.connect_command(peer, client.inventory()))
                    ask('Press Enter to return')
                elif selected == 'forget':
                    if confirm('Retire ' + peer['name'] + '? Existing SSH sessions and unmanaged keys are unaffected'):
                        client.forget(peer)
                        notice = 'Registration retired; other destinations remove grants on sync (offline leases expire within 10 minutes).'
                        if peer['id'] == me: return
                elif selected in ('approve', 'revoke', 'request'):
                    description = ('Allow ' + peer['username'] + ' on ' + peer['name'] + ' → ' + client.state['username'] + ' here?\nLogin fingerprint: ' + peer['fingerprint']) if selected == 'approve' else selected.title() + ' this directional connection?'
                    if confirm(description):
                        client.call(selected, peerId=peer['id']); client.sync()
                        notice = 'Incoming allowed; reverse direction is separate.' if selected == 'approve' else 'Connection ' + selected + ' saved.'
        except (SyncError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
            action, selected = choose('DEVICES · Needs attention', [('Sign in again', 'login'), ('Configure registry', 'configure'), ('Replace local registration', 'replace')],
                lambda _: ['Check sign-in, registry/context approval and native OpenSSH.', 'Saved keys and other profiles are preserved.', notice])
            if action == 'b': return
            if action == 'enter':
                if selected == 'login': signin(root)
                elif selected == 'configure': configure(root, company)
                elif confirm('Retire the old registration and create a new device identity? Old private keys are kept locally'):
                    replacement = Devices(root)
                    replacement.replace_registration()
                    replacement.register().sync()


def signin(root):
    env = dict(os.environ, WORKBENCHES_ACCOUNT_ROOT=str(root), WORKBENCHES_ACCOUNT_OFFLINE='1')
    env.pop('WORKBENCHES_ACCOUNT_ISSUER', None); env.pop('WORKBENCHES_ACCOUNT_CLIENT_ID', None)
    result = subprocess.run([os.sys.executable, str(Path(__file__).with_name('setup-workbenches-account.py'))], env=env)
    propagate_cancel(result.returncode)
