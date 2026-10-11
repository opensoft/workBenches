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
import select
import pty
import termios
import time
from urllib.parse import urlsplit

MAX_BYTES = 24576
REPO = Path(__file__).resolve().parents[1]
IMAGES = {
    "bitwarden": "workbenches-credential-recovery:bitwarden-2026.9.1-v3",
    "1password": "workbenches-credential-recovery:1password-2.40.0-v3",
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
        if entry.get("credentialFormat", "json") not in ("json", "api-key"):
            raise RecoveryError("Unsupported stored credential format.")
        if entry.get("credentialFormat") == "api-key" and entry.get("provider") not in ("codex", "omniroute"):
            raise RecoveryError("Raw API-key recovery supports Codex and OmniRoute; other providers require credential JSON.")
        provider, profile = entry.get("provider", ""), entry.get("profile", "")
        if provider not in ("claude", "codex", "pi", "omniroute") or not isinstance(profile, str) or not re.fullmatch(r"[a-z0-9-]+", profile):
            raise RecoveryError("Invalid provider or profile in recovery mapping.")
        path = entry.get("credentialPath")
        if not isinstance(path, str) or not path.startswith(("/", "~/")):
            raise RecoveryError("Each entry requires an absolute or ~/ credentialPath.")
        if service == "bitwarden":
            source = entry.get("itemId", "")
            if not isinstance(source, str) or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", source):
                raise RecoveryError("Bitwarden entries require exact item UUIDs.")
            field = entry.get('itemField', 'notes')
            if field not in ('notes', 'password', 'custom'):
                raise RecoveryError('Unsupported Bitwarden credential field.')
            name = entry.get('customField')
            if field == 'custom':
                if not isinstance(name, str) or not name or len(name) > 120 or not all(c.isprintable() for c in name):
                    raise RecoveryError('Custom credential fields require an exact printable field name.')
            elif name is not None:
                raise RecoveryError('Custom field names require itemField: custom.')
            source = (source, field, name)
        else:
            source = entry.get("secretReference", "")
            if isinstance(source, str) and any(not c.isprintable() for c in source):
                raise RecoveryError("Invalid secret reference characters.")
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


def prompt(text):
    try:
        value = input(text).strip()
    except EOFError:
        raise SystemExit(130) from None
    if value.lower() == "q":
        raise SystemExit(130)
    return value


def native_signin(argv, env):
    """Relay only known authentication prompts, capture CLI sessions privately.

    The CLI gets its own controlling terminal. Raw CLI output (including error
    messages and session tokens) is never printed or written to setup logs.
    """
    pid, terminal = pty.fork()
    if pid == 0:
        settings = termios.tcgetattr(0)
        settings[3] &= ~termios.ECHO
        termios.tcsetattr(0, termios.TCSANOW, settings)
        os.execvpe(argv[0], argv, env)
    buffer = b""
    deadline = time.monotonic() + 300
    try:
        while True:
            if time.monotonic() > deadline:
                raise RecoveryError("Vault sign-in timed out.")
            ready, _, _ = select.select([terminal], [], [], 1)
            if ready:
                try:
                    chunk = os.read(terminal, 4096)
                except OSError:
                    chunk = b""
                if not chunk:
                    break
                buffer = (buffer + chunk)[-8192:]
                text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", buffer.decode(errors="replace"))
                # Match the CLI's known prompts, never relay arbitrary output.
                patterns = ((r"(?i)enter[^\r\n]*secret key[^\r\n]*:\s*$", "1Password Secret Key: "),
                            (r"(?i)(?:enter|master)[^\r\n]*password[^\r\n]*:\s*$", "Vault account password: "),
                            (r"(?i)(?:enter|verification|two.step)[^\r\n]*code[^\r\n]*:\s*$", "Vault verification code: "))
                for pattern, label in patterns:
                    if re.search(pattern, text):
                        answer = secret_input(label)
                        os.write(terminal, (answer + "\n").encode())
                        buffer = b""
                        break
                # Unknown prompts can be cancelled rather than silently hanging.
                if buffer and text.rstrip().endswith(":") and not any(re.search(pattern, text) for pattern, _ in patterns):
                    raise RecoveryError("Unrecognized vault authentication prompt; use advanced login or native provider sign-in.")
        if pid is not None:
            _, status = os.waitpid(pid, 0)
            pid = None
            code = os.waitstatus_to_exitcode(status)
            if code in (130, 143, -signal.SIGINT, -signal.SIGTERM):
                raise SystemExit(130 if code in (130, -signal.SIGINT) else 143)
            if code:
                raise RecoveryError("Vault sign-in failed; check your account and authentication policy.")
        text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", buffer.decode(errors="replace"))
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        session = lines[-1] if lines else ""
        if not session or len(session) > 4096 or not re.fullmatch(r"[A-Za-z0-9_+/=.-]{20,}", session):
            raise RecoveryError("Vault sign-in returned no usable session.")
        return session
    finally:
        if pid is not None:
            os.killpg(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(terminal)

def validate_enrollment(mapping, service):
    # Validate destinations with temporary, syntactically valid locators. The
    # container will replace these only after the user chooses exact items.
    if not isinstance(mapping, dict) or mapping.get("guided") is not True:
        raise RecoveryError("Invalid guided recovery plan.")
    data = dict(mapping, entries=[])
    for index, entry in enumerate(mapping.get("entries", [])):
        row = dict(entry)
        row["itemId" if service == "bitwarden" else "secretReference"] = (
            f"00000000-0000-0000-0000-{index:012d}" if service == "bitwarden" else f"op://vault/item{index}/field")
        data["entries"].append(row)
    return validate_mapping(data, service)


def bitwarden_fields(item):
    """Return locators and labels only; never return decrypted field values."""
    fields = []
    if item.get('notes'):
        fields.append({'itemField': 'notes', 'label': 'Notes'})
    if item.get('type') == 1 and item.get('login', {}).get('password'):
        fields.append({'itemField': 'password', 'label': 'Login password'})
    custom = item.get('fields') or []
    for field in custom:
        name = field.get('name')
        if (field.get('type') in (0, 1) and field.get('value') and isinstance(name, str) and name
                and len(name) <= 120 and all(c.isprintable() for c in name)
                and sum(other.get('name') == name for other in custom) == 1):
            fields.append({'itemField': 'custom', 'customField': name, 'label': name})
    return fields


def bitwarden_payload(entry, env):
    field = entry.get('itemField', 'notes')
    if field in ('notes', 'password'):
        return vault_command(['bw', 'get', field, entry['itemId']], env)
    item = json.loads(vault_command(['bw', 'get', 'item', entry['itemId']], env, 1024 * 1024))
    matches = [row for row in (item.get('fields') or []) if row.get('name') == entry['customField']]
    if len(matches) != 1 or matches[0].get('type') not in (0, 1) or not isinstance(matches[0].get('value'), str):
        raise RecoveryError('The selected custom credential field is missing or ambiguous.')
    value = matches[0]['value'].encode()
    if len(value) > MAX_BYTES:
        raise RecoveryError('Stored credential exceeds the supported size.')
    return value


def pick_item(mapping, entry, env):
    service = mapping["service"]
    while True:
        search = prompt(f"Search {service} for {entry['provider']}/{entry['profile']} (S to skip): ")
        if search.lower() == "s":
            return None
        if not search:
            print("Enter part of the item name.")
            continue
        if service == "bitwarden":
            # Bitwarden's response includes decrypted notes. They stay in this
            # container; only item names/IDs are displayed, never note contents.
            raw = vault_command(["bw", "list", "items", "--search", search], env, 8 * 1024 * 1024)
            items = [{"id": item["id"], "title": item.get("name", "item"), 'fields': bitwarden_fields(item)}
                     for item in json.loads(raw) if bitwarden_fields(item)]
        else:
            raw = vault_command(["op", "item", "list", "--format=json"], env, 8 * 1024 * 1024)
            items = [item for item in json.loads(raw) if search.casefold() in item.get("title", "").casefold()]
        if not items:
            print("No matching credential items. Try a different item name.")
            continue
        if len(items) > 50:
            print("Too many matches; use a more specific search.")
            continue
        for index, item in enumerate(items, 1):
            # Avoid terminal escape/control injection from remote metadata.
            title = ''.join(c for c in str(item['title']) if c.isprintable())[:120]
            identifier = str(item["id"])
            if not re.fullmatch(r"[A-Za-z0-9-]+", identifier):
                raise RecoveryError("Invalid vault item identifier.")
            print(f"  {index}. {title} ({identifier})")
        choice = prompt("Item number (S to skip, Enter to search again): ")
        if choice.lower() == "s":
            return None
        if not choice.isdigit() or not 1 <= int(choice) <= len(items):
            continue
        item = items[int(choice) - 1]
        result = dict(entry)
        if service == "bitwarden":
            result["itemId"] = item["id"]
            fields = item['fields']
            if len(fields) == 1:
                field = fields[0]
            else:
                for index, field in enumerate(fields, 1):
                    print(f"  {index}. {field['label']}")
                choice = prompt('Field containing credentials (S to skip): ')
                if choice.lower() == 's':
                    return None
                if not choice.isdigit() or not 1 <= int(choice) <= len(fields):
                    continue
                field = fields[int(choice) - 1]
            result.update({key: value for key, value in field.items() if key != 'label'})
        else:
            vault = item["vault"]["id"]
            raw = vault_command(["op", "item", "get", item["id"], "--vault", vault, "--format=json"], env, 1024 * 1024)
            # Display field IDs only. Values never leave the container picker.
            fields = [field for field in json.loads(raw).get("fields", []) if field.get("id")]
            for index, field in enumerate(fields, 1):
                label = ''.join(c for c in str(field.get('label') or field['id']) if c.isprintable())[:120]
                print(f"  {index}. {label}")
            field_number = prompt("Field containing credentials (S to skip): ")
            if field_number.lower() == "s":
                return None
            if not field_number.isdigit() or not 1 <= int(field_number) <= len(fields):
                continue
            field = fields[int(field_number) - 1]
            section = field.get("section", {}).get("id")
            reference = f"op://{vault}/{item['id']}/" + (section + "/" if section else "") + field["id"]
            result["secretReference"] = reference
        validate_mapping(dict(mapping, entries=[result]), service)
        print(f"Use this item for {entry['provider']}/{entry['profile']}?")
        if prompt("Confirm [y/N]: ").lower() in ("y", "yes"):
            if entry['provider'] in ('codex', 'omniroute'):
                default = '2' if result.get('itemField') in ('password', 'custom') else '1'
                value = prompt(f"Stored value: 1. Credential JSON  2. API key [{default}]: ") or default
                if value not in ('1', '2'):
                    continue
                result['credentialFormat'] = 'api-key' if value == '2' else 'json'
            return result


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
    entries = validate_enrollment(mapping, service) if mapping.get("guided") else validate_mapping(mapping, service)
    env = os.environ.copy()
    env.update(HOME="/tmp/session", XDG_CONFIG_HOME="/tmp/session/config", OP_CONFIG_DIR="/tmp/session/op",
               BITWARDENCLI_APPDATA_DIR="/tmp/session/bw", OP_BIOMETRIC_UNLOCK_ENABLED="false")
    Path(env["HOME"]).mkdir(mode=0o700, exist_ok=True)
    try:
        if service == "bitwarden":
            vault_command(["bw", "config", "server", mapping["server"]], env)
            method = mapping.get("authMode", "apikey")
            if method == "signin":
                email = prompt("Bitwarden login email: ")
                if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
                    raise RecoveryError("Enter a valid Bitwarden email address.")
                two_step = prompt("Two-step method: 0. Authenticator  1. Email  3. YubiKey OTP [0]: ") or "0"
                if two_step not in ("0", "1", "3"):
                    raise RecoveryError("Use a supported CLI two-step method or advanced API-key login.")
                master = secret_input("Vault master password: ")
                env["BW_SESSION"] = native_signin(["bw", "login", email, "--method", two_step,
                                                   "--passwordenv", "BW_PASSWORD", "--raw"], dict(env, BW_PASSWORD=master))
            elif method == "apikey":
                print("Advanced Bitwarden API-key login (inputs stay in this container).", flush=True)
                auth = dict(env, BW_CLIENTID=secret_input("Personal API client_id: "), BW_CLIENTSECRET=secret_input("Personal API client_secret: "))
                vault_command(["bw", "login", "--apikey"], auth)
                unlock = dict(env, BW_PASSWORD=secret_input("Vault master password: "))
                env["BW_SESSION"] = vault_command(["bw", "unlock", "--passwordenv", "BW_PASSWORD", "--raw"], unlock, 4096).decode().strip()
            else:
                raise RecoveryError("Unsupported Bitwarden sign-in method.")
            if not env["BW_SESSION"]:
                raise RecoveryError("Vault unlock returned no session.")
            vault_command(["bw", "sync"], env)
        else:
            if mapping.get("authMode", "token") == "signin":
                address = prompt("1Password sign-in address (e.g. my.1password.com): ")
                email = prompt("1Password login email: ")
                env["OP_SESSION"] = native_signin(["op", "account", "add", "--signin", "--raw", "--shorthand", "workbenches", "--address", address, "--email", email], env)
                env["OP_ACCOUNT"] = "workbenches"
            elif mapping.get("authMode", "token") == "token":
                env["OP_SERVICE_ACCOUNT_TOKEN"] = secret_input("1Password service-account token: ")
            else:
                raise RecoveryError("Unsupported 1Password sign-in method.")
        if mapping.get("guided"):
            picked = []
            for entry in mapping["entries"]:
                choice = pick_item(mapping, entry, env)
                if choice:
                    picked.append(choice)
            mapping = {key: value for key, value in mapping.items() if key != "guided"}
            mapping["entries"] = entries = picked
            validate_mapping(mapping, service)
            (staging / "mapping.json").write_text(json.dumps(mapping))
        for index, entry in enumerate(entries):
            payload = (bitwarden_payload(entry, env) if service == 'bitwarden'
                       else vault_command(["op", "read", "--no-newline", entry["secretReference"]], env))
            if entry.get("credentialFormat") == "api-key":
                key = payload.decode().strip()
                if not key or any(character.isspace() for character in key):
                    raise RecoveryError("Stored API key must be a nonempty value without whitespace.")
                payload = json.dumps({"OPENAI_API_KEY": key} if entry['provider'] == 'codex' else {"type": "api", "key": key}).encode()
            valid_payload(entry["provider"], payload)
            destination = staging / f"{index}.json"
            with destination.open("xb") as stream:
                stream.write(payload)
    finally:
        if service == "bitwarden":
            # Cache is tmpfs even when logout fails or the process is cancelled.
            subprocess.run(["bw", "logout"], env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def recover(service, manifest, guided_mapping=None):
    if guided_mapping is None:
        private_file(manifest)
        mapping = json.loads(manifest.read_text())
        entries = validate_mapping(mapping, service)
    else:
        mapping = guided_mapping
        validate_enrollment(mapping, service)
        entries = mapping["entries"]
        if manifest.exists() or manifest.is_symlink():
            raise RecoveryError("Guided recovery requires a new mapping path; import the existing mapping instead.")
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
        if guided_mapping is not None:
            returned = staging / "mapping.json"
            private_file(returned)
            returned_mapping = json.loads(returned.read_text())
            selected_entries = validate_mapping(returned_mapping, service)
            approved = {(row["provider"], row["profile"], row["credentialPath"]) for row in selected}
            if any((row["provider"], row["profile"], row["credentialPath"]) not in approved for row in selected_entries):
                raise RecoveryError("Container returned an unapproved credential destination.")
            if returned_mapping.get("server") != mapping.get("server"):
                raise RecoveryError("Container changed the approved vault server.")
            # Persist only validated metadata, never arbitrary container output.
            fields = ("enabled", "provider", "profile", "credentialPath", "itemId", "itemField", "customField", "secretReference", "credentialFormat")
            returned_mapping = {key: mapping[key] for key in ("schemaVersion", "service", "server", "authMode") if key in mapping}
            returned_mapping['entries'] = [{key: row[key] for key in fields if key in row} for row in selected_entries]
            selected = selected_entries
            targets = [target_path(row) for row in selected]
        # Validate the whole batch before installing anything. Containers never see profile homes.
        payloads = []
        for index, entry in enumerate(selected):
            source = staging / f"{index}.json"
            private_file(source)
            payload = source.read_bytes()
            valid_payload(entry["provider"], payload)
            target_path(entry)
            payloads.append(payload)
        if guided_mapping is not None and selected:
            manifest.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
            # Save metadata without replacing an existing mapping.
            with tempfile.NamedTemporaryFile(dir=manifest.parent) as stream:
                stream.write(json.dumps(returned_mapping, indent=2).encode())
                stream.flush()
                os.fsync(stream.fileno())
                os.link(stream.name, manifest)
            print(f"Saved private recovery mapping: {manifest}")
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
