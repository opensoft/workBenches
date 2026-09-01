import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).parents[2] / "scripts" / "consolidate-codex-state.py"
SPEC = importlib.util.spec_from_file_location("consolidate_codex_state", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class CodexStateConsolidationTest(unittest.TestCase):
    def test_family_comes_from_profile_metadata(self):
        self.assertEqual(
            MODULE.family_for(
                {"name": "custom", "email": "person@unrelated.example", "family": "tenant-a"}
            ),
            "tenant-a",
        )

    def test_missing_or_unsafe_family_is_rejected(self):
        for family in (None, "", "../escape", "Uppercase"):
            with self.subTest(family=family), self.assertRaises(ValueError):
                MODULE.family_for({"name": "profile", "family": family})


if __name__ == "__main__":
    unittest.main()
