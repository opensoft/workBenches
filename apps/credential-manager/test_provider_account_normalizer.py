import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[2] / "scripts" / "normalize-ai-provider-accounts.py"
SPEC = importlib.util.spec_from_file_location("normalize_ai_provider_accounts", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ProviderAccountNormalizerTest(unittest.TestCase):
    def test_normalizes_account_and_truthful_escrow_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            ai = root / "ai"
            ai.mkdir()
            source = ai / "source.json"
            source.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "kind": "workbenches-ai-profile-source",
                        "owner": {"type": "tenant", "id": "example"},
                        "profiles": {
                            "claude": [
                                {
                                    "name": "team-001",
                                    "email": "team-001@example.com",
                                    "family": "team",
                                }
                            ]
                        },
                    }
                )
            )

            normalized = MODULE.normalize(source)
            profile = normalized["profiles"]["claude"][0]
            self.assertEqual(normalized["credentialContractVersion"], 1)
            self.assertEqual(profile["accountId"], "example.claude.team-001.account")
            self.assertEqual(profile["authentication"]["type"], "subscription_oauth")
            self.assertEqual(profile["authentication"]["escrowStatus"], "not-escrowed")

            secret = root / profile["authentication"]["credentialRef"]
            secret.parent.mkdir(parents=True)
            secret.write_text("ciphertext")
            self.assertEqual(
                MODULE.normalize(source)["profiles"]["claude"][0]["authentication"]["escrowStatus"],
                "available",
            )


if __name__ == "__main__":
    unittest.main()
