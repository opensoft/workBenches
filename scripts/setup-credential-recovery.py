#!/usr/bin/env python3
"""Select supported credential stores during workstation onboarding."""
import argparse
import os
import json
import re
import tempfile
from pathlib import Path
import signal
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
from setup_prompts import prompt, cancellation_signals
import profile_credentials

SERVICES = (
    ("azure", "Azure Key Vault — organization tenant/device-code login", "ai-credential-keyvault.json"),
    ("bitwarden", "Bitwarden — account sign-in; advanced API-key login", "ai-credential-bitwarden.json"),
    ("vaultwarden", "Vaultwarden — Bitwarden-compatible account sign-in", "ai-credential-vaultwarden.json"),
    ("1password", "1Password — account sign-in; advanced service-account token", "ai-credential-1password.json"),
)


def run_recovery(service, manifest, use_container=True):
    # Recheck the Docker context immediately before contacting a vault. Do not
    # forward inherited credentials to Docker through env flags or build args.
    if use_container or service != "azure":
        runtime = profile_credentials.RUNTIME
        try:
            runtime.docker_ready()
        except runtime.RecoveryError as error:
            print(f"{error} Native provider login remains available.", file=sys.stderr)
            return 1
        except OSError:
            print("Credential recovery needs a working local Docker context. Native provider login remains available.", file=sys.stderr)
            return 1
    if service == "azure":
        argv = ["bash", str(REPO / "scripts/backup-ai-profile-credentials-to-kv.sh"), "restore",
                "--manifest", str(manifest), "--azure-login"]
        runtime_mode = "docker" if use_container else os.environ.get("WORKBENCHES_AZURE_CLI_RUNTIME", "auto")
        env = dict(os.environ, WORKBENCHES_AZURE_CLI_RUNTIME=runtime_mode)
    else:
        argv = [sys.executable, str(REPO / "scripts/recover-vault-credentials.py"),
                "--service", "bitwarden" if service == "vaultwarden" else service,
                "--manifest", str(manifest)]
        env = os.environ.copy()
    selected = os.environ.get("WORKBENCHES_SELECTED_PROVIDERS")
    if selected:
        # Existing mappings can include other tools. Limit this setup run to
        # configured profiles of the selected tools without editing the import.
        runtime = profile_credentials.RUNTIME
        try:
            runtime.private_file(manifest)
            mapping = json.loads(manifest.read_text())
            providers = {"codex" if p == "openai" else p for p in selected.split(",")}
            approved = {(row["provider"], row["profile"], row["credentialPath"])
                        for row in profile_credentials.entries(providers)}
            mapping["entries"] = [row for row in mapping["entries"] if row.get("enabled") and
                                  (row["provider"], row["profile"], str(Path(row["credentialPath"]).expanduser())) in approved]
            if not mapping["entries"]:
                print("No mapped credentials for the selected configured profiles.")
                return 0
            with tempfile.TemporaryDirectory(prefix="workbenches-selected-mapping-") as directory:
                filtered = Path(directory) / "mapping.json"
                filtered.write_text(json.dumps(mapping))
                filtered.chmod(0o600)
                argv[argv.index("--manifest") + 1] = str(filtered)
                result = subprocess.run(argv, env=env)
        except (runtime.RecoveryError, OSError, ValueError, KeyError, TypeError):
            print("Invalid private mapping or profile metadata; native provider sign-in remains available.", file=sys.stderr)
            return 1
    else:
        result = subprocess.run(argv, env=env)
    if result.returncode in (130, -signal.SIGINT, 143, -signal.SIGTERM):
        raise SystemExit(130 if result.returncode in (130, -signal.SIGINT) else 143)
    return result.returncode


def write_private(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent) as stream:
        stream.write(json.dumps(data, indent=2).encode())
        stream.flush()
        os.fsync(stream.fileno())
        os.link(stream.name, path)


def guided_recovery(service, manifest, advanced_auth=False):
    providers = os.environ.get("WORKBENCHES_SELECTED_PROVIDERS")
    selected = {"codex" if provider == "openai" else provider for provider in providers.split(",")} if providers else None
    rows = [entry for entry in profile_credentials.entries(selected) if not Path(entry["credentialPath"]).exists()]
    if not rows:
        print("No missing configured credentials. Configure a profile first, or use native provider sign-in.")
        return 0
    if service == "azure":
        print("Azure mappings must match the workBenches ownership tags on existing secrets.")
        mapping = {"schemaVersion": 1, "tenantId": prompt("Azure tenant ID: "),
                   "subscriptionId": prompt("Azure subscription ID: "), "vaultName": prompt("Key Vault name: "),
                   "company": prompt("Company tag on the stored credentials: "), "entries": []}
        for entry in rows:
            name = prompt(f"Secret name for {entry['provider']}/{entry['profile']} (S to skip): ")
            if name and name.lower() != "s":
                mapping["entries"].append(dict(entry, secretName=name))
        if not mapping["entries"]:
            return 0
        write_private(manifest, mapping)
        return run_recovery(service, manifest)
    runtime = profile_credentials.RUNTIME
    canonical = "bitwarden" if service == "vaultwarden" else service
    mapping = {"schemaVersion": 1, "service": canonical, "guided": True, "entries": rows}
    if os.environ.get("WORKBENCHES_VAULT_SERVICE") == service:
        mapping["compact"] = True
        mapping["loginEmail"] = profile_credentials.login_email(rows)
    if canonical == "bitwarden":
        default = "https://vault.bitwarden.com" if service == "bitwarden" else ""
        mapping["server"] = prompt(f"Vault HTTPS server [{default}]: ") or default
    mapping["authMode"] = ("apikey" if canonical == "bitwarden" else "token") if advanced_auth else "signin"
    try:
        runtime.recover(canonical, manifest, guided_mapping=mapping)
        return 0
    except (runtime.RecoveryError, OSError, ValueError, KeyError, TypeError):
        print("Guided recovery failed; check vault access or use native provider sign-in.", file=sys.stderr)
        return 1


