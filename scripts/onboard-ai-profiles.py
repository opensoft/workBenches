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
from setup_prompts import prompt as metadata_prompt, cancellation_signals, propagate_cancel


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
    value = metadata_prompt(f"{prompt}{suffix}: ")
    return value or default


def ask_yes_no(prompt: str, default: bool = False) -> bool:
    marker = "Y/n" if default else "y/N"
    while True:
        value = metadata_prompt(f"{prompt} [{marker}]: ").lower()
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


def company_name_from_email(email: str) -> str:
    domain = email.rsplit("@", 1)[-1]
    return domain.split(".")[0]


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
        subprocess.run(["bash", str(REPO / "bootstrap.sh"), "--clone", value, str(destination)], check=True)
        if ref:
            subprocess.run(["git", "-C", str(destination), "switch", ref], check=True)
    source = destination / "ai"
    if not (source / "source.json").is_file():
        raise RuntimeError(f"cloned registry has no ai/source.json: {destination}")
    return source.resolve()


def interactive_answers() -> dict[str, Any]:
    print("\nAI account profiles keep work and personal provider logins isolated.")
    print("Q or closed input cancels setup at any prompt.")
    print("Profile setup stores names and login emails, never passwords, OAuth tokens, or API keys.")
    detected = [
        PROVIDER_LABELS[provider]
        for provider, present in standard_credential_homes_detected().items()
        if present
    ]
    if detected:
        print("Existing standard credential storage detected for: " + ", ".join(detected))
        print("It will be preserved in place and will not be copied into new profile homes.")
    if os.environ.get("WORKBENCHES_REQUIRE_PROFILE") != "1" and not ask_yes_no("Set up separate AI profiles for this workstation now?", False):
        return {"consent": False}

    scope = ask("Profile ownership: personal, organization, or registry (advanced)", os.environ.get("WORKBENCHES_IDENTITY_SCOPE", "personal")).lower()
    if scope not in ("personal", "organization", "registry"):
        raise ValueError("choose personal, organization, or registry")
    registry_mode = scope == "registry"
    if registry_mode:
        scope = ask("Registry profile ownership: personal or organization", "organization").lower()
        if scope not in ("personal", "organization"):
            raise ValueError("choose personal or organization")
    selected = os.environ.get("WORKBENCHES_PROFILE_PROVIDERS", "all")
    if not selected:
        selected = ask("AI provider for Pi profiles (claude,gpt,gemini,grok,glm)", "gpt")
    providers = parse_providers(selected)
    email = ask("AI account login email", os.environ.get("WORKBENCHES_IDENTITY_EMAIL", ""))
    if not EMAIL_RE.match(email):
        raise ValueError("Enter a valid AI account login email.")
    companies = []
    personal_accounts = []
    if scope == "organization":
        name = ask("Organization name", os.environ.get("WORKBENCHES_IDENTITY_NAME", company_name_from_email(email)))
        companies = [{"name": name, "email": email, "githubOrg": "",
                      "providers": providers, "registry": "manual"}]
    else:
        personal_accounts = [{"email": email, "providers": providers}]
    github_user = ""
    personal_org = ""
    personal_registry = "manual"
    registry_requested = registry_mode or (
        "WORKBENCHES_SELECTED_PROVIDERS" not in os.environ
        and ask_yes_no("Use a GitHub credential registry (advanced)?", False)
    )
    if registry_requested:
        github_user = ask("GitHub username for registry enrollment", github_login())
        if not github_user:
            raise ValueError("GitHub username is required for registry enrollment")
        for company in companies:
            company["githubOrg"] = ask("GitHub organization that owns the registry")
            if not company["githubOrg"]:
                raise ValueError("registry organization is required")
            company["registry"] = choose_registry(company["name"], company["githubOrg"])
        if personal_accounts:
            print("Your personal registry is optional. If you use one, enter the GitHub username or organization "
                  "that owns its repository (for example, your personal GitHub username).")
            personal_org = ask("Personal credential-registry GitHub owner", github_user)
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
    companies = payload.get("companies", [])
    personal = payload.get("personal", {})
    if not isinstance(companies, list) or not isinstance(personal, dict):
        raise ValueError("companies and personal must be valid objects")
    company_slugs: set[str] = set()
    for company in companies:
        if not all(str(company.get(field, "")).strip() for field in ("name", "email")):
            raise ValueError("each company requires name and email")
        if not EMAIL_RE.match(company["email"]):
            raise ValueError(f"invalid company email: {company['email']}")
        company_slug = slugify(company["name"])
        if company_slug == "personal":
            raise ValueError("company name cannot use the reserved personal profile scope")
        if company_slug in company_slugs:
            raise ValueError(f"company names produce the same profile scope: {company_slug}")
        company_slugs.add(company_slug)
        company["providers"] = parse_providers(company.get("providers"))
        company["registry"] = company.get("registry") or "manual"
        company["githubOrg"] = company.get("githubOrg", "")
        if not registry_is_manual(company["registry"]) and (not github_user or not company["githubOrg"]):
            raise ValueError("registry enrollment requires githubUser and githubOrg")
    accounts = personal.get("accounts", [])
    if not isinstance(accounts, list):
        raise ValueError("personal.accounts must be an array")
    for account in accounts:
        if not EMAIL_RE.match(str(account.get("email", ""))):
            raise ValueError(f"invalid personal email: {account.get('email', '')}")
        account["providers"] = parse_providers(account.get("providers"))
    personal["githubOrg"] = personal.get("githubOrg") or github_user
    personal["registry"] = personal.get("registry") or "manual"
    if not registry_is_manual(personal["registry"]) and not github_user:
        raise ValueError("registry enrollment requires githubUser")
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
    profile_path: str,
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
                "profilePath": f"{profile_path}/{name}",
                "aliases": provider_aliases,
                "workspace": workspace,
                "status": "active",
                "sourceMode": "manual-workstation",
            }
        )


