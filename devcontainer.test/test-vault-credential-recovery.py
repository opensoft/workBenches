#!/usr/bin/env python3
"""Vault selection and mapped recovery with fake credentials and mocked CLIs."""
import copy
import importlib.util
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
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runtime = load("recovery", ROOT / "credential-container/credential_recovery.py")
selector = load("selector", ROOT / "scripts/setup-credential-recovery.py")


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.mapping = json.loads((ROOT / "config/ai-credential-bitwarden.example.json").read_text())
        self.target = self.home / ".claude-profiles/profiles/company/team/team-001/.credentials.json"
        self.mapping["entries"][0]["credentialPath"] = str(self.target)
        self.manifest = self.home / "mapping.json"
        self.write_mapping()
        self.payload = json.dumps({"claudeAiOauth": {"accessToken": "fake-access", "refreshToken": "fake-refresh"}}).encode()
        self.env = {"HOME": str(self.home)}
        for key in ("CLAUDE_PROFILES_HOME", "CODEX_PROFILES_HOME", "CHATGPT_PROFILES_HOME", "PI_PROFILES_HOME", "WORKBENCHES_CREDENTIALS_HOME", "DOCKER_HOST", "DOCKER_CONTEXT"):
            self.env[key] = ""
        self.env = {**os.environ, **self.env}
        for key, value in list(self.env.items()):
            if value == "":
                self.env.pop(key)
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, self.env, clear=True).start()

    def write_mapping(self):
        self.manifest.write_text(json.dumps(self.mapping))
        self.manifest.chmod(0o600)

    def fake_docker(self, argv, **kwargs):
        if argv[1] == "run":
            output = next(value.split("src=", 1)[1].split(",", 1)[0] for value in argv if "dst=/recovery/output" in value)
            self.staging = Path(output)
            result = self.staging / "0.json"
            result.write_bytes(self.payload)
            result.chmod(0o600)
        return subprocess.CompletedProcess(argv, 0, stdout="unix:///var/run/docker.sock")

    def restore(self, side_effect=None):
        with patch.object(runtime, "checked_run", side_effect=side_effect or self.fake_docker) as run, patch("sys.stdin.isatty", return_value=True), patch("sys.stdout.isatty", return_value=True):
            runtime.recover("bitwarden", self.manifest)
            return run

    def test_restore_container_policy_atomic_install_and_cleanup(self):
        run = self.restore()
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertFalse(self.staging.exists())
        argv = next(call.args[0] for call in run.call_args_list if call.args[0][1] == "run")
        for value in ("--rm", "--read-only", "--interactive", "--tty", "ALL", "no-new-privileges", f"{os.getuid()}:{os.getgid()}"):
            self.assertIn(value, argv)
        mounts = [argv[i + 1] for i, value in enumerate(argv) if value == "--mount"]
        self.assertEqual(len(mounts), 2)
        self.assertIn("readonly", mounts[0])
        self.assertFalse(any(str(self.target.parent) in mount or "docker.sock" in mount for mount in mounts))
        self.assertNotIn("--env", argv)

    def test_existing_credential_preserved_without_auth_or_build(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text("existing")
        with patch.object(runtime, "checked_run") as run:
            runtime.recover("bitwarden", self.manifest)
        run.assert_not_called()
        self.assertEqual(self.target.read_text(), "existing")

    def test_credential_created_during_fetch_is_preserved(self):
        def fetch(argv, **kwargs):
            result = self.fake_docker(argv, **kwargs)
            if argv[1] == "run":
                self.target.parent.mkdir(parents=True)
                self.target.write_text("another-login")
            return result
        self.restore(fetch)
        self.assertEqual(self.target.read_text(), "another-login")

    def test_bad_payload_never_installed_and_staging_removed(self):
        self.payload = b'{"unexpected":"fake-secret"}'
        with self.assertRaises(runtime.RecoveryError):
            self.restore()
        self.assertFalse(self.target.exists())
        self.assertFalse(self.staging.exists())

    def test_cancel_never_installs_and_cleans_staging(self):
        def cancel(argv, **kwargs):
            result = self.fake_docker(argv, **kwargs)
            if argv[1] == "run":
                raise SystemExit(130)
            return result
        with self.assertRaises(SystemExit) as error:
            self.restore(cancel)
        self.assertEqual(error.exception.code, 130)
        self.assertFalse(self.target.exists())
        self.assertFalse(self.staging.exists())

    def test_unsafe_paths_rejected_before_docker(self):
        for path in (self.home / ".bashrc", self.target.parent / "auth.json", self.target.parent.parent / "other/.credentials.json"):
            with self.subTest(path=path):
                self.mapping["entries"][0]["credentialPath"] = str(path)
                self.write_mapping()
                with patch.object(runtime, "checked_run") as run, self.assertRaises(runtime.RecoveryError):
                    runtime.recover("bitwarden", self.manifest)
                run.assert_not_called()

    def test_symlink_parent_rejected(self):
        root = self.home / ".claude-profiles"
        root.symlink_to(self.home, target_is_directory=True)
        with patch.object(runtime, "checked_run") as run, self.assertRaises(runtime.RecoveryError):
            runtime.recover("bitwarden", self.manifest)
        run.assert_not_called()

    def test_mapping_requires_owner_only_regular_file(self):
        self.manifest.chmod(0o644)
        with self.assertRaises(runtime.RecoveryError):
            runtime.private_file(self.manifest)
        link = self.home / "link"
        link.symlink_to(self.manifest)
        with self.assertRaises(runtime.RecoveryError):
            runtime.private_file(link)

    def test_remote_context_rejected_before_authentication(self):
        with patch.dict(os.environ, {"DOCKER_HOST": "ssh://remote"}), patch.object(runtime, "checked_run") as run, self.assertRaises(runtime.RecoveryError):
            runtime.docker_ready()
        run.assert_not_called()

    def test_context_overrides_docker_host(self):
        with patch.dict(os.environ, {"DOCKER_HOST": "ssh://remote", "DOCKER_CONTEXT": "local"}), patch.object(runtime, "checked_run", return_value=subprocess.CompletedProcess([], 0, stdout="unix:///run/user/1000/docker.sock")) as run:
            runtime.docker_ready()
        self.assertIn("local", run.call_args_list[0].args[0])

    def test_invalid_sources_and_duplicate_profiles_rejected(self):
        for mutate in (lambda data: data.update(server="http://vault.test"),
                       lambda data: data["entries"][0].update(itemId="search-name"),
                       lambda data: data["entries"].append(copy.deepcopy(data["entries"][0]))):
            data = copy.deepcopy(self.mapping)
            mutate(data)
            with self.assertRaises(runtime.RecoveryError):
                runtime.validate_mapping(data, "bitwarden")

    def test_bitwarden_login_unlock_fetch_and_logout_keep_secrets_off_args(self):
        output = self.home / "output"
        output.mkdir()
        calls = []
        def vault(argv, env, limit=runtime.MAX_BYTES):
            calls.append((argv, env.copy()))
            if argv[1] == "unlock":
                return b"fake-session"
            if argv[1:3] == ["get", "notes"]:
                return self.payload
            return b""
        with patch.object(runtime, "secret_input", side_effect=["fake-id", "fake-api-secret", "fake-password"]), patch.object(runtime, "vault_command", side_effect=vault), patch.object(runtime.Path, "mkdir"), patch.object(runtime.subprocess, "run") as logout:
            runtime.container_restore(self.mapping, output)
        self.assertEqual([call[0][1] for call in calls], ["config", "login", "unlock", "sync", "get"])
        self.assertEqual(calls[-1][1]["BW_SESSION"], "fake-session")
        self.assertFalse(any("fake-password" in argv or "fake-api-secret" in argv for argv, _ in calls))
        self.assertNotIn("BW_PASSWORD", calls[-1][1])
        self.assertNotIn("BW_CLIENTSECRET", calls[-1][1])
        self.assertEqual(logout.call_args.args[0], ["bw", "logout"])
        self.assertEqual((output / "0.json").read_bytes(), self.payload)

    def test_onepassword_fetches_only_mapped_field(self):
        mapping = json.loads((ROOT / "config/ai-credential-1password.example.json").read_text())
        output = self.home / "output"
        output.mkdir()
        payload = b'{"OPENAI_API_KEY":"fake-key"}'
        with patch.object(runtime, "secret_input", return_value="fake-service-token"), patch.object(runtime, "vault_command", return_value=payload) as vault, patch.object(runtime.Path, "mkdir"):
            runtime.container_restore(mapping, output)
        self.assertEqual(vault.call_args.args[0], ["op", "read", "--no-newline", mapping["entries"][0]["secretReference"]])
        self.assertEqual(vault.call_args.args[1]["OP_SERVICE_ACCOUNT_TOKEN"], "fake-service-token")
        self.assertEqual((output / "0.json").read_bytes(), payload)

    def test_payload_size_and_invalid_json_rejected(self):
        for payload in (b"x" * (runtime.MAX_BYTES + 1), b"[]", b"{", b'{"claudeAiOauth":false}'):
            with self.assertRaises((runtime.RecoveryError, ValueError)):
                runtime.valid_payload("claude", payload)


class SelectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "credential-container").mkdir()
        for name in ("setup-credential-recovery.py", "setup_prompts.py", "profile_credentials.py"):
            shutil.copy(ROOT / "scripts" / name, self.repo / "scripts")
        (self.repo / "credential-container/credential_recovery.py").write_text("class RecoveryError(Exception): pass\ndef docker_ready(): pass\n")
        (self.repo / "scripts/recover-vault-credentials.py").write_text("import os,sys\nwith open(os.environ['TEST_LOG'],'a') as f: f.write(' '.join(sys.argv[1:])+'\\n')\nsys.exit(int(os.environ.get('TEST_EXIT','0')))\n")
        (self.repo / "scripts/backup-ai-profile-credentials-to-kv.sh").write_text('#!/bin/bash\nprintf "azure %s\\n" "$WORKBENCHES_AZURE_CLI_RUNTIME" >> "$TEST_LOG"\nexit "${TEST_EXIT:-0}"\n')
        self.config = self.home / ".config/workbenches"
        self.config.mkdir(parents=True)
        for _, _, filename in selector.SERVICES:
            (self.config / filename).write_text("{}")
        self.log = self.home / "actions"
        self.env = {**os.environ, "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / ".config"), "TEST_LOG": str(self.log)}
        for key in ("WORKBENCHES_SKIP_CREDENTIAL_RECOVERY", "AI_CREDENTIAL_KV_MANIFEST"):
            self.env.pop(key, None)

    def run_selector(self, answers=(), interactive=True, **env):
        argv = [sys.executable, str(self.repo / "scripts/setup-credential-recovery.py"), "--interactive" if interactive else "--apply-existing"]
        if not interactive:
            result = subprocess.run(argv, capture_output=True, text=True, env={**self.env, **env})
            return result.returncode, result.stdout + result.stderr
        master, slave = pty.openpty()
        process = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, env={**self.env, **env})
        os.close(slave)
        output, count = b"", 0
        deadline = time.monotonic() + 10
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    output += data
                    if output.endswith(b": ") and count < len(answers):
                        os.write(master, answers[count])
                        count += 1
                if process.poll() is not None:
                    break
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.fail(output.decode())
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            os.close(master)
        return process.returncode, output.decode()

    def test_decline_does_not_contact_vault(self):
        self.assertEqual(self.run_selector([b"n\n"])[0], 0)
        self.assertFalse(self.log.exists())

    def test_multiple_services_selected_and_mapping_paths_used(self):
        status, output = self.run_selector([b"y\n", b"2,4\n"])
        self.assertEqual(status, 0, output)
        actions = self.log.read_text()
        self.assertIn("--service bitwarden", actions)
        self.assertIn("--service 1password", actions)
        self.assertIn("ai-credential-bitwarden.json", actions)
        self.assertIn("ai-credential-1password.json", actions)

    def test_q_at_each_prompt_cancels_before_recovery(self):
        for answers in ([b"Q\n"], [b"y\n", b"q\n"], [b"y\n", b"1I\n", b"Q\n"]):
            with self.subTest(answers=answers):
                self.assertEqual(self.run_selector(answers)[0], 130)
                self.assertFalse(self.log.exists())

    def test_closed_input_cancels(self):
        self.assertEqual(self.run_selector([b"\x04"])[0], 130)
        self.assertFalse(self.log.exists())

    def test_unsupported_store_uses_native_signin(self):
        self.assertEqual(self.run_selector([b"y\n", b"0\n"])[0], 0)
        self.assertFalse(self.log.exists())

    def test_invalid_service_choice_reprompts(self):
        self.assertEqual(self.run_selector([b"y\n", b"99\n", b"0\n"])[0], 0)
        self.assertFalse(self.log.exists())

    def test_noninteractive_keeps_existing_azure_mapping_and_runtime(self):
        self.assertEqual(self.run_selector(interactive=False)[0], 0)
        self.assertEqual(self.log.read_text().strip(), "azure auto")

    def test_interactive_azure_recovery_forces_container(self):
        status, output = self.run_selector([b"y\n", b"1\n", b"\n"])
        self.assertEqual(status, 0, output)
        self.assertEqual(self.log.read_text().strip(), "azure docker")

    def test_explicit_skip_avoids_prompt_or_vault_access(self):
        self.assertEqual(self.run_selector(interactive=False, WORKBENCHES_SKIP_CREDENTIAL_RECOVERY="1")[0], 0)
        self.assertFalse(self.log.exists())

    def test_vault_cancellation_propagates(self):
        self.assertEqual(self.run_selector(interactive=False, TEST_EXIT="130")[0], 130)


if __name__ == "__main__":
    unittest.main()