def main():
    cancellation_signals()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interactive", action="store_true")
    parser.add_argument("--apply-existing", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--choose-route", type=Path)
    args = parser.parse_args()
    if args.choose_route:
        if profile_credentials.selected_ready():
            fd = os.open(args.choose_route, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW)
            with os.fdopen(fd, "w") as stream:
                stream.write("existing")
            print("Reusing existing credentials for the selected AI tools; vault recovery is unnecessary.")
            return 0
        print("Authentication for selected AI tools (Q cancels setup):")
        print("  1. Sign in directly after installation")
        print("  2B. Bitwarden   2V. Vaultwarden   2P. 1Password   2A. Azure Key Vault")
        print("  2. Advanced vault selection / mapping imports")
        print("  3. Configure authentication later")
        while True:
            answer = prompt("Authentication route [1]: ") or "1"
            compact_services = {"2b": "bitwarden", "2v": "vaultwarden", "2p": "1password", "2a": "azure"}
            if answer.lower() in compact_services or answer in ("1", "2", "3"):
                # The caller supplies a private temporary file.
                fd = os.open(args.choose_route, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW)
                with os.fdopen(fd, "w") as stream:
                    stream.write("vault:" + compact_services[answer.lower()] if answer.lower() in compact_services else {"1": "direct", "2": "vault", "3": "later"}[answer])
                return 0
            print("Choose 1, 2, or 3.")
    if args.list:
        for service, label, _ in SERVICES:
            print(f"{service}: {label}")
        return 0
    if profile_credentials.resolve_env("SKIP_CREDENTIAL_RECOVERY") == "1":
        return 0
    if profile_credentials.selected_ready():
        print("Reusing existing credentials; no missing selected credentials to recover.")
        return 0
    config = profile_credentials.config_root()
    manifests = {service: Path(os.environ.get("AI_CREDENTIAL_KV_MANIFEST", config / filename)) if service == "azure" else config / filename
                 for service, _, filename in SERVICES}
    guided_services = set()
    advanced_services = set()
    if args.interactive:
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            print("Vault selection requires an interactive terminal.", file=sys.stderr)
            return 1
        compact_service = profile_credentials.resolve_env("VAULT_SERVICE")
        if compact_service and compact_service not in manifests:
            raise ValueError("Unsupported credential service")
        print("AI credential recovery (Q cancels setup at any prompt).")
        answer = "y" if profile_credentials.resolve_env("AUTH_ROUTE", sensitive=True) == "vault" else prompt("Do you have AI assistant tokens or profile credentials stored in a vault? [y/N]: ")
        if answer.lower() not in ("y", "yes"):
            print("Profiles can use native provider sign-in.")
            return 0
        if compact_service:
            selected = [compact_service]
            if not manifests[compact_service].is_file():
                guided_services.add(compact_service)
        else:
            print("Supported services; choose all that apply:")
            for index, (_, label, _) in enumerate(SERVICES, 1):
                print(f"  {index}. {label}")
            print("  0. None of these / use native provider sign-in")
            print("Append I to import mapping JSON, or A for automation login (e.g. 2I or 4A).")
            while True:
                answer = prompt("Services (numbers separated by commas or spaces) [0]: ") or "0"
                try:
                    tokens = answer.lower().replace(",", " ").split()
                    if any(not re.fullmatch(r"[0-4](?:i?a?|ai?)", value) for value in tokens):
                        raise ValueError('invalid service')
                    choices = list(dict.fromkeys(int(value[0]) for value in tokens))
                except ValueError:
                    choices = []
                if choices and all(0 <= value <= len(SERVICES) for value in choices) and (0 not in choices or choices == [0]):
                    break
                print("Choose listed service numbers, or 0 to use native sign-in.")
            if choices == [0]:
                return 0
            selected = [SERVICES[index - 1][0] for index in choices]
            imports = {SERVICES[int(value[0]) - 1][0] for value in tokens if 'i' in value and value[0] != '0'}
            advanced_services = {SERVICES[int(value[0]) - 1][0] for value in tokens if 'a' in value and value[0] != '0'}
            for service in selected:
                if service in imports:
                    answer = prompt("Private mapping JSON path (S to skip): ")
                    if answer.lower() == 's':
                        manifests[service] = None
                    else:
                        manifests[service] = Path(answer).expanduser()
                elif not manifests[service].is_file():
                    guided_services.add(service)
    else:
        # Preserve existing unattended Azure recovery without inventing a store
        # or attempting password-manager authentication without a terminal.
        selected = ["azure"] if manifests["azure"].is_file() else []
    failed = False
    for service in selected:
        manifest = manifests[service]
        if manifest is None:
            continue
        if service in guided_services:
            if guided_recovery(service, manifest, service in advanced_services):
                failed = True
            continue
        if not manifest.is_file():
            print(f"No {service} recovery mapping found. Native provider sign-in remains available.", file=sys.stderr)
            failed = True
            continue
        print(f"Recovering missing AI credentials from {service}...", flush=True)
        if run_recovery(service, manifest, use_container=args.interactive):
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
