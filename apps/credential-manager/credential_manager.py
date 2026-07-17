#!/usr/bin/env python3
"""Local-only dashboard for multiple AI harness accounts."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import threading
import webbrowser
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


HOME = Path.home()
STATE_DIR = HOME / ".local/state/workbenches/credential-manager"
STATE_DIR.mkdir(parents=True, exist_ok=True)


@dataclass(frozen=True)
class Account:
    provider: str
    name: str
    email: str
    family: str = ""
    plan: str = ""
    workspace: str = ""
    status: str = "active"
    auth_mode: str = "browser"
    secret_env: str = ""


PROVIDER_ALIASES = {
    "codex": "chatgpt",
    "openai": "chatgpt",
    "zai": "glm",
    "z.ai": "glm",
}

PROVIDER_CLIS = {
    "claude": "claude",
    "chatgpt": "codex",
    "grok": "grok",
    "gemini": "gemini",
    "glm": "opencode",
    "antigravity": "agy",
    "abacus": "abacusai",
}


def canonical_provider(provider: str) -> str:
    provider = provider.strip().lower()
    return PROVIDER_ALIASES.get(provider, provider)


def git_repo_url(repo: Path) -> str:
    try:
        remote = subprocess.check_output(
            ["git", "-C", str(repo), "remote", "get-url", "origin"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""
    if remote.startswith("git@github.com:"):
        remote = "https://github.com/" + remote.removeprefix("git@github.com:")
    if remote.endswith(".git"):
        remote = remote[:-4]
    return remote


def load_accounts(repo: Path) -> list[Account]:
    accounts: list[Account] = []
    seen: set[tuple[str, str]] = set()
    config = repo / "config" if (repo / "config").is_dir() else repo

    unified = config / "ai-harness-accounts.json"
    if unified.exists():
        data = json.loads(unified.read_text())
        for item in data.get("accounts", []):
            provider = canonical_provider(item["provider"])
            account = Account(
                provider=provider,
                name=item["name"],
                email=item.get("email", ""),
                family=item.get("family", ""),
                plan=item.get("plan", ""),
                workspace=item.get("workspace", ""),
                status=item.get("status", "active"),
                auth_mode=item.get("authMode", "browser"),
                secret_env=item.get("secretEnv", ""),
            )
            accounts.append(account)
            seen.add((account.provider, account.name))

    legacy_specs = (
        ("claude", config / "claude-profiles.json", "profiles"),
        ("chatgpt", config / "openai-profiles.json", "profiles"),
        ("grok", config / "grok-profiles.json", "profiles"),
        ("gemini", config / "gemini-profiles.json", "profiles"),
        ("glm", config / "glm-profiles.json", "profiles"),
        ("antigravity", config / "antigravity-accounts.json", "accounts"),
        ("abacus", config / "abacus-accounts.json", "accounts"),
    )
    for provider, path, key in legacy_specs:
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        for item in data.get(key, []):
            identity = (provider, item["name"])
            if identity in seen:
                continue
            account = Account(
                provider=provider,
                name=item["name"],
                email=item.get("email", ""),
                family=item.get("family", ""),
                plan=item.get("plan", ""),
                workspace=item.get("workspace", ""),
                status=item.get("status", "active"),
                auth_mode=item.get("authMode", "browser"),
                secret_env=item.get("secretEnv", ""),
            )
            accounts.append(account)
            seen.add(identity)
    return accounts


def profile_home(account: Account) -> Path | None:
    if account.provider == "claude":
        return HOME / ".claude-profiles/profiles" / account.name
    if account.provider == "chatgpt":
        current = HOME / ".chatgpt-profiles/profiles" / account.name
        legacy = HOME / ".openai-profiles/profiles" / account.name
        return legacy if legacy.exists() and not current.exists() else current
    if account.provider == "grok":
        return HOME / ".grok-profiles/profiles" / account.name
    if account.provider == "gemini":
        return HOME / ".gemini-profiles/profiles" / account.name
    if account.provider == "glm":
        return HOME / ".glm-profiles/profiles" / account.name
    return None


def auth_command(account: Account) -> tuple[list[str], dict[str, str]] | None:
    env = os.environ.copy()
    directory = profile_home(account)
    if account.provider == "claude" and directory:
        directory.mkdir(parents=True, exist_ok=True)
        metadata = directory / ".claude.json"
        if not metadata.exists():
            metadata.write_text('{"hasCompletedOnboarding": true}\n')
            metadata.chmod(0o600)
        env["CLAUDE_CONFIG_DIR"] = str(directory)
        return ["claude", "auth", "login", "--claudeai", "--email", account.email], env
    if account.provider == "chatgpt" and directory:
        directory.mkdir(parents=True, exist_ok=True)
        env["CODEX_HOME"] = str(directory)
        config = directory / "config.toml"
        if not config.exists():
            config.write_text('forced_login_method = "chatgpt"\ncli_auth_credentials_store = "file"\n')
            config.chmod(0o600)
        command = ["codex", "login"]
        if account.auth_mode == "device":
            command.append("--device-auth")
        return command, env
    if account.provider == "grok" and directory:
        directory.mkdir(parents=True, exist_ok=True)
        env["GROK_HOME"] = str(directory)
        command = ["grok", "login"]
        if account.auth_mode == "device":
            command.append("--device-auth")
        return command, env
    return None


def verify(account: Account) -> dict:
    directory = profile_home(account)
    cli = PROVIDER_CLIS.get(account.provider)
    identity_valid = (
        ("@" in account.email or account.auth_mode == "api-key")
        and not account.email.startswith("REPLACE_")
    )
    cli_available = bool(cli and shutil.which(cli))
    auth_supported = account.provider in {"claude", "chatgpt", "grok"}
    result = {
        **account.__dict__,
        "profileDirectory": str(directory) if directory else "",
        "installed": bool(directory and directory.exists()) if directory else cli_available,
        "authenticated": False,
        "identityValid": identity_valid,
        "cliAvailable": cli_available,
        "detail": "Authentication adapter not available",
        "canAuth": auth_supported and account.status != "planned" and identity_valid and cli_available,
    }
    if account.status == "planned":
        result["detail"] = "Planned account"
        return result
    if not identity_valid:
        result["detail"] = "Login email is still a manifest placeholder"
        return result
    if account.provider == "claude" and directory:
        command = ["claude", "auth", "status", "--text"]
        env_key = "CLAUDE_CONFIG_DIR"
    elif account.provider == "chatgpt" and directory:
        command = ["codex", "login", "status"]
        env_key = "CODEX_HOME"
    elif account.provider == "grok" and directory:
        command = ["grok", "models"]
        env_key = "GROK_HOME"
    elif account.provider == "gemini" and directory:
        credential = directory / ".gemini/oauth_creds.json"
        result["authenticated"] = credential.is_file() and credential.stat().st_size > 0
        result["detail"] = (
            "Credential cache present; launch pgemini and run /about to verify"
            if result["authenticated"]
            else "Launch pgemini login PROFILE to sign in"
        )
        return result
    elif account.provider == "glm" and directory:
        result["detail"] = "Use pglm login PROFILE and select Z.AI Coding Plan"
        return result
    elif account.provider == "antigravity":
        result["detail"] = "Session is managed by the operating-system keyring; launch agy to verify or switch accounts"
        return result
    elif account.provider == "abacus":
        if account.secret_env and os.environ.get(account.secret_env):
            result["detail"] = f"{account.secret_env} is present but has not been sent to Abacus for validation"
        else:
            result["detail"] = "Launch abacusai and use /login [email], or provide a per-account ABACUS_API_KEY"
        return result
    else:
        return result
    env = os.environ.copy()
    env[env_key] = str(directory)
    try:
        check = subprocess.run(command, env=env, text=True, capture_output=True, timeout=15)
        output = (check.stdout or check.stderr).strip()
        result["authenticated"] = check.returncode == 0
        result["detail"] = output[-500:] or ("Authenticated" if check.returncode == 0 else "Not authenticated")
    except FileNotFoundError:
        result["detail"] = f"{command[0]} CLI is not installed"
    except subprocess.TimeoutExpired:
        result["detail"] = "Credential check timed out"
    return result


HTML = r'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>AI Harness Account Manager</title><style>
:root{font-family:Inter,system-ui,sans-serif;color:#18212f;background:#f4f7fb}body{margin:0}.wrap{max-width:1180px;margin:auto;padding:28px}header{display:flex;justify-content:space-between;gap:20px;align-items:center}.card{background:#fff;border:1px solid #dce3ec;border-radius:14px;box-shadow:0 4px 18px #19324d0d}.summary{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:22px 0}.metric{padding:18px}.metric b{font-size:28px;display:block}.toolbar{padding:16px 18px;display:flex;justify-content:space-between;align-items:center}button{border:0;border-radius:8px;padding:9px 14px;font-weight:650;cursor:pointer;background:#1769e0;color:white}button.secondary{background:#e8eef7;color:#243247}button:disabled{opacity:.45;cursor:not-allowed}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:13px 15px;border-top:1px solid #e7ecf2;font-size:14px}th{color:#5d6878}.pill{padding:4px 8px;border-radius:999px;font-size:12px;font-weight:700}.good{background:#dcf8e8;color:#15643a}.bad{background:#fff0e1;color:#8b4600}.muted{background:#edf1f6;color:#596575}.detail{max-width:300px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}a{color:#1769e0}#message{margin:12px 0;color:#445}</style></head><body><div class="wrap">
<header><div><h1>AI Harness Account Manager</h1><div>Source of truth: <a id="repo" target="_blank"></a></div></div><button class="secondary" onclick="refresh()">Refresh verification</button></header>
<div class="summary"><div class="metric card"><b id="total">–</b>Accounts</div><div class="metric card"><b id="valid">–</b>Authenticated</div><div class="metric card"><b id="missing">–</b>Need login</div><div class="metric card"><b id="providers">–</b>Providers</div></div>
<div id="message"></div><div class="card"><div class="toolbar"><b>Configured accounts</b><span>Credentials remain in provider-owned profiles or keyrings.</span></div><table><thead><tr><th>Harness</th><th>Profile</th><th>Email</th><th>Plan / workspace</th><th>Local</th><th>Credential</th><th>Detail</th><th></th></tr></thead><tbody id="rows"></tbody></table></div></div>
<script>const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function refresh(){message.textContent='Checking local credentials…';const d=await(await fetch('/api/summary')).json();repo.textContent=d.repositoryUrl||d.repositoryPath;repo.href=d.repositoryUrl||'#';total.textContent=d.accounts.length;valid.textContent=d.accounts.filter(a=>a.authenticated).length;missing.textContent=d.accounts.filter(a=>a.canAuth&&!a.authenticated).length;providers.textContent=new Set(d.accounts.map(a=>a.provider)).size;rows.innerHTML=d.accounts.map(a=>`<tr><td>${esc(a.provider)}</td><td><b>${esc(a.name)}</b><br><small>${esc(a.family)}</small></td><td>${esc(a.email)}</td><td>${esc(a.plan||'–')} / ${esc(a.workspace||'–')}</td><td><span class="pill ${a.installed?'good':'muted'}">${a.installed?'Present':'Missing'}</span></td><td><span class="pill ${a.authenticated?'good':a.canAuth?'bad':'muted'}">${a.authenticated?'Valid':a.canAuth?'Login needed':'Manual'}</span></td><td class="detail" title="${esc(a.detail)}">${esc(a.detail)}</td><td><button ${(!a.canAuth||a.authenticated)?'disabled':''} onclick="login('${esc(a.provider)}','${esc(a.name)}')">Authenticate</button></td></tr>`).join('');message.textContent='';}
async function login(provider,name){message.textContent=`Starting ${name} authentication…`;const r=await fetch('/api/auth',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({provider,name})});const d=await r.json();message.textContent=d.message||d.error;setTimeout(refresh,2500)}refresh();</script></body></html>'''


class App:
    def __init__(self, repo: Path):
        self.repo = repo.resolve()
        self.accounts = load_accounts(self.repo)
        self.repo_url = git_repo_url(self.repo)
        self.processes: dict[str, subprocess.Popen] = {}

    def summary(self) -> dict:
        return {"repositoryPath": str(self.repo), "repositoryUrl": self.repo_url, "accounts": [verify(a) for a in self.accounts]}

    def authenticate(self, provider: str, name: str) -> str:
        account = next((a for a in self.accounts if a.provider == provider and a.name == name), None)
        if not account:
            raise ValueError("Unknown account")
        spec = auth_command(account)
        if not spec:
            raise ValueError(f"Interactive authentication is not supported for {provider}")
        command, env = spec
        if not shutil.which(command[0]):
            raise ValueError(f"{command[0]} CLI is not installed")
        key = f"{provider}-{name}"
        log = STATE_DIR / f"{key}.log"
        stream = log.open("w")
        log.chmod(0o600)
        self.processes[key] = subprocess.Popen(command, env=env, stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        return f"Authentication started for {name}. Complete the provider browser flow, then refresh. Log: {log}"


def handler_for(app: App):
    class Handler(BaseHTTPRequestHandler):
        def reply(self, status: int, body, content_type="application/json"):
            payload = body.encode() if isinstance(body, str) else json.dumps(body).encode()
            self.send_response(status); self.send_header("content-type", content_type); self.send_header("content-length", str(len(payload))); self.end_headers(); self.wfile.write(payload)
        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/": self.reply(200, HTML, "text/html; charset=utf-8")
            elif path == "/api/summary": self.reply(200, app.summary())
            else: self.reply(404, {"error": "Not found"})
        def do_POST(self):
            if urlparse(self.path).path != "/api/auth": return self.reply(404, {"error": "Not found"})
            try:
                length = int(self.headers.get("content-length", "0")); data = json.loads(self.rfile.read(length)); message = app.authenticate(data["provider"], data["name"]); self.reply(202, {"message": message})
            except (ValueError, KeyError, json.JSONDecodeError) as exc: self.reply(400, {"error": str(exc)})
        def log_message(self, fmt, *args): pass
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-repo",
        type=Path,
        default=Path(os.environ.get("AI_HARNESS_ACCOUNT_REPO", Path.home() / ".config/workbenches")),
        help="Local clone containing config/ai-harness-accounts.json or a legacy split manifest",
    )
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    app = App(args.source_repo)
    if not app.accounts: raise SystemExit("No supported account manifests found")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(app))
    url = f"http://127.0.0.1:{args.port}"
    print(f"AI Harness Account Manager: {url}")
    if not args.no_browser: threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    server.serve_forever()


if __name__ == "__main__": main()
