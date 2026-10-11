#!/usr/bin/env python3
"""Test credential recovery transports without Azure, Docker, or real secrets."""
import errno
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
SUBJECT = REPO / "scripts/backup-ai-profile-credentials-to-kv.sh"


class RecoveryRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # Exclude the workstation's real az, docker and Python installers.
        for name in ("bash", "dirname", "stat", "id", "jq", "cmp", "sha256sum",
                     "realpath", "mktemp", "chmod", "rm", "mkdir", "cp", "mv",
                     "date", "awk"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.home = self.root / "home"
        self.home.mkdir()
        self.target = self.home / ".claude-profiles/profiles/example/team/team-001/.credentials.json"
        self.manifest = self.root / "manifest.json"
        self.manifest.write_text(json.dumps({
            "schemaVersion": 1, "tenantId": "tenant-test", "subscriptionId": "sub-test",
            "vaultName": "kv-test", "company": "example", "entries": [{
                "provider": "claude", "profile": "team-001", "secretName": "ai-credential-claude-team-001",
                "credentialPath": str(self.target), "enabled": True}]}))
        self.manifest.chmod(0o600)
        self.env = {"PATH": str(self.bin), "HOME": str(self.home),
                    "XDG_DATA_HOME": str(self.home / ".local/share"),
                    "XDG_STATE_HOME": str(self.home / ".local/state"),
                    "TEST_LOG": str(self.root / "calls.jsonl"),
                    "TEST_NATIVE_CACHE": str(self.root / "native-cache"),
                    "TEST_FAKE_AZ": str(self.root / "fake-az")}
        self.write_program(self.root / "fake-az", '''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["TEST_LOG"], "a") as log: log.write(json.dumps({"az": args}) + "\\n")
cache = pathlib.Path(os.environ.get("AZURE_CONFIG_DIR", os.environ["TEST_NATIVE_CACHE"]))
if args[:2] == ["account", "show"]:
    if os.environ.get("TEST_NEEDS_LOGIN") == "1" and not (cache / "signed-in").exists(): sys.exit(1)
    print("wrong-tenant" if os.environ.get("TEST_WRONG_TENANT") else "tenant-test")
elif args[:1] == ["login"]:
    assert args[args.index("--tenant") + 1] == "tenant-test"
    assert "--use-device-code" in args and args[args.index("--output") + 1] == "none"
    print("Open your browser and enter the fixture device code.", file=sys.stderr)
    if os.environ.get("TEST_LOGIN_CANCEL"): sys.exit(130)
    if os.environ.get("TEST_LOGIN_FAIL"): sys.exit(1)
    cache.mkdir(parents=True, exist_ok=True)
    (cache / "signed-in").write_text("fixture")
elif args[:2] == ["keyvault", "show"]:
    print("/subscriptions/sub-test/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv-test")
elif args[:3] == ["keyvault", "secret", "show"]:
    print(json.dumps({"id": "https://kv-test.vault.azure.net/secrets/ai-credential-claude-team-001/version1",
                      "contentType": "application/json; credential-format=claude",
                      "tags": {"company": "example", "provider": "claude", "profile": "team-001", "managedBy": "workBenches"}}))
elif args[:3] == ["keyvault", "secret", "download"]:
    pathlib.Path(args[args.index("--file") + 1]).write_text(json.dumps({"claudeAiOauth": {"accessToken": "fixture-access", "refreshToken": "fixture-refresh"}}))
elif args[:1] == ["version"]: pass
else: sys.exit(2)
''')

    def write_program(self, path, body):
        path.write_text(f"#!{sys.executable}\n" + body)
        path.chmod(0o755)

    def docker(self):
        self.write_program(self.bin / "docker", '''
import json, os, sys
args = sys.argv[1:]
with open(os.environ["TEST_LOG"], "a") as log: log.write(json.dumps({"docker": args}) + "\\n")
if args == ["info"]: sys.exit(1 if os.environ.get("TEST_DOCKER_DOWN") else 0)
assert args[:2] == ["run", "--rm"]
assert args[args.index("--user") + 1] == f"{os.getuid()}:{os.getgid()}"
assert args[args.index("--cap-drop") + 1] == "ALL"
assert args[args.index("--security-opt") + 1] == "no-new-privileges"
assert args.count("--mount") == 1
mount = dict(part.split("=", 1) for part in args[args.index("--mount") + 1].split(","))
assert mount["type"] == "bind" and mount["src"] == mount["dst"]
assert "/ai-credential-kv." in mount["src"] and mount["src"] != os.environ["HOME"]
assert "docker.sock" not in " ".join(args)
for index, arg in enumerate(args):
    if arg == "--env":
        key, value = args[index + 1].split("=", 1); os.environ[key] = value
index = args.index("--entrypoint")
assert args[index + 1] == "az"
assert args[index + 2].startswith("mcr.microsoft.com/azure-cli:")
os.execv(os.environ["TEST_FAKE_AZ"], [os.environ["TEST_FAKE_AZ"], *args[index + 3:]])
''')

    def run_restore(self, *, terminal=False, answer=b"", login=True):
        cmd = [str(SUBJECT), "restore", "--manifest", str(self.manifest)]
        if login: cmd.append("--azure-login")
        if not terminal:
            result = subprocess.run(cmd, env=self.env, input=b"", capture_output=True, timeout=15)
            code, output = result.returncode, result.stdout + result.stderr
        else:
            master, slave = pty.openpty()
            process = subprocess.Popen(cmd, env=self.env, stdin=slave, stdout=slave, stderr=slave)
            os.close(slave)
            output = b""
            try:
                if answer: os.write(master, answer)
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    if select.select([master], [], [], 0.1)[0]:
                        try: chunk = os.read(master, 65536)
                        except OSError as exc:
                            if exc.errno == errno.EIO: break
                            raise
                        if not chunk: break
                        output += chunk
                code = process.wait(timeout=1)
            finally:
                if process.poll() is None: process.kill(); process.wait()
                os.close(master)
        self.assertNotIn(b"fixture-access", output)
        self.assertNotIn(b"fixture-refresh", output)
        self.calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()] if (self.root / "calls.jsonl").exists() else []
        for call in self.calls:
            args = call.get("docker", [])
            if "--mount" in args:
                mount = dict(part.split("=", 1) for part in args[args.index("--mount") + 1].split(","))
                self.assertFalse(Path(mount["src"]).exists(), "temporary login cache was not removed")
        return code, output

    def test_native_cli_preferred(self):
        (self.bin / "az").symlink_to(self.root / "fake-az")
        self.docker()
        self.assertEqual(self.run_restore()[0], 0)
        self.assertTrue(self.target.exists())
        self.assertFalse(any("docker" in call for call in self.calls))

    def test_container_device_login_and_restore(self):
        self.docker()
        self.env["TEST_NEEDS_LOGIN"] = "1"
        self.assertEqual(self.run_restore(terminal=True)[0], 0)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertTrue(any(call.get("az", [])[:1] == ["login"] for call in self.calls))

    def test_container_noninteractive_login_rejected(self):
        self.docker()
        self.env["TEST_NEEDS_LOGIN"] = "1"
        self.assertNotEqual(self.run_restore()[0], 0)
        self.assertFalse(self.target.exists())
        self.assertFalse(any(call.get("az", [])[:1] == ["login"] for call in self.calls))

    def test_login_opt_in_required(self):
        self.docker()
        self.env["TEST_NEEDS_LOGIN"] = "1"
        self.assertNotEqual(self.run_restore(terminal=True, login=False)[0], 0)
        self.assertFalse(self.target.exists())

    def test_wrong_tenant_rejected(self):
        self.docker()
        self.env["TEST_WRONG_TENANT"] = "1"
        self.assertNotEqual(self.run_restore(terminal=True)[0], 0)
        self.assertFalse(self.target.exists())
        self.assertFalse(any(call.get("az", [])[:2] == ["keyvault", "secret"] for call in self.calls))

    def test_failed_login_leaves_no_credentials(self):
        self.docker()
        self.env.update(TEST_NEEDS_LOGIN="1", TEST_LOGIN_FAIL="1")
        self.assertNotEqual(self.run_restore(terminal=True)[0], 0)
        self.assertFalse(self.target.exists())

    def test_cancelled_login_preserves_cancellation_status(self):
        self.docker()
        self.env.update(TEST_NEEDS_LOGIN="1", TEST_LOGIN_CANCEL="1")
        self.assertEqual(self.run_restore(terminal=True)[0], 130)
        self.assertFalse(self.target.exists())

    def test_no_runtime_fails_without_installing(self):
        self.assertNotEqual(self.run_restore()[0], 0)
        self.assertFalse(self.target.exists())
        self.assertFalse((self.home / ".local/share/workbenches/tools").exists())

    def test_unreachable_docker_and_declined_install(self):
        self.docker()
        self.env["TEST_DOCKER_DOWN"] = "1"
        self.assertNotEqual(self.run_restore(terminal=True, answer=b"n\n")[0], 0)
        self.assertFalse((self.home / ".local/share/workbenches/tools").exists())

    def test_existing_user_local_cli_reused(self):
        target = self.home / ".local/share/workbenches/tools/azure-cli/bin/az"
        target.parent.mkdir(parents=True)
        target.symlink_to(self.root / "fake-az")
        self.assertEqual(self.run_restore()[0], 0)

    def test_user_local_install_without_docker(self):
        self.write_program(self.bin / "python3", '''
import os, pathlib, sys
if sys.argv[1:3] == ["-m", "venv"]:
    target = pathlib.Path(sys.argv[3]) / "bin"; target.mkdir(parents=True)
    (target / "az").symlink_to(os.environ["TEST_FAKE_AZ"])
    (target / "python").write_text("#!/bin/bash\\nexit 0\\n"); (target / "python").chmod(0o755)
elif sys.argv[1] != "-c": sys.exit(2)
''')
        self.env["TEST_NEEDS_LOGIN"] = "1"
        self.assertEqual(self.run_restore(terminal=True, answer=b"y\n")[0], 0)
        self.assertTrue(self.target.exists())
        self.assertTrue((self.home / ".local/share/workbenches/tools/azure-cli/bin/az").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
