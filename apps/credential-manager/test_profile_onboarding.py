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
            expected = {"claude": 2, "openai": 2, "gemini": 1, "grok": 1, "glm": 1}
            for provider, count in expected.items():
                data = json.loads((output / f"{provider}-profiles.json").read_text())
                self.assertEqual(len(data["profiles"]), count)
            state = output / "ai-profile-onboarding.json"
            self.assertEqual(state.stat().st_mode & 0o777, 0o600)
            self.assertIn("Existing standard provider credential homes were preserved", result.stdout)

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

    def test_declined_consent_writes_nothing(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary:
            home = pathlib.Path(temporary)
            result, output = self.run_onboarding(home, {"consent": False})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
