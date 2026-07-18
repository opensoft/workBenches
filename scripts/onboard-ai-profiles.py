#!/usr/bin/env python3
"""Collect consent and compose registry-backed or local AI profile manifests."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
from typing import Any
from urllib.parse import quote


REPO = pathlib.Path(__file__).resolve().parents[1]
COMPOSER_PATH = REPO / "scripts/compose-ai-profiles.py"
SPEC = importlib.util.spec_from_file_location("compose_ai_profiles", COMPOSER_PATH)
COMPOSER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(COMPOSER)

PROVIDERS = tuple(COMPOSER.PROVIDERS)
PROVIDER_LABELS = {
    "claude": "Claude",
    "openai": "GPT/Codex",
    "gemini": "Gemini",
    "grok": "Grok",
    "glm": "Z.AI GLM",
}
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
REPO_RE = re.compile(r"(?:github\.com[:/])([^/]+)/([^/.]+)(?:\.git)?$")


def ask(prompt: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    value = input(f"{prompt}{suffix}: ").strip()
    return value or default


def ask_yes_no(prompt: str, default: bool = False) -> bool:
    marker = "Y/n" if default else "y/N"
    while True:
        value = input(f"{prompt} [{marker}]: ").strip().lower()
        if not value:
            return default
        if value in {"y", "yes"}:
            return True
        if value in {"n", "no"}:
            return False
        print("Enter yes or no.")


def ask_count(prompt: str) -> int:
    while True:
        value = ask(prompt, "0")
        if value.isdigit():
            return int(value)
        print("Enter a whole number zero or greater.")


def ask_email(prompt: str) -> str:
    while True:
        value = ask(prompt).lower()
        if EMAIL_RE.match(value):
            return value
        print("Enter a valid email address.")


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "account"


def parse_providers(value: str | list[str] | None) -> list[str]:
    if value is None or value == "" or value == "all":
        return list(PROVIDERS)
    values = value if isinstance(value, list) else re.split(r"[,\s]+", value.lower())
    if "all" in values:
        return list(PROVIDERS)
    aliases = {"gpt": "openai", "codex": "openai", "zai": "glm", "z.ai": "glm"}
    result: list[str] = []
    for item in values:
        provider = aliases.get(item, item)
        if provider not in PROVIDERS:
            raise ValueError(f"unknown provider: {item}")
        if provider not in result:
            result.append(provider)
    return result


def github_login() -> str:
    try:
        result = subprocess.run(
            ["gh", "api", "user", "--jq", ".login"],
            check=True,
            text=True,
            capture_output=True,
            timeout=20,
        )
        return result.stdout.strip()
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return ""


def standard_credential_homes_detected() -> dict[str, bool]:
    home = pathlib.Path.home()
    return {
        "claude": (home / ".claude/.credentials.json").is_file(),
        "openai": (home / ".codex/auth.json").is_file(),
        "gemini": (home / ".gemini/oauth_creds.json").is_file(),
        "grok": (home / ".grok").is_dir(),
    }


def registry_score(name: str) -> int:
    normalized = name.lower()
    score = 0
    for token, weight in (
        ("ai-credentials", 100),
        ("credential-registry", 90),
        ("credentials", 60),
        ("credential", 50),
        ("tenant", 30),
        ("registry", 20),
    ):
        if token in normalized:
            score += weight
    return score


def discover_registries(org: str) -> list[dict[str, Any]]:
    try:
        result = subprocess.run(
            [
                "gh",
                "repo",
                "list",
                org,
                "--limit",
                "200",
                "--json",
                "name,nameWithOwner,url,sshUrl,isPrivate",
            ],
            check=True,
            text=True,
            capture_output=True,
            timeout=45,
        )
        repos = json.loads(result.stdout)
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []

    candidates: list[dict[str, Any]] = []
    for repo in sorted(repos, key=lambda item: registry_score(item["name"]), reverse=True)[:25]:
        if registry_score(repo["name"]) == 0:
            continue
        check = subprocess.run(
            ["gh", "api", f"repos/{repo['nameWithOwner']}/contents/ai/source.json", "--silent"],
            text=True,
            capture_output=True,
            timeout=20,
        )
        if check.returncode == 0:
            repo["registryRef"] = ""
            candidates.append(repo)
            continue
        try:
            branches_result = subprocess.run(
                ["gh", "api", f"repos/{repo['nameWithOwner']}/branches", "--paginate", "--jq", ".[].name"],
                check=True,
                text=True,
                capture_output=True,
                timeout=30,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            continue
        branch_names = [
            branch
            for branch in branches_result.stdout.splitlines()
            if any(token in branch.lower() for token in ("credential", "registry", "ai-profile"))
        ]
        for branch in branch_names:
            branch_check = subprocess.run(
                [
                    "gh",
                    "api",
                    f"repos/{repo['nameWithOwner']}/contents/ai/source.json?ref={quote(branch, safe='')}",
                    "--silent",
                ],
                text=True,
                capture_output=True,
                timeout=20,
            )
            if branch_check.returncode == 0:
                repo["registryRef"] = branch
                candidates.append(repo)
                break
    return candidates


def choose_registry(label: str, org: str) -> str | dict[str, str]:
    candidates = discover_registries(org)
    if candidates:
        print(f"\nCredential registries found for {label} ({org}):")
        for index, repo in enumerate(candidates, 1):
            privacy = "private" if repo.get("isPrivate") else "public"
            branch = f", branch {repo['registryRef']}" if repo.get("registryRef") else ""
            print(f"  {index}) {repo['nameWithOwner']} ({privacy}{branch})")
        print("  M) Fill profile metadata manually on this workstation")
        print("  U) Enter a registry URL")
        while True:
            value = ask("Select a registry", "1").lower()
            if value == "m":
                return "manual"
            if value == "u":
                return ask("Git repository URL or local path")
            if value.isdigit() and 1 <= int(value) <= len(candidates):
                selected = candidates[int(value) - 1]
                return {"url": selected["sshUrl"], "ref": selected.get("registryRef", "")}
            print("Choose a listed number, M, or U.")

    print(f"No accessible AI credential registry with ai/source.json was found for {org}.")
    return ask("Registry URL or local path (leave blank to fill manually)") or "manual"


def repo_identity(value: str) -> tuple[str, str] | None:
    match = REPO_RE.search(value.rstrip("/"))
    return (match.group(1), match.group(2)) if match else None


def registry_parts(value: str | dict[str, str]) -> tuple[str, str]:
    if isinstance(value, dict):
        return str(value.get("url", "")), str(value.get("ref", ""))
    return str(value), ""


def registry_is_manual(value: str | dict[str, str]) -> bool:
    url, _ = registry_parts(value)
    return not url or url == "manual"


def materialize_registry(value: str | dict[str, str], root: pathlib.Path) -> pathlib.Path | None:
    value, ref = registry_parts(value)
    if not value or value == "manual":
        return None
    candidate = pathlib.Path(value).expanduser()
    if candidate.exists():
        source = candidate / "ai" if (candidate / "ai/source.json").is_file() else candidate
        if (source / "source.json").is_file():
            return source.resolve()
        raise RuntimeError(f"registry has no ai/source.json: {candidate}")

    identity = repo_identity(value)
    if not identity:
        raise RuntimeError(f"could not determine GitHub owner/repository from: {value}")
    owner, repo = identity
    projects_candidate = pathlib.Path.home() / "projects" / repo
    if (projects_candidate / "ai/source.json").is_file():
        return (projects_candidate / "ai").resolve()

    destination = root / owner / repo
    if (destination / ".git").is_dir():
        clean = not subprocess.run(
            ["git", "-C", str(destination), "status", "--porcelain"], capture_output=True, text=True
        ).stdout
        if clean and ref:
            subprocess.run(["git", "-C", str(destination), "fetch", "origin", ref], check=True)
            subprocess.run(["git", "-C", str(destination), "switch", ref], check=True)
        if clean:
            subprocess.run(["git", "-C", str(destination), "pull", "--ff-only"], check=True)
    elif destination.exists():
        raise RuntimeError(f"registry destination is not a Git repository: {destination}")
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", value, str(destination)], check=True)
        if ref:
            subprocess.run(["git", "-C", str(destination), "switch", ref], check=True)
    source = destination / "ai"
    if not (source / "source.json").is_file():
        raise RuntimeError(f"cloned registry has no ai/source.json: {destination}")
    return source.resolve()


def interactive_answers() -> dict[str, Any]:
    print("\nAI account profiles keep work and personal provider logins isolated.")
    print("Profile setup stores names and login emails, never passwords, OAuth tokens, or API keys.")
    detected = [
        PROVIDER_LABELS[provider]
        for provider, present in standard_credential_homes_detected().items()
        if present
    ]
    if detected:
        print("Existing standard credential storage detected for: " + ", ".join(detected))
        print("It will be preserved in place and will not be copied into new profile homes.")
    if not ask_yes_no("Set up separate AI profiles for this workstation now?", False):
        return {"consent": False}

    detected_login = github_login()
    if not shutil.which("gh"):
        print("GitHub CLI is not installed, so private registry discovery is unavailable.")
        print("You may still enter registry URLs/local paths or use manual profiles.")
    elif not detected_login and ask_yes_no("GitHub CLI is not authenticated. Sign in now for registry discovery?", True):
        subprocess.run(["gh", "auth", "login"], check=True)
        detected_login = github_login()
    github_user = ask("Personal GitHub username", detected_login)
    if not github_user:
        raise RuntimeError("a personal GitHub username is required")

    company_count = ask_count("How many companies do you use this workstation for?")
    companies: list[dict[str, Any]] = []
    for index in range(1, company_count + 1):
        print(f"\nCompany {index}")
        name = ask("Company name")
        if not name:
            raise RuntimeError("company name is required")
        email = ask_email(f"Your login email at {name}")
        org = ask(f"GitHub organization for {name}")
        if not org:
            raise RuntimeError("company GitHub organization is required")
        providers = parse_providers(
            ask("AI providers for a manual fallback (all or comma-separated claude,gpt,gemini,grok,glm)", "all")
        )
        companies.append({"name": name, "email": email, "githubOrg": org, "providers": providers})

    personal_count = ask_count("How many personal AI subscription login emails do you use?")
    personal_accounts: list[dict[str, Any]] = []
    for index in range(1, personal_count + 1):
        email = ask_email(f"Personal AI subscription email {index}")
        providers = parse_providers(ask("AI providers for this email if filled manually", "all"))
        personal_accounts.append({"email": email, "providers": providers})
    personal_org = ask("Personal GitHub username or organization that owns your credential registry", github_user)

    print("\nSearching GitHub for credential registries. Only repository metadata and ai/source.json presence are checked.")
    for company in companies:
        company["registry"] = choose_registry(company["name"], company["githubOrg"])
    personal_registry = choose_registry("personal accounts", personal_org)

    return {
        "consent": True,
        "githubUser": github_user,
        "companies": companies,
        "personal": {
            "githubOrg": personal_org,
            "accounts": personal_accounts,
            "registry": personal_registry,
        },
    }


def normalize_answers(payload: dict[str, Any]) -> dict[str, Any]:
    if not payload.get("consent"):
        return {"consent": False}
    github_user = str(payload.get("githubUser", "")).strip()
    if not github_user:
        raise ValueError("githubUser is required")
    companies = payload.get("companies", [])
    personal = payload.get("personal", {})
    if not isinstance(companies, list) or not isinstance(personal, dict):
        raise ValueError("companies and personal must be valid objects")
    for company in companies:
        if not all(str(company.get(field, "")).strip() for field in ("name", "email", "githubOrg")):
            raise ValueError("each company requires name, email, and githubOrg")
        if not EMAIL_RE.match(company["email"]):
            raise ValueError(f"invalid company email: {company['email']}")
        company["providers"] = parse_providers(company.get("providers"))
        company["registry"] = company.get("registry") or "manual"
    accounts = personal.get("accounts", [])
    if not isinstance(accounts, list):
        raise ValueError("personal.accounts must be an array")
    for account in accounts:
        if not EMAIL_RE.match(str(account.get("email", ""))):
            raise ValueError(f"invalid personal email: {account.get('email', '')}")
        account["providers"] = parse_providers(account.get("providers"))
    personal["githubOrg"] = personal.get("githubOrg") or github_user
    personal["registry"] = personal.get("registry") or "manual"
    personal["accounts"] = accounts
    return {
        "consent": True,
        "githubUser": github_user,
        "companies": companies,
        "personal": personal,
    }


def add_manual_profile(
    output: dict[str, list[dict[str, Any]]],
    providers: list[str],
    preferred_name: str,
    email: str,
    family: str,
    workspace: str,
    aliases: list[str],
) -> None:
    suffix = 1
    name = preferred_name
    while any(
        any(name == profile["name"] or name in profile.get("aliases", []) for profile in output[provider])
        for provider in providers
    ):
        suffix += 1
        name = f"{preferred_name}-{suffix}"
    clean_aliases = [alias for alias in aliases if alias != name]
    for provider in providers:
        used = {
            value
            for profile in output[provider]
            for value in (profile["name"], *profile.get("aliases", []))
        }
        provider_aliases = [alias for alias in clean_aliases if alias not in used]
        output[provider].append(
            {
                "name": name,
                "email": email,
                "family": family,
                "aliases": provider_aliases,
                "workspace": workspace,
                "status": "active",
                "sourceMode": "manual-workstation",
            }
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--answers", type=pathlib.Path, help="Use a JSON answer file instead of prompting")
    parser.add_argument(
        "--output-dir",
        type=pathlib.Path,
        default=pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config")) / "workbenches",
    )
    parser.add_argument(
        "--registry-root",
        type=pathlib.Path,
        default=pathlib.Path.home() / ".local/share/workbenches/registries",
    )
    args = parser.parse_args()

    try:
        raw = json.loads(args.answers.read_text()) if args.answers else interactive_answers()
        answers = normalize_answers(raw)
        if not answers.get("consent"):
            print("AI profile setup skipped. Existing standard provider logins were not changed.")
            return 0

        source_paths: list[pathlib.Path] = []
        selected: dict[str, Any] = {}
        for company in answers["companies"]:
            registry = company["registry"]
            source = materialize_registry(registry, args.registry_root)
            selected[f"company:{company['githubOrg']}"] = registry
            if source and source not in source_paths:
                source_paths.append(source)
        personal_registry = answers["personal"]["registry"]
        personal_source = materialize_registry(personal_registry, args.registry_root)
        selected[f"personal:{answers['personal']['githubOrg']}"] = personal_registry
        if personal_source and personal_source not in source_paths:
            source_paths.append(personal_source)

        output = COMPOSER.compose([str(path) for path in source_paths], answers["githubUser"]) if source_paths else {
            provider: [] for provider in PROVIDERS
        }

        for company in answers["companies"]:
            if not registry_is_manual(company["registry"]):
                continue
            slug = slugify(company["name"])
            add_manual_profile(
                output,
                company["providers"],
                f"work-{slug}",
                company["email"],
                f"work-{slug}",
                company["name"],
                [slug],
            )
        if registry_is_manual(answers["personal"]["registry"]):
            for index, account in enumerate(answers["personal"]["accounts"], 1):
                add_manual_profile(
                    output,
                    account["providers"],
                    f"personal-{index}",
                    account["email"],
                    "personal",
                    "personal",
                    [f"personal-{slugify(account['email'].split('@')[0])}"],
                )

        args.output_dir.mkdir(parents=True, exist_ok=True)
        for provider, filename in COMPOSER.PROVIDERS.items():
            COMPOSER.atomic_json(args.output_dir / filename, {"version": 1, "profiles": output[provider]})
        if source_paths and not any(output.values()):
            print(
                "Warning: registries were found, but none granted profiles to the supplied GitHub username.",
                file=sys.stderr,
            )
        state = {
            "version": 1,
            "consent": True,
            "githubUser": answers["githubUser"],
            "companies": answers["companies"],
            "personal": answers["personal"],
            "registries": selected,
            "standardCredentialHomesDetected": standard_credential_homes_detected(),
        }
        COMPOSER.atomic_json(args.output_dir / "ai-profile-onboarding.json", state)
        print(
            "AI profile manifests created: "
            + ", ".join(f"{provider}={len(output[provider])}" for provider in PROVIDERS)
        )
        print("Existing standard provider credential homes were preserved and were not copied into profiles.")
        return 0
    except (ValueError, RuntimeError, COMPOSER.ProfileError, json.JSONDecodeError, OSError, subprocess.CalledProcessError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