def company_profile_category(profile: dict[str, Any]) -> str:
    path_parts = str(profile.get("profilePath", "")).lower().split("/")
    for category in ("team", "max", "xfactor"):
        if category in path_parts:
            return category
    name = str(profile["name"]).lower()
    if name == "team" or name.startswith("team-"):
        return "team"
    if name == "max" or name.startswith("max-"):
        return "max"
    return "xfactor"


def apply_scope_layout(
    output: dict[str, list[dict[str, Any]]],
    scoped: dict[str, list[dict[str, Any]]],
    family: str,
    workspace: str,
) -> None:
    for provider, profiles in scoped.items():
        by_name = {profile["name"]: profile for profile in output[provider]}
        for source_profile in profiles:
            target = by_name[source_profile["name"]]
            target["family"] = family
            target["workspace"] = workspace
            if family == "personal":
                target["profilePath"] = f"personal/{target['name']}"
            else:
                category = company_profile_category(source_profile)
                target["profilePath"] = f"{family}/{category}/{target['name']}"


def merge_identity_profiles(existing: list[dict[str, Any]], incoming: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged = list(existing)
    used = {value: profile for profile in merged for value in (profile['name'], *profile.get('aliases', []))}
    def identity(profile: dict[str, Any]) -> tuple[str, str]:
        return (profile.get('email', '').strip().casefold(), profile.get('family', ''))
    for profile in incoming:
        preferred = profile['name']
        name, suffix = preferred, 1
        while name in used:
            # Rerunning this identity reuses its existing name/path and credentials.
            if identity(profile)[0] and identity(used[name]) == identity(profile):
                break
            suffix += 1
            name = f'{preferred}-{suffix}'
        else:
            added = dict(profile, name=name)
            if name != preferred:
                prefix = profile['profilePath'].rsplit('/', 1)[0]
                added['profilePath'] = f'{prefix}/{name}'
            added['aliases'] = [alias for alias in profile.get('aliases', []) if alias != name and alias not in used]
            merged.append(added)
            used.update({value: added for value in (name, *added['aliases'])})
    return merged


def main() -> int:
    cancellation_signals()
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
        company_sources: list[tuple[dict[str, Any], pathlib.Path]] = []
        selected: dict[str, Any] = {}
        for company in answers["companies"]:
            registry = company["registry"]
            source = materialize_registry(registry, args.registry_root)
            selected[f"company:{company['githubOrg']}"] = registry
            if source and source not in source_paths:
                source_paths.append(source)
            if source:
                company_sources.append((company, source))
        personal_registry = answers["personal"]["registry"]
        personal_source = materialize_registry(personal_registry, args.registry_root)
        selected[f"personal:{answers['personal']['githubOrg']}"] = personal_registry
        if personal_source and personal_source not in source_paths:
            source_paths.append(personal_source)

        output = COMPOSER.compose([str(path) for path in source_paths], answers["githubUser"]) if source_paths else {
            provider: [] for provider in PROVIDERS
        }
        assigned: dict[tuple[str, str], str] = {}
        for company, source in company_sources:
            family = slugify(company["name"])
            scoped = COMPOSER.compose([str(source)], answers["githubUser"])
            for provider, profiles in scoped.items():
                for profile in profiles:
                    key = (provider, profile["name"])
                    previous = assigned.get(key)
                    if previous and previous != family:
                        raise RuntimeError(
                            f"{provider} profile {profile['name']} is assigned to multiple companies"
                        )
                    assigned[key] = family
            apply_scope_layout(output, scoped, family, company["name"])
        if personal_source:
            scoped = COMPOSER.compose([str(personal_source)], answers["githubUser"])
            for provider, profiles in scoped.items():
                for profile in profiles:
                    key = (provider, profile["name"])
                    if key in assigned:
                        raise RuntimeError(
                            f"{provider} profile {profile['name']} is assigned to company and personal registries"
                        )
            apply_scope_layout(output, scoped, "personal", "personal")

        for company in answers["companies"]:
            if not registry_is_manual(company["registry"]):
                continue
            slug = slugify(company["name"])
            add_manual_profile(
                output,
                company["providers"],
                f"work-{slug}",
                company["email"],
                slug,
                f"{slug}/xfactor",
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
                    "personal",
                    [f"personal-{slugify(account['email'].split('@')[0])}"],
                )

        args.output_dir.mkdir(parents=True, exist_ok=True)
        families = [slugify(company["name"]) for company in answers["companies"]]
        families.append("personal")
        for provider, filename in COMPOSER.PROVIDERS.items():
            if not output[provider] and "WORKBENCHES_SELECTED_PROVIDERS" in os.environ:
                continue
            destination = args.output_dir / filename
            if os.environ.get('WORKBENCHES_IDENTITY_SCOPE') and destination.is_file():
                existing = json.loads(destination.read_text())
                existing_profiles = existing.get('profiles', [])
                # Adding an identity must never replace another identity's AI profiles.
                output[provider] = merge_identity_profiles(existing_profiles, output[provider])
                families = list(dict.fromkeys([*existing.get('families', []), *families]))
            if "WORKBENCHES_SELECTED_PROVIDERS" in os.environ and not os.environ.get('WORKBENCHES_IDENTITY_SCOPE') and destination.is_file():
                existing = json.loads(destination.read_text())
                if existing.get("profiles"):
                    print(f"Preserving configured {provider} profiles.")
                    continue
            COMPOSER.atomic_json(
                destination,
                {"version": 1, "families": families, "profiles": output[provider]},
            )
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
        if isinstance(exc, subprocess.CalledProcessError):
            propagate_cancel(exc.returncode)
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
