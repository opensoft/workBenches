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
                "family": "example-company",
                "profilePath": "example-company/team/team-001",
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
            claude_home = home / ".claude-profiles/profiles/example-company/team/team-001"
            claude_home.mkdir(parents=True)
            (claude_home / ".profile.json").write_text(
                json.dumps(profile), encoding="utf-8"
            )
            standard_auth = home / ".pi/agent/auth.json"
            standard_auth.parent.mkdir(parents=True)
            standard_auth.write_text('{"standard":"credential"}', encoding="utf-8")
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
            expected = home / ".pi-profiles/profiles/example-company/team/team-001/agent"
            self.assertEqual((root / "capture").read_text(), str(expected))
            self.assertEqual(expected.stat().st_mode & 0o777, 0o700)
            self.assertEqual((expected / "settings.json").stat().st_mode & 0o777, 0o600)
            self.assertFalse((expected / "auth.json").exists())
            self.assertEqual(
                standard_auth.read_text(encoding="utf-8"), '{"standard":"credential"}'
            )
            self.assertEqual(
                json.loads(pi_manifest.read_text())["profiles"][0]["providers"],
                ["claude", "openai", "gemini", "grok", "glm"],
            )
            settings = json.loads((expected / "settings.json").read_text())
            self.assertEqual(settings["defaultProvider"], "pi-claude-cli")
            self.assertEqual(settings["defaultModel"], "claude-fable-5")
            self.assertIn("npm:@ramarivera/pi-claude-cli@0.3.1", settings["packages"])
            for category in ("team", "max", "xfactor"):
                self.assertTrue(
                    (home / f".pi-profiles/profiles/example-company/{category}").is_dir()
                )
            self.assertTrue(
                (home / ".pi-profiles/state/example-company/sessions").is_dir()
            )
            self.assertEqual(
                (home / ".pi-profiles/state").stat().st_mode & 0o777, 0o700
            )

            env_capture = root / "env-capture"
            fake_pi.write_text(
                '#!/bin/sh\nprintf "%s\n%s\n" "$PI_CODING_AGENT_DIR" "$CLAUDE_CONFIG_DIR" > "$ENV_CAPTURE"\n'
            )
            env["ENV_CAPTURE"] = str(env_capture)
            subprocess.run([str(launcher), "team001"], env=env, check=True)
            self.assertEqual(env_capture.read_text().splitlines(), [str(expected), str(claude_home)])

            payload = json.loads(pi_manifest.read_text(encoding="utf-8"))
            payload["profiles"][0]["providers"] = ["openai"]
            pi_manifest.write_text(json.dumps(payload), encoding="utf-8")
            subprocess.run(
                [str(setup), "--manifest", str(pi_manifest)],
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            settings = json.loads((expected / "settings.json").read_text())
            self.assertNotIn("defaultProvider", settings)
            self.assertNotIn("defaultModel", settings)
            self.assertNotIn("npm:@ramarivera/pi-claude-cli@0.3.1", settings["packages"])

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

    def test_composition_rejects_cross_profile_alias_collisions(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            config = pathlib.Path(temporary)
            first = {
                "name": "alpha",
                "email": "alpha@example.com",
                "family": "company",
                "aliases": ["shared"],
            }
            second = {
                "name": "zeta",
                "email": "zeta@example.com",
                "family": "company",
                "aliases": ["SHARED"],
            }
            (config / "claude-profiles.json").write_text(
                json.dumps({"version": 1, "profiles": [first]}), encoding="utf-8"
            )
            (config / "openai-profiles.json").write_text(
                json.dumps({"version": 1, "profiles": [second]}), encoding="utf-8"
            )
            result = subprocess.run(
                [
                    str(REPO / "scripts/compose-pi-profiles.py"),
                    "--config-dir",
                    str(config),
                    "--check",
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ambiguous Pi profile", result.stderr)

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
            profile_dir = home / ".pi-profiles/profiles/company/team/team-001"
            auth = profile_dir / "agent/auth.json"
            auth.parent.mkdir(parents=True)
            (profile_dir / ".profile.json").write_text(
                json.dumps({"name": "team-001", "profilePath": "company/team/team-001"}),
                encoding="utf-8",
            )
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

            unsafe = subprocess.run(
                [
                    command[0],
                    "check",
                    "--repo",
                    str(repo),
                    "--profile",
                    "../escape",
                    "--identity-file",
                    str(identity),
                ],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(unsafe.returncode, 2)
            self.assertIn("Unsafe Pi profile name", unsafe.stderr)

    def test_launcher_list_tolerates_missing_manifest_and_profile_root(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            home = pathlib.Path(temporary) / "home"
            home.mkdir()
            env = {
                **os.environ,
                "HOME": str(home),
                "PI_PROFILES_MANIFEST": str(home / "missing.json"),
            }
            result = subprocess.run(
                [str(REPO / "base-image/files/pi-profile"), "list"],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
