import json
import os
import pathlib
import subprocess
import tempfile
import unittest


REPO = pathlib.Path(__file__).parents[2]


class ClaudeNestedProfilesTest(unittest.TestCase):
    def test_setup_copies_flat_profile_and_launcher_uses_nested_path(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            root = pathlib.Path(temporary)
            home = root / "home"
            config = home / ".config/workbenches"
            config.mkdir(parents=True)
            manifest = config / "claude-profiles.json"
            manifest.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "profiles": [
                            {
                                "name": "team-001",
                                "profilePath": "example-company/team/team-001",
                                "email": "team-001@example.com",
                                "family": "example-company",
                                "aliases": ["team001"],
                            }
                        ],
                    }
                )
            )

            flat = home / ".claude-profiles/profiles/team-001"
            flat.mkdir(parents=True)
            credential = {"testCredential": "preserved"}
            (flat / ".credentials.json").write_text(json.dumps(credential))
            (flat / ".credentials.json").chmod(0o600)

            env = {
                **os.environ,
                "HOME": str(home),
                "XDG_CONFIG_HOME": str(home / ".config"),
                "CLAUDE_PROFILES_HOME": str(home / ".claude-profiles"),
            }
            subprocess.run(
                [str(REPO / "scripts/setup-claude-profiles.sh"), "--manifest", str(manifest)],
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )

            nested = home / ".claude-profiles/profiles/example-company/team/team-001"
            self.assertTrue(flat.is_dir())
            self.assertTrue(nested.is_dir())
            self.assertEqual(json.loads((nested / ".credentials.json").read_text()), credential)
            self.assertEqual(
                json.loads((nested / ".profile.json").read_text())["profilePath"],
                "example-company/team/team-001",
            )
            self.assertEqual(
                (nested / "projects").resolve(),
                home / ".claude-profiles/state/example-company/projects",
            )
            for category in ("team", "max", "xfactor"):
                self.assertTrue(
                    (home / f".claude-profiles/profiles/example-company/{category}").is_dir()
                )

            retained_group = home / ".claude-profiles/profiles/team/team-001"
            retained_group.mkdir(parents=True)
            (retained_group / ".profile.json").write_text(
                json.dumps(
                    {
                        "name": "team-001",
                        "profilePath": "team/team-001",
                        "email": "team-001@example.com",
                        "family": "example-company",
                        "aliases": ["team001"],
                    }
                )
            )

            capture = root / "capture"
            fake_claude = root / "claude"
            fake_claude.write_text(
                '#!/bin/sh\nprintf "%s" "$CLAUDE_CONFIG_DIR" > "$CAPTURE"\n'
            )
            fake_claude.chmod(0o755)
            env.update({"CLAUDE_BIN": str(fake_claude), "CAPTURE": str(capture)})
            subprocess.run(
                [str(REPO / "base-image/files/claude-profile"), "status", "team001"],
                env=env,
                check=True,
            )
            self.assertEqual(capture.read_text(), str(nested))

            env["CLAUDE_PROFILES_MANIFEST"] = str(root / "missing-manifest.json")
            subprocess.run(
                [str(REPO / "base-image/files/claude-profile"), "status", "team001"],
                env=env,
                check=True,
            )
            self.assertEqual(capture.read_text(), str(nested))


if __name__ == "__main__":
    unittest.main()
