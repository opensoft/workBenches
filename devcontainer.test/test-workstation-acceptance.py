#!/usr/bin/env python3
"""Online acceptance in the declared, disposable workstation/Docker engine.

No host home/socket is mounted. Only generated test accounts are used. HTTPS is
verified against a generated CA, added only to this disposable credential image.
Hosted vault MFA/SSO and real AI account authorization require separate accounts.
"""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import pty
import re
import secrets
import select
import signal
import ssl
import subprocess
import time
import urllib.request

HOME = Path.home()
REPO = HOME / 'projects/workBenches'
REPORT = Path('/report')
COMPOSE = ['docker', 'compose', '-p', 'acceptance-vault', '-f',
           '/source/devcontainer.test/workstation/vault-compose.yml']
IMAGE = 'workbenches-credential-recovery:bitwarden-2026.9.1-v3'
ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
ENV = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
           GIT_TERMINAL_PROMPT='0', WORKBENCHES_SKIP_WAVE_WIDGETS='1',
           WORKBENCHES_SKIP_ESTATE_COMMANDS='1', WORKBENCHES_SKIP_WORKSPACE_REPO='1',
           WORKBENCHES_SKIP_PROJECT_COMMAND='1', NPM_CONFIG_USERCONFIG=str(HOME / '.npmrc'))
ENV['BUILDKIT_PROGRESS'] = 'plain'
MARKERS = []
RESULTS = []


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, env=ENV, **kwargs)


