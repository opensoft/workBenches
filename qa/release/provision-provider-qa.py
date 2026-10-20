#!/usr/bin/env python3
"""Bootstrap independent Team001 QA sessions through the official native CLIs.

Consent is attended once; passwords/codes stay in the local auth terminal. Store
only verified resulting credential files in the dedicated QA vault. Never import
or refresh the team's production backup session as a QA bootstrap shortcut.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time

SUBSCRIPTION = '297b2389-33bf-48c8-8deb-0b92838431e4'
VAULT = 'kv-openbenches-qa'
EMAIL = 'team-001@opensoft.one'


def root(provider):
    directory = Path.home() / '.cache/workbenches-release-qa/provider-sessions' / (provider + '-team001')
    if any(p.is_symlink() for p in [directory, *directory.parents]):
        raise ValueError('Private nonsymlink QA storage required')
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if directory.stat().st_uid != os.getuid() or directory.stat().st_mode & 0o077:
        raise ValueError('Private QA storage required')
    return directory


def environment(provider):
    directory = root(provider)
    home = directory / 'home'; home.mkdir(exist_ok=True, mode=0o700)
    env = {k:v for k,v in os.environ.items() if k in ('PATH', 'TERM', 'LANG', 'LC_ALL')}
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
               XDG_CACHE_HOME=str(home / '.cache'), XDG_DATA_HOME=str(home / '.local/share'), BROWSER='true')
    if provider == 'codex': env['CODEX_HOME'] = str(directory)
    else:
        config = directory / 'claude'; config.mkdir(exist_ok=True, mode=0o700)
        env['CLAUDE_CONFIG_DIR'] = str(config)
    return env


def binary(provider):
    if provider == 'claude' and shutil.which('mise'):
        result = subprocess.run(['mise', 'which', 'claude'], capture_output=True, text=True, timeout=15)
        if result.returncode == 0 and Path(result.stdout.strip()).is_file(): return result.stdout.strip()
    value = shutil.which(provider)
    if not value: raise ValueError('Native provider CLI is required')
    return value


def claims(token):
    parts = token.split('.')
    if len(parts) != 3: raise ValueError('Official CLI identity token required')
    part = parts[1]
    value = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
    if not isinstance(value, dict): raise ValueError('Official CLI identity token required')
    return value


def collect(provider):
    directory = root(provider)
    path = directory / ('auth.json' if provider == 'codex' else 'claude/.credentials.json')
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Credential file must be private')
    credential = json.loads(path.read_bytes())
    if not isinstance(credential, dict): raise ValueError('Native account credential object required')
    session = credential.get('tokens' if provider == 'codex' else 'claudeAiOauth')
    if not isinstance(session, dict): raise ValueError('Native account session required')
    refresh = session.get('refresh_token' if provider == 'codex' else 'refreshToken')
    if not isinstance(refresh, str) or not refresh.strip():
        raise ValueError('Refreshable native account session required')
    account = tenant = subject = None
    if provider == 'codex':
        if credential.get('OPENAI_API_KEY'): raise ValueError('Native account session required')
        # This cache must come from the trusted native CLI login started here;
        # decoded claims are a selection guard, not general JWT authentication.
        proof = claims(credential['tokens']['id_token'])
        if credential.get('auth_mode') != 'chatgpt' or str(proof.get('email') or '').casefold() != EMAIL:
            raise ValueError('Wrong Team001 Codex identity')
        if proof.get('exp', 0) <= time.time(): raise ValueError('Fresh login required')
        account = credential['tokens'].get('account_id')
        subject = proof.get('sub')
    else:
        result = subprocess.run([binary(provider), 'auth', 'status', '--json'], env=environment(provider),
                                capture_output=True, timeout=30)
        if result.returncode: raise ValueError('Claude identity verification failed')
        proof = json.loads(result.stdout)
        if not isinstance(proof, dict): raise ValueError('Claude identity verification failed')
        if proof.get('loggedIn') is not True or str(proof.get('email') or '').casefold() != EMAIL:
            raise ValueError('Wrong Team001 Claude identity')
        if credential['claudeAiOauth']['expiresAt'] / 1000 <= time.time(): raise ValueError('Fresh login required')
        # Organization identity is not the user's account identity.
        account = proof.get('accountId') or proof.get('userId')
        tenant = proof.get('orgId')
    value = {'schemaVersion': 1, 'provider': provider, 'profile': 'Team001', 'email': EMAIL,
             'providerAccountId': account, 'providerTenantId': tenant, 'providerSubject': subject,
             'credential': credential, 'state': 'ready', 'storedAt': time.time()}
    with tempfile.TemporaryDirectory(prefix='openbenches-provider-qa-', dir='/dev/shm') as temporary:
        upload = Path(temporary) / 'session.json'; upload.write_text(json.dumps(value)); upload.chmod(0o600)
        result = subprocess.run(['az', 'keyvault', 'secret', 'set', '--subscription', SUBSCRIPTION,
            '--vault-name', VAULT, '--name', 'qa-' + provider + '-team001-session', '--file', str(upload),
            '--content-type', 'application/json', '--tags', 'application=openBenches', 'environment=qa',
            'profile=Team001', '--query', 'id', '-o', 'tsv', '--only-show-errors'], capture_output=True, timeout=60)
        if result.returncode: raise ValueError('QA vault upload failed')
    print(json.dumps({'provider': provider, 'profile': 'Team001', 'email': EMAIL, 'vault': VAULT, 'status': 'stored'}), flush=True)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provider', required=True, choices=['codex', 'claude'])
    parser.add_argument('--collect-existing-login', action='store_true')
    args = parser.parse_args()
    if not args.collect_existing_login:
        command = ([binary('codex'), '-c', 'cli_auth_credentials_store="file"', 'login', '--device-auth']
                   if args.provider == 'codex' else [binary('claude'), 'auth', 'login', '--claudeai', '--email', EMAIL])
        subprocess.run(command, env=environment(args.provider), check=True)
    else:
        path = root(args.provider) / ('auth.json' if args.provider == 'codex' else 'claude/.credentials.json')
        deadline = time.monotonic() + 1800
        while not path.is_file() and time.monotonic() < deadline: time.sleep(2)
    collect(args.provider)


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError):
        print('QA provider bootstrap needs attention; no credential values emitted.', flush=True)
        raise SystemExit(1)
