#!/usr/bin/env python3
"""Regression tests for bench service selection and missing/disabled init."""

import importlib.util
from pathlib import Path
import unittest


path = Path(__file__).resolve().parents[1] / "scripts" / "check-bench-init.py"
spec = importlib.util.spec_from_file_location("check_bench_init", path)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class BenchInitTests(unittest.TestCase):
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
        self.assertEqual(len(chains), 4)
        self.assertTrue(all(chain[0] == files[0] for chain in chains))

    def test_enabled_service_passes(self):
        self.assertEqual(checker.init_errors({"services": {"cloud-bench": {"image": "cloud-bench:brett", "init": True}}}), [])


if __name__ == "__main__":
    unittest.main()