def terminal(name, replies, expected=0, env=None, timeout=1800):
    master, slave = pty.openpty()
    process = subprocess.Popen(['bash', 'setup.sh'], cwd=REPO, env=env or ENV,
                               stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    output, last, answered = b'', 0, 0
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                clean = ANSI.sub('', output.decode(errors='replace')).replace('\r', '')
                safe = clean
                for marker in MARKERS:
                    safe = safe.replace(marker, '[redacted test value]')
                (REPORT / (name + '.txt')).write_text(safe)
                if answered < len(replies):
                    pattern, reply = replies[answered]
                    match = re.search(pattern, clean[last:])
                    if match:
                        last += match.end()
                        os.write(master, reply.encode())
                        answered += 1
            if process.poll() is not None:
                break
        process.wait(timeout=5)
        assert process.returncode == expected, (name, process.returncode)
        assert answered == len(replies), (name, 'unanswered prompts', answered)
        clean = ANSI.sub('', output.decode(errors='replace')).replace('\r', '')
        assert all(marker not in clean for marker in MARKERS), 'test value leaked to terminal'
        RESULTS.append({'case': name, 'exitCode': process.returncode, 'prompts': answered})
        print(f'PASS {name}', flush=True)
        return clean
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        os.close(master)
        clean = ANSI.sub('', output.decode(errors='replace')).replace('\r', '')
        for marker in MARKERS:
            clean = clean.replace(marker, '[redacted test value]')
        (REPORT / (name + '.txt')).write_text(clean)
        (REPORT / 'results.json').write_text(json.dumps(RESULTS, indent=2) + '\n')


def bw(*args, session=None):
    # Capture all CLI bytes; neither login/session nor encrypted item output is
    # relayed into reports. Generated password is passed through the environment.
    env = dict(ENV, BW_PASSWORD=MASTER)
    if session:
        env['BW_SESSION'] = session
    result = subprocess.run(COMPOSE + ['run', '--rm', '--no-deps', 'credential-tools', *args],
                            env=env, capture_output=True, text=True)
    if result.returncode:
        diagnostic = result.stderr
        for marker in MARKERS:
            diagnostic = diagnostic.replace(marker, '[redacted test value]')
        diagnostic = re.sub(r'[A-Za-z0-9_+/=.-]{20,}', '[redacted]', diagnostic)
        raise RuntimeError('native Bitwarden test-account operation failed: ' + args[0] + ': ' + diagnostic[:600])
    return result.stdout.strip()


def seed_vault():
    """Register using Vaultwarden's API, then let native bw encrypt the item.

    Account API contract: vaultwarden/1.37.4/src/api/core/accounts.rs.
    Bitwarden type-2 user key: HKDF enc/mac + AES256-CBC + HMAC-SHA256.
    """
    tls = Path('/acceptance/tls')
    tls.mkdir(mode=0o700)
    gateway = subprocess.check_output(['docker', 'network', 'inspect', 'bridge',
                                      '--format', '{{(index .IPAM.Config 0).Gateway}}'], text=True).strip()
    server = f'https://{gateway}:18443'
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
         '-keyout', str(tls / 'key.pem'), '-out', str(tls / 'cert.pem'),
         '-subj', '/CN=workbenches-acceptance', '-addext', f'subjectAltName=IP:{gateway}',
         '-addext', 'basicConstraints=critical,CA:TRUE'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    (tls / 'key.pem').chmod(0o600)
    run(COMPOSE + ['up', '-d', 'vault'])
    context = ssl.create_default_context(cafile=str(tls / 'cert.pem'))
    for _ in range(60):
        try:
            urllib.request.urlopen(server + '/alive', context=context, timeout=2).close()
            break
        except (OSError, urllib.error.URLError):
            time.sleep(1)
    else:
        raise RuntimeError('disposable HTTPS vault did not start')
    mk = hashlib.pbkdf2_hmac('sha256', MASTER.encode(), EMAIL.encode(), 600000, 32)
    auth = hashlib.pbkdf2_hmac('sha256', mk, MASTER.encode(), 1, 32)
    # Bitwarden expands the master key directly with HKDF-Expand.
    enc = hmac.new(mk, b'enc\x01', 'sha256').digest()
    mac = hmac.new(mk, b'mac\x01', 'sha256').digest()
    encode = lambda value: base64.b64encode(value).decode()
    def wrap(value, encryption_key, mac_key):
        iv = secrets.token_bytes(16)
        result = subprocess.run(['openssl', 'enc', '-aes-256-cbc', '-K', encryption_key.hex(), '-iv', iv.hex()],
                                input=value, capture_output=True)
        if result.returncode:
            raise RuntimeError('test account key encryption failed')
        cipher = result.stdout
        return '2.' + '|'.join(encode(part) for part in (iv, cipher, hmac.new(mac_key, iv + cipher, 'sha256').digest()))
    user_key = secrets.token_bytes(64)
    wrapped = wrap(user_key, enc, mac)
    rsa = subprocess.check_output(['openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048'],
                                  stderr=subprocess.DEVNULL)
    public = subprocess.check_output(['openssl', 'pkey', '-pubout', '-outform', 'DER'], input=rsa)
    private = subprocess.check_output(['openssl', 'pkcs8', '-topk8', '-nocrypt', '-outform', 'DER'], input=rsa)
    payload = {'email': EMAIL, 'name': 'Disposable acceptance account', 'masterPasswordHash': encode(auth),
               'key': wrapped, 'kdf': 0, 'kdfIterations': 600000,
               'keys': {'publicKey': encode(public), 'encryptedPrivateKey': wrap(private, user_key[:32], user_key[32:])}}
    request = urllib.request.Request(server + '/identity/accounts/register/send-verification-email',
                                     data=json.dumps({'email': EMAIL, 'name': 'Acceptance'}).encode(),
                                     headers={'Content-Type': 'application/json', 'Accept': 'application/json'})
    with urllib.request.urlopen(request, context=context, timeout=10) as response:
        payload['emailVerificationToken'] = json.load(response)
    request = urllib.request.Request(server + '/identity/accounts/register/finish', data=json.dumps(payload).encode(),
                                     headers={'Content-Type': 'application/json'})
    urllib.request.urlopen(request, context=context, timeout=10).close()
    # Keep certificate verification enabled. This is the only disposable clone
    # modification: trust this test CA in Node, never disable TLS verification.
    container = REPO / 'credential-container'
    (container / 'acceptance-ca.pem').write_bytes((tls / 'cert.pem').read_bytes())
    with (container / '.dockerignore').open('a') as stream:
        stream.write('\n!acceptance-ca.pem\n')
    with (container / 'Dockerfile').open('a') as stream:
        stream.write('\nCOPY acceptance-ca.pem /opt/workbenches/acceptance-ca.pem\n'
                     'ENV NODE_EXTRA_CA_CERTS=/opt/workbenches/acceptance-ca.pem\n')
    Path('/acceptance/seed').mkdir(mode=0o700)
    run(COMPOSE + ['build', 'credential-tools'])
    bw('config', 'server', server)
    session = bw('login', EMAIL, '--passwordenv', 'BW_PASSWORD', '--raw')
    MARKERS.append(session)
    item = json.loads(bw('get', 'template', 'item', session=session))
    item.update(name='WorkBenches acceptance Codex', type=1,
                login={'username': EMAIL, 'password': API_VALUE, 'uris': []}, notes=None)
    encoded = encode(json.dumps(item).encode())
    bw('create', 'item', encoded, session=session)
    bw('logout')
    return server


def snapshot():
    paths = [HOME / '.bashrc', HOME / '.zshrc', HOME / '.npmrc',
             HOME / '.chatgpt-profiles/profiles/personal/personal-1/auth.json',
             HOME / '.config/workbenches/ai-credential-vaultwarden.json']
    return [(str(path), path.read_bytes(), path.stat().st_mtime_ns) for path in paths]


TUI = 'Changes selected: 0'
CODEX = (TUI, '\x1b[C\x1b[B\x1b[B \n')
REVIEW = r'Apply these changes\?.*\(Q to cancel\): '
DONE = r'Press Enter to continue.*\(Q to cancel\): '
EMAIL = 'acceptance@example.test'
MASTER = secrets.token_urlsafe(32)
API_VALUE = 'acceptance-' + secrets.token_hex(24)  # Invalid, nonbillable AI test value.
MARKERS.extend([MASTER, API_VALUE])


def main():
    assert str(HOME) == '/home/node' and not REPO.exists(), 'requires fresh declared workstation volumes'
    assert not (HOME / '.ssh').exists(), 'anonymous clone must have no SSH identity'
    REPORT.mkdir(exist_ok=True)
    ref = os.environ.get('WORKBENCHES_ACCEPTANCE_REF', 'main')
    bootstrap = Path('/acceptance/bootstrap.sh')
    run(['curl', '-fsSL', 'https://raw.githubusercontent.com/opensoft/workBenches/' + ref + '/bootstrap.sh',
         '-o', str(bootstrap)])
    run(['bash', str(bootstrap), '--branch', ref, '--directory', str(REPO)])
    sha = subprocess.check_output(['git', '-C', str(REPO), 'rev-parse', 'HEAD'], text=True).strip()
    expected = os.environ.get('WORKBENCHES_ACCEPTANCE_SHA')
    assert not expected or sha == expected, 'remote moved; retest the intended commit'
    (REPORT / 'environment.json').write_text(json.dumps({'sha': sha, 'ref': ref, 'vault': 'Vaultwarden 1.37.4',
        'credentials': 'generated test account and invalid AI key', 'hostSocketMounted': False,
        'tls': 'verified private test CA; appended only to disposable credential Dockerfile'}, indent=2) + '\n')
    terminal('quit', [(TUI, 'Q')], 130)
    terminal('empty', [(TUI, '\n')])
    terminal('decline', [CODEX, (REVIEW, 'n\n')], 130)
    assert not (HOME / '.config/workbenches/openai-profiles.json').exists()
    server = seed_vault()
    replies = [CODEX, (REVIEW, '\n'), (r'Authentication route \[1\]: ', '2V\n'),
               (r'Profile ownership:.*: ', '\n'), (r'AI account login email: ', EMAIL + '\n'),
               (r'Vault HTTPS server.*: ', server + '\n'),
               (r'Bitwarden login email.*: ', '\n'),
               (r'Vault master password: ', MASTER + '\n'), (r'Confirm \[y/N\]: ', 'y\n'),
               (DONE, '\n')]
    assert len(replies) <= 10, 'simple recovery flow grew beyond ten responses'
    output = terminal('live-vault-cli-install', replies)
    credential = HOME / '.chatgpt-profiles/profiles/personal/personal-1/auth.json'
    assert json.loads(credential.read_text())['OPENAI_API_KEY'] == API_VALUE
    assert credential.stat().st_mode & 0o777 == 0o600
    assert 'Using ' + str(HOME / '.local') in output, 'global npm permission fallback missing'
    run([str(HOME / '.local/bin/codex'), '--version'])
    ENV['PATH'] = str(HOME / '.local/bin') + ':' + ENV['PATH']
    before = snapshot()
    terminal('repeat-unchanged', [(TUI, '\n')])
    assert snapshot() == before, 'unchanged selection modified installed configuration'
    output = terminal('repeat-update', [CODEX, (REVIEW, '\n'), (DONE, '\n')])
    assert 'Reusing existing credentials' in output and 'Authentication route [1]' not in output
    assert credential.read_bytes() == dict((row[0], row[1]) for row in before)[str(credential)]
    fault_env = dict(ENV, NPM_CONFIG_REGISTRY='http://127.0.0.1:9', NPM_CONFIG_FETCH_RETRIES='0')
    output = terminal('failed-npm-update', [CODEX, (REVIEW, '\n'), (DONE, '\n')], 1, env=fault_env)
    assert 'update failed' in output and 'Codex CLI updated' not in output
    benches = sorted(json.loads((REPO / 'config/bench-config.json').read_text())['benches'])
    selection = (TUI, '\x1b[B' * benches.index('pyBench') + ' \n')
    terminal('bench-install', [selection, (REVIEW, '\n'), (DONE, '\n')], timeout=3600)
    # Native setup must now create Wave-ready containers on first installation.
    run(['bash', str(REPO / 'scripts/wave-container-shell.sh'), '--workbenches-root', str(REPO),
         '--shell', 'bash', '--check', 'pyBench'], cwd=REPO)
    run(['docker', 'exec', '--user', 'node', 'py-bench', 'python3', '--version'])
    run(['docker', 'exec', '--user', 'node', 'py-bench', 'codex', '--version'])
    before = snapshot()
    terminal('repeat-installed-bench', [(TUI, '\n')])
    assert snapshot() == before
    for path in (REPO / 'logs').glob('*.log'):
        assert all(value not in path.read_text() for value in MARKERS), 'test value leaked to setup logs'
    assert not subprocess.check_output(['docker', 'ps', '-a', '--filter', 'ancestor=' + IMAGE, '-q']).strip(), 'credential worker left behind'
    print('PASS disposable workstation acceptance (AI service authorization intentionally untested)', flush=True)


if __name__ == '__main__':
    main()
