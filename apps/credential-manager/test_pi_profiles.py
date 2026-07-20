import json
import os
import pathlib
import subprocess
import tempfile
import unittest


REPO = pathlib.Path(__file__).parents[2]


class PiProfilesTest(unittest.TestCase):
    def test_composition_setup_alias_and_isolation_are_idempotent(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            root = pathlib.Path(temporary)
            home = root / "home"
            config = home / ".config/workbenches"
            config.mkdir(parents=True)
            profile = {
                "name": "team-001",
                "email": "team-001@example.com",
                "family": "company",
                "aliases": ["team001"],
            }
            for provider in ("claude", "openai", "gemini", "grok", "glm"):
                (config / f"{provider}-profiles.json").write_text(
                    json.dumps({"version": 1, "profiles": [profile]}), encoding="utf-8"
                )
            pi_manifest = config / "pi-profiles.json"
            subprocess.run(
                [
                    str(REPO / "scripts/compose-pi-profiles.py"),
                    "--config-dir", str(config), "--output", str(pi_manifest),
                ], check=True, capture_output=True, text=True,
            )
            fake_pi = root / "pi"
            fake_pi.write_text('#!/bin/sh\nprintf "%s" "$PI_CODING_AGENT_DIR" > "$CAPTURE"\n')
            fake_pi.chmod(0o755)
            env = {
                **os.environ,
                "HOME": str(home),
                "XDG_CONFIG_HOME": str(home / ".config"),
                "PI_BIN": str(fake_pi),
                "CAPTURE": str(root / "capture"),
            }
            setup = REPO / "scripts/setup-pi-profiles.sh"
            for _ in range(2):
                subprocess.run([str(setup), "--manifest", str(pi_manifest)], env=env, check=True, capture_output=True, text=True)
            launcher = home / ".local/bin/ppi"
            subprocess.run([str(launcher), "team001"], env=env, check=True)
            expected = home / ".pi-profiles/profiles/team-001/agent"
            self.assertEqual((root / "capture").read_text(), str(expected))
            self.assertEqual(expected.stat().st_mode & 0o777, 0o700)
            self.assertEqual((expected / "settings.json").stat().st_mode & 0o777, 0o600)
            self.assertFalse((expected / "auth.json").exists())
            self.assertEqual(
                json.loads(pi_manifest.read_text())["profiles"][0]["providers"],
                ["claude", "openai", "gemini", "grok", "glm"],
            )

    def test_composition_rejects_cross_provider_identity_mismatch(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            config = pathlib.Path(temporary)
            base = {"name": "team-001", "email": "one@example.com", "family": "company", "aliases": []}
            (config / "claude-profiles.json").write_text(json.dumps({"version": 1, "profiles": [base]}))
            changed = {**base, "email": "two@example.com"}
            (config / "openai-profiles.json").write_text(json.dumps({"version": 1, "profiles": [changed]}))
            result = subprocess.run(
                [str(REPO / "scripts/compose-pi-profiles.py"), "--config-dir", str(config), "--check"],
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("identity mismatch", result.stderr)

    def test_pi_escrow_round_trip_uses_separate_harness_secret(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            root = pathlib.Path(temporary)
            repo = root / "registry"
            (repo / ".git").mkdir(parents=True)
            (repo / "ai").mkdir()
            (repo / "ai/source.json").write_text(json.dumps({
                "profiles": {"claude": [{"name": "team-001"}]}
            }))
            home = root / "home"
            auth = home / ".pi-profiles/profiles/team-001/agent/auth.json"
            auth.parent.mkdir(parents=True)
            expected = {"anthropic": {"type": "oauth", "access": "a", "refresh": "r", "expires": 123}}
            auth.write_text(json.dumps(expected))
            auth.chmod(0o600)
            identity = root / "recovery.agekey"
            identity.write_text("test")
            identity.chmod(0o600)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            sops = bin_dir / "sops"
            sops.write_text(
                "#!/bin/sh\n"
                "last=''\nfor arg in \"$@\"; do last=$arg; done\ncat \"$last\"\n"
            )
            sops.chmod(0o755)
            env = {**os.environ, "HOME": str(home), "PATH": f"{bin_dir}:{os.environ['PATH']}"}
            command = [
                str(REPO / "scripts/pi-credential-escrow"),
                "backup", "--repo", str(repo), "--profile", "team-001",
                "--identity-file", str(identity),
            ]
            subprocess.run(command, env=env, check=True, capture_output=True, text=True)
            secret = repo / "ai/secrets/pi/team-001.auth.sops.yaml"
            self.assertTrue(secret.exists())
            auth.unlink()
            subprocess.run(
                [command[0], "restore", *command[2:]], env=env, check=True, capture_output=True, text=True
            )
            self.assertEqual(json.loads(auth.read_text()), expected)


if __name__ == "__main__":
    unittest.main()
