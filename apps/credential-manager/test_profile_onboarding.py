import json
import os
import pathlib
import subprocess
import tempfile
import unittest


REPO = pathlib.Path(__file__).parents[2]
SCRIPT = REPO / "scripts/onboard-ai-profiles.py"


class ProfileOnboardingTest(unittest.TestCase):
    def run_onboarding(self, home: pathlib.Path, answers: dict):
        answer_file = home / "answers.json"
        answer_file.write_text(json.dumps(answers))
        output = home / ".config/workbenches"
        result = subprocess.run(
            [str(SCRIPT), "--answers", str(answer_file), "--output-dir", str(output)],
            env={**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config")},
            text=True,
            capture_output=True,
        )
        return result, output

    def test_manual_company_and_personal_profiles_cover_selected_providers(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            home = pathlib.Path(temporary)
            answers = {
                "consent": True,
                "githubUser": "engineer",
                "companies": [
                    {
                        "name": "Example Company",
                        "email": "engineer@example.com",
                        "githubOrg": "example-company",
                        "providers": ["all"],
                        "registry": "manual",
                    },
                    {
                        "name": "Second Company",
                        "email": "engineer@second.example",
                        "githubOrg": "second-company",
                        "providers": ["claude", "openai"],
                        "registry": "manual",
                    }
                ],
                "personal": {
                    "githubOrg": "engineer",
                    "registry": "manual",
                    "accounts": [
                        {
                            "email": "person@example.net",
                            "providers": ["claude", "gpt"],
                        }
                    ],
                },
            }

            result, output = self.run_onboarding(home, answers)

            self.assertEqual(result.returncode, 0, result.stderr)
            expected = {"claude": 3, "openai": 3, "gemini": 1, "grok": 1, "glm": 1}
            for provider, count in expected.items():
                data = json.loads((output / f"{provider}-profiles.json").read_text())
                self.assertEqual(len(data["profiles"]), count)
                self.assertEqual(
                    data["families"],
                    ["example-company", "second-company", "personal"],
                )
                company = next(
                    profile for profile in data["profiles"]
                    if profile["email"] == "engineer@example.com"
                )
                self.assertEqual(company["family"], "example-company")
                self.assertEqual(
                    company["profilePath"],
                    "example-company/xfactor/work-example-company",
                )
                personal = [
                    profile for profile in data["profiles"]
                    if profile["email"] == "person@example.net"
                ]
                if personal:
                    self.assertEqual(personal[0]["family"], "personal")
                    self.assertEqual(
                        personal[0]["profilePath"],
                        f"personal/{personal[0]['name']}",
                    )
            state = output / "ai-profile-onboarding.json"
            self.assertEqual(state.stat().st_mode & 0o777, 0o600)
            self.assertIn("Existing standard provider credential homes were preserved", result.stdout)

            setup = subprocess.run(
                [str(REPO / "scripts/setup-ai-profiles.sh"), "--apply-existing"],
                env={
                    **os.environ,
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                },
                text=True,
                capture_output=True,
            )
            self.assertEqual(setup.returncode, 0, setup.stderr)
            roots = (
                ".claude-profiles",
                ".chatgpt-profiles",
                ".pi-profiles",
                ".gemini-profiles",
                ".grok-profiles",
                ".glm-profiles",
            )
            for root_name in roots:
                root = home / root_name
                self.assertTrue((root / "state/example-company").is_dir())
                self.assertTrue((root / "state/second-company").is_dir())
                self.assertTrue((root / "state/personal").is_dir())
                for company in ("example-company", "second-company"):
                    for category in ("team", "max", "xfactor"):
                        self.assertTrue(
                            (root / f"profiles/{company}/{category}").is_dir(),
                            f"{root_name} missing {company}/{category} scaffold",
                        )
                self.assertTrue((root / "profiles/personal").is_dir())

    def test_setup_composes_pi_profiles_from_a_partial_provider_inventory(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            home = pathlib.Path(temporary) / "home"
            config = home / ".config/workbenches"
            config.mkdir(parents=True)
            (config / "openai-profiles.json").write_text(
                json.dumps(
                    {
                        "version": 1,
                        "families": ["company"],
                        "profiles": [
                            {
                                "name": "work-chatgpt",
                                "email": "user@example.com",
                                "family": "company",
                                "aliases": [],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [str(REPO / "scripts/setup-ai-profiles.sh"), "--apply-existing"],
                env={
                    **os.environ,
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                },
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            pi_manifest = json.loads((config / "pi-profiles.json").read_text())
            self.assertEqual(
                [profile["name"] for profile in pi_manifest["profiles"]],
                ["work-chatgpt"],
            )

    def test_profile_launchers_list_cleanly_before_setup(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            home = pathlib.Path(temporary) / "home"
            home.mkdir()
            cases = (
                ("claude-profile", "CLAUDE_PROFILES_MANIFEST", "CLAUDE_PROFILES_HOME"),
                ("codex-profile", "CODEX_PROFILES_MANIFEST", "CODEX_PROFILES_HOME"),
            )
            for launcher, manifest_name, home_name in cases:
                with self.subTest(launcher=launcher):
                    env = {
                        **os.environ,
                        "HOME": str(home),
                        manifest_name: str(home / f"missing-{launcher}.json"),
                        home_name: str(home / f"missing-{launcher}-profiles"),
                    }
                    result = subprocess.run(
                        [str(REPO / "base-image/files" / launcher), "list"],
                        env=env,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "")

    def test_registry_sources_are_composed_with_user_grants(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            home = pathlib.Path(temporary)
            tenant = home / "company-registry/ai"
            personal = home / "personal-registry/ai"
            (tenant / "grants/users").mkdir(parents=True)
            personal.mkdir(parents=True)
            (tenant / "source.json").write_text(
                json.dumps(
                    {
                        "version": 1,
                        "kind": "workbenches-ai-profile-source",
                        "owner": {"type": "tenant", "id": "example-company"},
                        "profiles": {
                            "claude": [
                                {
                                    "name": "team-001",
                                    "email": "team-001@example.com",
                                    "family": "company",
                                }
                            ]
                        },
                    }
                )
            )
            (tenant / "grants/users/engineer.json").write_text(
                json.dumps(
                    {
                        "version": 1,
                        "user": "engineer",
                        "profiles": {"claude": ["team-*"]},
                    }
                )
            )
            (personal / "source.json").write_text(
                json.dumps(
                    {
                        "version": 1,
                        "kind": "workbenches-ai-profile-source",
                        "owner": {"type": "user", "id": "engineer"},
                        "profiles": {
                            "openai": [
                                {
                                    "name": "personal-chatgpt",
                                    "email": "person@example.net",
                                    "family": "personal",
                                }
                            ]
                        },
                    }
                )
            )
            answers = {
                "consent": True,
                "githubUser": "engineer",
                "companies": [
                    {
                        "name": "Example Company",
                        "email": "engineer@example.com",
                        "githubOrg": "example-company",
                        "registry": str(tenant.parent),
                    }
                ],
                "personal": {
                    "githubOrg": "engineer",
                    "registry": str(personal.parent),
                    "accounts": [{"email": "person@example.net", "providers": ["openai"]}],
                },
            }

            result, output = self.run_onboarding(home, answers)

            self.assertEqual(result.returncode, 0, result.stderr)
            claude = json.loads((output / "claude-profiles.json").read_text())
            openai = json.loads((output / "openai-profiles.json").read_text())
            self.assertEqual([item["name"] for item in claude["profiles"]], ["team-001"])
            self.assertEqual([item["name"] for item in openai["profiles"]], ["personal-chatgpt"])
            self.assertEqual(claude["profiles"][0]["family"], "example-company")
            self.assertEqual(
                claude["profiles"][0]["profilePath"],
                "example-company/team/team-001",
            )
            self.assertEqual(openai["profiles"][0]["family"], "personal")
            self.assertEqual(
                openai["profiles"][0]["profilePath"],
                "personal/personal-chatgpt",
            )

    def test_declined_consent_writes_nothing(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            home = pathlib.Path(temporary)
            result, output = self.run_onboarding(home, {"consent": False})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
