import json
import os
import pathlib
import subprocess
import tempfile
import unittest


REPO = pathlib.Path(__file__).parents[2]


class ProviderProfilesTest(unittest.TestCase):
    def test_provider_launchers_isolate_state_and_resolve_aliases(self):
        cases = {
            "gemini": ("pgemini", "GEMINI_BIN", "GEMINI_CLI_HOME"),
            "grok": ("pgrok", "GROK_BIN", "GROK_HOME"),
            "glm": ("pglm", "OPENCODE_BIN", "XDG_DATA_HOME"),
        }
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            root = pathlib.Path(temporary)
            home = root / "home"
            config = home / ".config/workbenches"
            config.mkdir(parents=True)
            fake = root / "fake-cli"
            fake.write_text(
                "#!/bin/sh\n"
                'printf "%s\\n" "${GEMINI_CLI_HOME:-${GROK_HOME:-${XDG_DATA_HOME:-}}}" > "$CAPTURE"\n'
            )
            fake.chmod(0o755)

            for provider, (launcher, binary_env, expected_env) in cases.items():
                manifest = config / f"{provider}-profiles.json"
                manifest.write_text(
                    json.dumps(
                        {
                            "version": 1,
                            "profiles": [
                                {
                                    "name": "team-001",
                                    "email": "team-001@example.com",
                                    "family": "company",
                                    "aliases": ["team001"],
                                }
                            ],
                        }
                    )
                )
                env = {
                    **os.environ,
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    binary_env: str(fake),
                    "CAPTURE": str(root / f"{provider}.capture"),
                }
                subprocess.run(
                    [
                        str(REPO / "scripts/setup-provider-profiles.sh"),
                        "--provider",
                        provider,
                        "--manifest",
                        str(manifest),
                    ],
                    env=env,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                subprocess.run(
                    [str(home / ".local/bin" / launcher), "team001"],
                    env=env,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                profile = home / f".{provider}-profiles/profiles/team-001"
                expected = profile if expected_env != "XDG_DATA_HOME" else profile / "xdg/data"
                self.assertEqual((root / f"{provider}.capture").read_text().strip(), str(expected))
                self.assertEqual(profile.stat().st_mode & 0o777, 0o700, provider)
                self.assertEqual(
                    (profile / ".profile.json").stat().st_mode & 0o777,
                    0o600,
                    provider,
                )


if __name__ == "__main__":
    unittest.main()
