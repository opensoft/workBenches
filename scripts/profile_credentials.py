"""Local credential presence for configured profiles; never probes provider access."""
import importlib.util
import json
import os
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('credential_runtime', REPO / 'credential-container/credential_recovery.py')
RUNTIME = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNTIME)


def entries(providers=None):
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'workbenches'
    manifests = {'claude': ('claude', 'CLAUDE_PROFILES_HOME', '.claude-profiles', '.credentials.json'),
                 'codex': ('openai', 'CODEX_PROFILES_HOME', '.chatgpt-profiles', 'auth.json'),
                 'pi': ('pi', 'PI_PROFILES_HOME', '.pi-profiles', 'agent/auth.json')}
    result = []
    for provider, (filename, variable, default, suffix) in manifests.items():
        if providers is not None and provider not in providers:
            continue
        manifest = config / (filename + '-profiles.json')
        if not manifest.is_file():
            continue
        data = json.loads(manifest.read_text())
        fallback = os.environ.get('CHATGPT_PROFILES_HOME', Path.home() / default) if provider == 'codex' else Path.home() / default
        root = Path(os.environ.get(variable, fallback)) / 'profiles'
        for profile in data.get('profiles', []):
            # Legacy manifests use family/name; current manifests use profilePath.
            relative = profile.get('profilePath') or profile['name']
            entry = {'enabled': True, 'provider': provider, 'profile': profile['name'],
                     'credentialPath': str(root / relative / suffix)}
            RUNTIME.target_path(entry)
            result.append(entry)
    if providers is not None and 'omniroute' in providers:
        root = Path(os.environ.get('WORKBENCHES_CREDENTIALS_HOME', config / 'credentials'))
        result.append({'enabled': True, 'provider': 'omniroute', 'profile': 'opencode',
                       'credentialPath': str(root / 'opencode/omniroute.json')})
    return result


def present(entry):
    try:
        path = RUNTIME.target_path(entry)
        if not path.is_file() or path.stat().st_size > RUNTIME.MAX_BYTES:
            return False
        RUNTIME.valid_payload(entry['provider'], path.read_bytes())
        return True
    except (OSError, ValueError, KeyError, TypeError, RUNTIME.RecoveryError):
        return False


def main():
    provider = {'openai': 'codex', 'Codex': 'codex', 'Claude': 'claude', 'Pi': 'pi'}.get(sys.argv[2], sys.argv[2]) if len(sys.argv) > 2 else None
    selected = os.environ.get('WORKBENCHES_SELECTED_PROVIDERS')
    requested = {provider} if provider else ({'codex' if p == 'openai' else p for p in selected.split(',')} if selected else None)
    rows = entries(requested)
    if sys.argv[1] == 'status':
        if rows and provider != 'omniroute':
            return 0 if all(present(entry) for entry in rows) else 1
        if rows and all(present(entry) for entry in rows):
            return 0
        defaults = {'claude': (Path.home() / '.claude/.credentials.json', 'ANTHROPIC_API_KEY'),
                    'codex': (Path(os.environ.get('CODEX_HOME', Path.home() / '.codex')) / 'auth.json', 'OPENAI_API_KEY'),
                    'pi': (Path.home() / '.pi/agent/auth.json', ''),
                    'omniroute': (Path.home() / '.local/share/opencode/auth.json', '')}
        path, variable = defaults[provider]
        if variable and os.environ.get(variable):
            return 0
        if not path.is_file() or path.stat().st_size > RUNTIME.MAX_BYTES:
            return 1
        payload = path.read_bytes()
        if provider == 'omniroute':
            payload = json.dumps(json.loads(payload).get('omniroute')).encode()
        RUNTIME.valid_payload(provider, payload)
        return 0
    if sys.argv[1] == 'ready':
        return 0 if rows and all(present(entry) for entry in rows) else 1
    if sys.argv[1] == 'profile':
        return 0 if any(entry['profile'] == sys.argv[3] and present(entry) for entry in rows) else 1
    for entry in rows:
        print(f"  {entry['provider']}/{entry['profile']}: {'credentials present' if present(entry) else 'sign-in needed'}")
    print('Credential presence is local; provider access has not been verified.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, RUNTIME.RecoveryError):
        sys.exit(1)
