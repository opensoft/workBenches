#!/usr/bin/env python3
"""Select supported credential stores during workstation onboarding."""
import argparse
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
SERVICES = (
    ("azure", "Azure Key Vault — organization tenant/device-code login", "ai-credential-keyvault.json"),
    ("bitwarden", "Bitwarden — personal API key + master-password unlock", "ai-credential-bitwarden.json"),
    ("vaultwarden", "Vaultwarden — Bitwarden-compatible API key + vault unlock", "ai-credential-vaultwarden.json"),
    ("1password", "1Password — scoped service-account token", "ai-credential-1password.json"),
)


def prompt(text):
    try:
        answer = input(text).strip()
    except EOFError:
        raise SystemExit(130) from None
    if answer.lower() == "q":
        raise SystemExit(130)
    return answer


def run_recovery(service, manifest, use_container=True):
    # Recheck the Docker context immediately before contacting a vault. Do not
    # forward inherited credentials to Docker through env flags or build args.
    if use_container or service != "azure":
        spec = importlib.util.spec_from_file_location("credential_recovery", REPO / "credential-container/credential_recovery.py")
        runtime = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runtime)
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
    result = subprocess.run(argv, env=env)
    if result.returncode in (130, -signal.SIGINT, 143, -signal.SIGTERM):
        raise SystemExit(130 if result.returncode in (130, -signal.SIGINT) else 143)
    return result.returncode


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interactive", action="store_true")
    parser.add_argument("--apply-existing", action="store_true")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.list:
        for service, label, _ in SERVICES:
            print(f"{service}: {label}")
        return 0
    if os.environ.get("WORKBENCHES_SKIP_CREDENTIAL_RECOVERY") == "1":
        return 0
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "workbenches"
    manifests = {service: Path(os.environ.get("AI_CREDENTIAL_KV_MANIFEST", config / filename)) if service == "azure" else config / filename
                 for service, _, filename in SERVICES}
    if args.interactive:
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            print("Vault selection requires an interactive terminal.", file=sys.stderr)
            return 1
        print("AI credential recovery (Q cancels setup at any prompt).")
        answer = prompt("Do you have AI assistant tokens or profile credentials stored in a vault? [y/N]: ")
        if answer.lower() not in ("y", "yes"):
            print("Profiles can use native provider sign-in.")
            return 0
        print("Supported services; choose all that apply:")
        for index, (_, label, _) in enumerate(SERVICES, 1):
            print(f"  {index}. {label}")
        print("  0. None of these / use native provider sign-in")
        while True:
            answer = prompt("Services (numbers separated by commas or spaces) [0]: ") or "0"
            try:
                choices = list(dict.fromkeys(int(value) for value in answer.replace(",", " ").split()))
            except ValueError:
                choices = []
            if choices and all(0 <= value <= len(SERVICES) for value in choices) and (0 not in choices or choices == [0]):
                break
            print("Choose listed service numbers, or 0 to use native sign-in.")
        if choices == [0]:
            return 0
        selected = [SERVICES[index - 1][0] for index in choices]
        for service in selected:
            example = "ai-credential-keyvault.example.json" if service == "azure" else f"ai-credential-{'bitwarden' if service == 'vaultwarden' else service}.example.json"
            print(f"{service}: use an owner-only mapping with approved vault items and profile destinations.")
            print(f"Example: {REPO / 'config' / example}")
            answer = prompt(f"Mapping path [{manifests[service]}] (S to skip this service): ")
            if answer.lower() == "s":
                manifests[service] = None
            elif answer:
                manifests[service] = Path(answer).expanduser()
    else:
        # Preserve existing unattended Azure recovery without inventing a store
        # or attempting password-manager authentication without a terminal.
        selected = ["azure"] if manifests["azure"].is_file() else []
    failed = False
    for service in selected:
        manifest = manifests[service]
        if manifest is None:
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
