"""Mapped vault recovery. Secrets are entered and fetched inside the container."""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

MAX_BYTES = 24576
REPO = Path(__file__).resolve().parents[1]
IMAGES = {
    "bitwarden": "workbenches-credential-recovery:bitwarden-2026.9.1-v1",
    "1password": "workbenches-credential-recovery:1password-2.40.0-v1",
}


class RecoveryError(Exception):
    pass


def checked_run(argv, **kwargs):
    result = subprocess.run(argv, **kwargs)
    if result.returncode in (130, 143, -signal.SIGINT, -signal.SIGTERM):
        raise SystemExit(130 if result.returncode in (130, -signal.SIGINT) else 143)
    if result.returncode:
        raise RecoveryError("Command failed; check vault access and authentication policy.")
    return result


def docker_ready():
    """Refuse remote contexts before sending a password or mounting local files."""
    context = os.environ.get("DOCKER_CONTEXT")
    endpoint = os.environ.get("DOCKER_HOST") if not context else None
    if not endpoint:
        args = ["docker", "context", "inspect"]
        if context:
            args.append(context)
        args += ["--format", "{{.Endpoints.docker.Host}}"]
        endpoint = checked_run(args, capture_output=True, text=True).stdout.strip()
    if not endpoint.startswith("unix://"):
        raise RecoveryError("Credential recovery requires a local Docker socket; select a local context.")
    checked_run(["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def private_file(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RecoveryError("Recovery mapping must be an owner-only regular file (chmod 600).")
    if info.st_size > 262144:
        raise RecoveryError("Recovery mapping is too large.")


def validate_mapping(data, service):
    if (not isinstance(data, dict) or data.get("schemaVersion") != 1
            or data.get("service") != service or not isinstance(data.get("entries"), list)):
        raise RecoveryError("Invalid recovery mapping; use the matching example in config/.")
    if service == "bitwarden":
        server = data.get("server", "")
        if not isinstance(server, str):
            raise RecoveryError("Bitwarden requires an explicit HTTPS server URL.")
        url = urlsplit(server)
        if (url.scheme != "https" or not url.hostname or url.username or url.password
                or url.query or url.fragment):
            raise RecoveryError("Bitwarden requires an explicit HTTPS server URL.")
    elif service != "1password":
        raise RecoveryError("Unsupported recovery service.")
    seen, sources = set(), set()
    for entry in data["entries"]:
        if not isinstance(entry, dict) or type(entry.get("enabled")) is not bool:
            raise RecoveryError("Each mapping entry requires enabled: true or false.")
        if not entry["enabled"]:
            continue
        provider, profile = entry.get("provider", ""), entry.get("profile", "")
        if provider not in ("claude", "codex", "pi", "omniroute") or not isinstance(profile, str) or not re.fullmatch(r"[a-z0-9-]+", profile):
            raise RecoveryError("Invalid provider or profile in recovery mapping.")
        path = entry.get("credentialPath")
        if not isinstance(path, str) or not path.startswith(("/", "~/")):
            raise RecoveryError("Each entry requires an absolute or ~/ credentialPath.")
        if service == "bitwarden":
            source = entry.get("itemId", "")
            if not isinstance(source, str) or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", source):
                raise RecoveryError("Bitwarden entries require exact item UUIDs (JSON in secure notes).")
        else:
            source = entry.get("secretReference", "")
            if not isinstance(source, str) or not re.fullmatch(r"op://[^/?#\s]+/[^/?#\s]+/(?:[^/?#\s]+/)?[^/?#\s]+", source):
                raise RecoveryError("1Password entries require an op://vault/item/field reference.")
        if (provider, profile) in seen or source in sources:
            raise RecoveryError("Enabled mappings must have unique profiles and secret references.")
        seen.add((provider, profile))
        sources.add(source)
    return [entry for entry in data["entries"] if entry["enabled"]]


def target_path(entry):
    provider = entry["provider"]
    home = Path.home()
    roots = {
        "claude": Path(os.environ.get("CLAUDE_PROFILES_HOME", home / ".claude-profiles")) / "profiles",
        "codex": Path(os.environ.get("CODEX_PROFILES_HOME", os.environ.get("CHATGPT_PROFILES_HOME", home / ".chatgpt-profiles"))) / "profiles",
        "pi": Path(os.environ.get("PI_PROFILES_HOME", home / ".pi-profiles")) / "profiles",
        "omniroute": Path(os.environ.get("WORKBENCHES_CREDENTIALS_HOME", Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "workbenches/credentials")) / "opencode",
    }
    suffixes = {"claude": ".credentials.json", "codex": "auth.json", "pi": "agent/auth.json", "omniroute": "omniroute.json"}
    target = Path(entry["credentialPath"]).expanduser()
    root = roots[provider].absolute()
    try:
        relative = target.relative_to(root)
    except ValueError:
        raise RecoveryError("Credential target is outside its approved profile root.") from None
    if ".." in target.parts or not str(relative).endswith("/" + suffixes[provider]):
        raise RecoveryError("Credential target does not match the provider filename.")
    if provider != "omniroute":
        # .../family/tier/profile/<credential filename>; bind the mapping to its profile.
        profile_dir = target.parent.parent if provider == "pi" else target.parent
        if profile_dir.name != entry["profile"]:
            raise RecoveryError("Credential target does not match the mapped profile name.")
    current = target
    while True:
        if current.is_symlink():
            raise RecoveryError("Credential target and its ancestors must not be symlinks.")
        if current.exists():
            info = current.stat()
            if info.st_uid != os.getuid() or info.st_mode & 0o022:
                raise RecoveryError("Credential target ancestors must be owner controlled.")
        if current == root:
            break
        current = current.parent
    if root.resolve() != root:
        raise RecoveryError("Profile root ancestors must not be symlinks.")
    if target.exists() and not target.is_file():
        raise RecoveryError("Credential target is not a regular file.")
    return target


def valid_payload(provider, payload):
    if not 0 < len(payload) <= MAX_BYTES:
        raise RecoveryError("Recovered credential exceeds the supported size.")
    data = json.loads(payload)
    nonempty = lambda value: isinstance(value, str) and bool(value)
    if not isinstance(data, dict):
        raise RecoveryError("Recovered credential must be a JSON object.")
    if provider == "claude":
        oauth = data.get("claudeAiOauth", {})
        valid = isinstance(oauth, dict) and all(nonempty(oauth.get(k)) for k in ("accessToken", "refreshToken"))
    elif provider == "codex":
        tokens = data.get("tokens", {})
        valid = (isinstance(tokens, dict) and all(nonempty(tokens.get(k)) for k in ("access_token", "refresh_token"))) or nonempty(data.get("OPENAI_API_KEY")) or nonempty(data.get("personal_access_token"))
    elif provider == "omniroute":
        valid = set(data) == {"type", "key"} and data["type"] == "api" and nonempty(data["key"])
    else:
        valid = bool(data)
    if not valid:
        raise RecoveryError("Recovered credential does not match its provider format.")


def secret_input(prompt):
    if not sys.stdin.isatty():
        raise RecoveryError("Vault authentication requires an interactive terminal.")
    try:
        value = getpass.getpass(prompt)
    except EOFError:
        raise SystemExit(130) from None
    if value.lower() == "q":
        raise SystemExit(130)
    if not value:
        raise RecoveryError("Authentication input was empty.")
    return value


def vault_command(argv, env, limit=MAX_BYTES):
    # Never relay CLI output or errors to setup logs: they can contain secrets.
    with tempfile.TemporaryFile() as output:
        checked_run(argv, env=env, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.DEVNULL)
        output.seek(0)
        data = output.read(limit + 1)
    if len(data) > limit:
        raise RecoveryError("Vault response exceeds the supported size.")
    return data


def container_restore(mapping, staging):
    service = mapping["service"]
    entries = validate_mapping(mapping, service)
    env = os.environ.copy()
    env.update(HOME="/tmp/session", XDG_CONFIG_HOME="/tmp/session/config", OP_CONFIG_DIR="/tmp/session/op",
               BITWARDENCLI_APPDATA_DIR="/tmp/session/bw", OP_BIOMETRIC_UNLOCK_ENABLED="false")
    Path(env["HOME"]).mkdir(mode=0o700, exist_ok=True)
    try:
        if service == "bitwarden":
            print("Bitwarden API-key login and master-password unlock (inputs stay in this container).", flush=True)
            vault_command(["bw", "config", "server", mapping["server"]], env)
            auth = dict(env, BW_CLIENTID=secret_input("Personal API client_id: "), BW_CLIENTSECRET=secret_input("Personal API client_secret: "))
            vault_command(["bw", "login", "--apikey"], auth)
            unlock = dict(env, BW_PASSWORD=secret_input("Vault master password: "))
            env["BW_SESSION"] = vault_command(["bw", "unlock", "--passwordenv", "BW_PASSWORD", "--raw"], unlock, 4096).decode().strip()
            if not env["BW_SESSION"]:
                raise RecoveryError("Vault unlock returned no session.")
            vault_command(["bw", "sync"], env)
        else:
            print("Use a 1Password service-account token with read access to the mapped vault.", flush=True)
            env["OP_SERVICE_ACCOUNT_TOKEN"] = secret_input("1Password service-account token: ")
        for index, entry in enumerate(entries):
            argv = (["bw", "get", "notes", entry["itemId"]] if service == "bitwarden"
                    else ["op", "read", "--no-newline", entry["secretReference"]])
            payload = vault_command(argv, env)
            valid_payload(entry["provider"], payload)
            destination = staging / f"{index}.json"
            with destination.open("xb") as stream:
                stream.write(payload)
    finally:
        if service == "bitwarden":
            # Cache is tmpfs even when logout fails or the process is cancelled.
            subprocess.run(["bw", "logout"], env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def recover(service, manifest):
    private_file(manifest)
    mapping = json.loads(manifest.read_text())
    entries = validate_mapping(mapping, service)
    selected, targets, seen_targets = [], [], set()
    for entry in entries:
        target = target_path(entry)
        if target in seen_targets:
            raise RecoveryError("Enabled mappings must have unique credential destinations.")
        seen_targets.add(target)
        if target.exists():
            print(f"KEEP {entry['provider']}/{entry['profile']}: existing credential")
        else:
            selected.append(entry)
            targets.append(target)
    if not selected:
        print("No missing mapped credentials to recover.")
        return
    docker_ready()
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise RecoveryError("Password-manager recovery needs an interactive terminal.")
    image = IMAGES[service]
    checked_run(["docker", "build", "--target", "onepassword" if service == "1password" else service, "--tag", image, "--file",
                 str(REPO / "credential-container/Dockerfile"), str(REPO / "credential-container")])
    with tempfile.TemporaryDirectory(prefix="workbenches-credential-") as directory:
        work = Path(directory)
        staging = work / "output"
        staging.mkdir(mode=0o700)
        mapping = dict(mapping, entries=selected)
        config = work / "manifest.json"
        config.write_text(json.dumps(mapping))
        config.chmod(0o600)
        checked_run(["docker", "run", "--rm", "--interactive", "--tty", "--read-only",
                     "--user", f"{os.getuid()}:{os.getgid()}", "--cap-drop", "ALL",
                     "--security-opt", "no-new-privileges", "--tmpfs", "/tmp:rw,nosuid,nodev,mode=1777,size=256m",
                     "--mount", f"type=bind,src={config},dst=/recovery/manifest.json,readonly",
                     "--mount", f"type=bind,src={staging},dst=/recovery/output",
                     image])
        # Validate the whole batch before installing anything. Containers never see profile homes.
        payloads = []
        for index, entry in enumerate(selected):
            source = staging / f"{index}.json"
            private_file(source)
            payload = source.read_bytes()
            valid_payload(entry["provider"], payload)
            target_path(entry)
            payloads.append(payload)
        for entry, target, payload in zip(selected, targets, payloads):
            target_path(entry)
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            target_path(entry)
            target.parent.chmod(0o700)
            temp_name = None
            try:
                with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".credential-", delete=False) as stream:
                    temp_name = stream.name
                    stream.write(payload)
                    stream.flush()
                    os.fsync(stream.fileno())
                # Atomic creation without overwriting a credential created during recovery.
                try:
                    os.link(temp_name, target)
                    print(f"OK {entry['provider']}/{entry['profile']}: recovered credential")
                except FileExistsError:
                    print(f"KEEP {entry['provider']}/{entry['profile']}: existing credential")
            finally:
                if temp_name:
                    Path(temp_name).unlink(missing_ok=True)


def main():
    os.umask(0o077)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", action="store_true")
    parser.add_argument("--service", choices=tuple(IMAGES))
    parser.add_argument("--manifest", type=Path, default=Path("/recovery/manifest.json"))
    args = parser.parse_args()
    try:
        if args.container:
            container_restore(json.loads(args.manifest.read_text()), Path("/recovery/output"))
        elif args.service:
            recover(args.service, args.manifest.expanduser())
        else:
            parser.error("--service is required")
    except KeyboardInterrupt:
        return 130
    except RecoveryError as error:
        print(f"Credential recovery failed: {error} Native provider login remains available.", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError):
        # JSON exceptions can include fragments of credential payloads. Do not print them.
        print("Credential recovery failed. Check the mapping, vault access, and supported sign-in method; native provider login remains available.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
