#!/usr/bin/env python3
"""Regression tests for bench service selection and missing/disabled init."""

import importlib.util
import contextlib
import io
from pathlib import Path
import unittest
from unittest.mock import patch


path = Path(__file__).resolve().parents[1] / "scripts" / "check-bench-init.py"
spec = importlib.util.spec_from_file_location("check_bench_init", path)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class BenchInitTests(unittest.TestCase):
    def test_jsonc_preserves_strings_and_accepts_comments_and_trailing_commas(self):
        text = r'''{
            // comment
            "url": "https://example.invalid/a/*literal*/",
            "note": "value, }",
            "dockerComposeFile": ["docker-compose.yml",],
        }'''
        config = checker.jsonc(text)
        self.assertEqual(config["url"], "https://example.invalid/a/*literal*/")
        self.assertEqual(config["note"], "value, }")
        self.assertEqual(config["dockerComposeFile"], ["docker-compose.yml"])

    def test_custom_selector_cannot_hide_behind_standard_sibling(self):
        files = [Path(".devcontainer/devcontainer.json"),
                 Path(".devcontainer/docker-compose.yml"),
                 Path(".devcontainer/custom-compose.yml")]
        text = '{"dockerComposeFile": ["docker-compose.yml", "custom-compose.yml"]}'
        with patch.object(Path, "read_text", return_value=text):
            with self.assertRaises(ValueError):
                checker.validate_declared_compose_files(Path(".").resolve(), files)

    def test_ignored_generated_selector_remains_outside_source_checks(self):
        files = [Path(".devcontainer/devcontainer.json"), Path(".devcontainer/docker-compose.yml")]
        text = '{"dockerComposeFile": ["docker-compose.yml", "docker-compose.amd-rocm.generated.yml"]}'
        result = checker.subprocess.CompletedProcess([], 0, "", "")
        with patch.object(Path, "read_text", return_value=text), \
             patch.object(checker.subprocess, "run", return_value=result) as run:
            checker.validate_declared_compose_files(Path(".").resolve(), files)
        self.assertIn("check-ignore", run.call_args.args[0])
        self.assertIs(run.call_args.kwargs["shell"], False)

    def test_empty_selectors_are_rejected(self):
        files = [Path(".devcontainer/devcontainer.json"), Path(".devcontainer/docker-compose.yml")]
        for value in ([], "", [""], None):
            with self.subTest(value=value), \
                 patch.object(Path, "read_text", return_value=checker.json.dumps({"dockerComposeFile": value})):
                with self.assertRaises(ValueError):
                    checker.validate_declared_compose_files(Path(".").resolve(), files)

    def test_ignored_selector_requires_an_audited_tracked_base(self):
        files = [Path(".devcontainer/devcontainer.json"), Path("other/docker-compose.yml")]
        text = '{"dockerComposeFile": ["docker-compose.override.yml"]}'
        result = checker.subprocess.CompletedProcess([], 0, "", "")
        with patch.object(Path, "read_text", return_value=text), \
             patch.object(checker.subprocess, "run", return_value=result):
            with self.assertRaises(ValueError):
                checker.validate_declared_compose_files(Path(".").resolve(), files)

    def test_missing_and_disabled_are_rejected(self):
        for setting in ({}, {"init": False}, {"init": "true"}, {"init": 1}):
            with self.subTest(setting=setting):
                config = {"services": {"py-bench": {"image": "py-bench:${USER:-brett}", **setting}}}
                self.assertEqual(checker.init_errors(config), ["py-bench"])

    def test_all_bench_images_and_workers_are_selected(self):
        names = ("py", "cpp", "dotnet", "go", "java", "rust", "php", "flutter",
                 "frappe", "cloud", "ops", "m365", "gentec", "sim")
        services = {name: {"image": f"{name}-bench:brett", "init": True} for name in names}
        services["worker-default"] = {"image": "frappe-bench:brett", "init": False}
        self.assertEqual(checker.init_errors({"services": services}), ["worker-default"])
        self.assertEqual(len(list(checker.bench_services({"services": services}))), 15)

    def test_base_test_stacks_and_flutter_app_are_selected(self):
        for image in ("workbench-base", "dev-bench-base", "sys-bench-base", "bio-bench-base"):
            self.assertEqual(checker.init_errors({"services": {"test": {"image": f"{image}:latest"}}}), ["test"])
        self.assertEqual(checker.init_errors({"services": {"app": {"build": {"context": "."}}}}), ["app"])
        self.assertEqual(checker.init_errors({"services": {"gentec_bench": {"build": {"args": {"BASE_IMAGE": "gentec-bench:latest"}}}}}), ["gentec_bench"])

    def test_unrelated_infrastructure_is_not_selected(self):
        config = {"services": {"db": {"image": "mariadb:11"}, "cache": {"image": "redis:7"},
                               "nginx": {"image": "nginx:alpine"}, "adb-service": {"build": "."}}}
        self.assertEqual(list(checker.bench_services(config)), [])

    def test_tracked_overlays_are_checked_with_their_base(self):
        files = [Path(".devcontainer") / name for name in (
            "docker-compose.yml", "docker-compose.override.yml", "docker-compose.wslg.yml",
            "docker-compose.usermap.yml", "docker-compose.override.example.yml",
        )]
        chains = list(checker.configurations(files))
        self.assertEqual(len(chains), 5)
        self.assertIn([files[3]], chains)
        self.assertIn([files[0], files[3]], chains)

    def test_enabled_service_passes(self):
        self.assertEqual(checker.init_errors({"services": {"cloud-bench": {"image": "cloud-bench:brett", "init": True}}}), [])

    def test_yaml_and_modern_compose_names_are_checked(self):
        files = [Path(".devcontainer") / name for name in (
            "compose.yaml", "compose.override.yml", "docker-compose.yaml",
            "docker-compose.usermap.yaml", "docker-compose-with-adb.yaml",
        )]
        chains = list(checker.configurations(files))
        for index in (0, 2, 3, 4):
            self.assertIn([files[index]], chains)
        self.assertIn([files[0], files[1]], chains)
        self.assertIn([files[2], files[3]], chains)

    def test_parser_failure_is_redacted_and_env_loading_disabled(self):
        result = checker.subprocess.CompletedProcess([], 1, "fixture-secret", "fixture-secret")
        output = io.StringIO()
        with patch.object(checker, "tracked_files", return_value=[Path("docker-compose.yml")]), \
             patch.object(checker.shutil, "copyfile"), \
             patch.object(checker.subprocess, "run", return_value=result) as run, \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertGreater(checker.check_root(Path(".")), 0)
        self.assertNotIn("fixture-secret", output.getvalue())
        command = run.call_args.args[0]
        self.assertIsInstance(command, list)
        self.assertEqual(command[:2], ["docker", "compose"])
        self.assertIs(run.call_args.kwargs["shell"], False)
        self.assertEqual(command[command.index("--env-file") + 1], checker.os.devnull)
        self.assertEqual(command[command.index("--profile") + 1], "*")
        for flag in ("--no-env-resolution", "--no-path-resolution"):
            self.assertIn(flag, command)
        self.assertEqual(run.call_args.kwargs["env"]["USER"], "bench-check")
        self.assertNotIn("ANTHROPIC_API_KEY", run.call_args.kwargs["env"])

    def test_empty_checkout_fails(self):
        with patch.object(checker, "tracked_files", return_value=[]), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertGreater(checker.check_root(Path(".")), 0)

    def test_empty_configuration_cannot_hide_behind_valid_configuration(self):
        files = [Path("valid/docker-compose.yml"), Path("missing/docker-compose.yml")]
        results = [checker.subprocess.CompletedProcess([], 0, checker.json.dumps(config), "")
                   for config in (
                       {"services": {"py-bench": {"image": "py-bench:brett", "init": True}}},
                       {"services": {"cache": {"image": "redis:7"}}},
                   )]
        output = io.StringIO()
        with patch.object(checker, "tracked_files", return_value=files), \
             patch.object(checker.shutil, "copyfile"), \
             patch.object(checker.subprocess, "run", side_effect=results), \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(checker.check_root(Path(".")), 1)
        self.assertIn("missing/docker-compose.yml: no bench services found", output.getvalue())

    def test_dedicated_infrastructure_stack_is_not_a_bench_variant(self):
        files = [Path("docker-compose.yml"), Path("infrastructure/docker-compose.yml")]
        results = [checker.subprocess.CompletedProcess([], 0, checker.json.dumps(config), "")
                   for config in (
                       {"services": {"frappe": {"image": "frappe-bench:brett", "init": True}}},
                       {"services": {"cache": {"image": "redis:7"}, "db": {"image": "mariadb:11"}}},
                   )]
        with patch.object(checker, "tracked_files", return_value=files), \
             patch.object(checker.shutil, "copyfile"), \
             patch.object(checker.subprocess, "run", side_effect=results), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(checker.check_root(Path(".")), 0)


if __name__ == "__main__":
    unittest.main()
