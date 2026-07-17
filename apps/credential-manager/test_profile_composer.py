import importlib.util
import json
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[2] / "scripts" / "compose-ai-profiles.py"
SPEC = importlib.util.spec_from_file_location("compose_ai_profiles", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ProfileComposerTest(unittest.TestCase):
    def write_source(self, root, owner_type, owner_id, profiles):
        source = root / owner_id / "ai"
        source.mkdir(parents=True)
        (source / "source.json").write_text(
            json.dumps(
                {
                    "version": 1,
                    "kind": "workbenches-ai-profile-source",
                    "owner": {"type": owner_type, "id": owner_id},
                    "profiles": profiles,
                }
            ),
            encoding="utf-8",
        )
        return source

    def test_tenant_grant_and_personal_source_are_composed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            tenant = self.write_source(
                root,
                "tenant",
                "opensoft",
                {
                    "claude": [
                        {"name": "team-001", "email": "team-001@example.com", "family": "company"},
                        {"name": "hidden-001", "email": "hidden@example.com", "family": "company"},
                    ],
                    "openai": [],
                },
            )
            grant = tenant / "grants" / "users"
            grant.mkdir(parents=True)
            (grant / "brettheap.json").write_text(
                json.dumps(
                    {
                        "version": 1,
                        "user": "brettheap",
                        "profiles": {"claude": ["team-*"], "openai": []},
                    }
                ),
                encoding="utf-8",
            )
            personal = self.write_source(
                root,
                "user",
                "brettheap",
                {
                    "claude": [
                        {"name": "personal-1", "email": "brett@example.com", "family": "personal"}
                    ],
                    "openai": [],
                },
            )

            result = MODULE.compose([str(tenant), str(personal)], "brettheap")

            self.assertEqual([profile["name"] for profile in result["claude"]], ["team-001", "personal-1"])

    def test_duplicate_alias_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            personal = self.write_source(
                root,
                "user",
                "brettheap",
                {
                    "claude": [
                        {"name": "one", "email": "one@example.com", "family": "personal", "aliases": ["shared"]},
                        {"name": "two", "email": "two@example.com", "family": "personal", "aliases": ["shared"]},
                    ],
                    "openai": [],
                },
            )

            with self.assertRaises(MODULE.ProfileError):
                MODULE.compose([str(personal)], "brettheap")


if __name__ == "__main__":
    unittest.main()
