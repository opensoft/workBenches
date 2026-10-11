#!/usr/bin/env python3
"""GitHub clone transport tests; no network or workstation SSH keys are used."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
BOOTSTRAP = REPO / "bootstrap.sh"


class GitTransportTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        self.dest = self.root / "clone"
        self.env = {"HOME": str(self.root), "PATH": f"{self.bin}:/usr/bin:/bin",
                    "TEST_LOG": str(self.log)}
        git = self.bin / "git"
        git.write_text(f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
args = sys.argv[1:]
config_args = []
while args[:1] == ["-c"]:
    config_args.extend(args[:2]); args = args[2:]
with open(os.environ["TEST_LOG"], "a") as log:
    log.write(json.dumps({"args":args,"config":config_args,"ssh":os.environ.get("GIT_SSH_COMMAND"),"prompt":os.environ.get("GIT_TERMINAL_PROMPT")}) + "\\n")
if args[:3] == ["config", "--get", "core.sshCommand"]: sys.exit(1)
if args[:1] == ["ls-remote"]: sys.exit(int(os.environ.get("TEST_PROBE_STATUS", "0")))
if args[:1] == ["clone"]:
    url, dest = args[-2:]
    if url.startswith("git@github.com:") and os.environ.get("TEST_SSH_CLONE_STATUS"):
        sys.exit(int(os.environ["TEST_SSH_CLONE_STATUS"]))
    if url.startswith("https://github.com/") and os.environ.get("TEST_HTTPS_FAIL"): sys.exit(128)
    path = pathlib.Path(dest)
    if path.exists() and any(path.iterdir()): sys.exit(128)
    path.mkdir(parents=True, exist_ok=True)
    (path / "setup.sh").write_text('#!/bin/bash\\nprintf setup > "$HOME/setup-ran"\\n')
    sys.exit(0)
if "--get-regexp" in args:
    print("submodule.devBenches.pyBench.url https://github.com/opensoft/pyBench.git")
    print("submodule.sysBenches.cloudBench.url https://github.com/opensoft/cloudBench.git")
    sys.exit(0)
if "submodule" in args:
    if os.environ.get("TEST_SUBMODULE_FAIL") and not any("insteadOf" in arg for arg in config_args): sys.exit(1)
    sys.exit(0)
sys.exit(2)
''')
        git.chmod(0o755)

    def run_bootstrap(self, *args):
        result = subprocess.run(["bash", str(BOOTSTRAP), *map(str, args)], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertTrue(self.log.exists(), result.stderr)
        self.calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.clones = [call for call in self.calls if call["args"][:1] == ["clone"]]
        return result

    def clone(self, url="https://github.com/opensoft/workBenches.git", *options):
        return self.run_bootstrap("--clone", url, self.dest, *options)

    def test_working_ssh_preferred_even_for_https_input(self):
        self.assertEqual(self.clone().returncode, 0)
        self.assertEqual(self.clones[0]["args"][-2], "git@github.com:opensoft/workBenches.git")
        probe = next(call for call in self.calls if call["args"][0] == "ls-remote")
        self.assertEqual(probe["args"][-1], "HEAD")
        for option in ("BatchMode=yes", "ConnectTimeout=5", "StrictHostKeyChecking=yes"):
            self.assertIn(option, probe["ssh"])
        self.assertEqual(probe["prompt"], "0")

    def test_missing_ssh_access_falls_back_to_https(self):
        self.env["TEST_PROBE_STATUS"] = "128"
        self.assertEqual(self.clone("git@github.com:opensoft/workBenches.git").returncode, 0)
        self.assertEqual(self.clones[0]["args"][-2], "https://github.com/opensoft/workBenches.git")
        self.assertEqual(self.clones[0]["prompt"], "0")
        self.assertIn("url.https://github.com/opensoft/workBenches.git.insteadOf=https://github.com/opensoft/workBenches.git", self.clones[0]["config"])

    def test_ssh_clone_failure_retries_https_with_clone_options(self):
        self.env["TEST_SSH_CLONE_STATUS"] = "128"
        self.assertEqual(self.clone("ssh://git@github.com/opensoft/workBenches", "--depth", "1").returncode, 0)
        self.assertEqual(len(self.clones), 2)
        self.assertTrue(self.clones[1]["args"][-2].startswith("https://github.com/"))
        self.assertEqual(self.clones[1]["args"][1:3], ["--depth", "1"])

    def test_custom_ssh_command_is_preserved(self):
        self.env["GIT_SSH_COMMAND"] = "ssh -F /custom/config"
        self.assertEqual(self.clone().returncode, 0)
        self.assertTrue(self.clones[0]["ssh"].startswith("ssh -F /custom/config "))

    def test_other_hosts_are_unchanged(self):
        url = "https://git.example.org/org/repo.git"
        self.assertEqual(self.clone(url).returncode, 0)
        self.assertEqual(self.clones[0]["args"][-2], url)
        self.assertFalse(any(call["args"][0] == "ls-remote" for call in self.calls))

    def test_cancelled_probe_does_not_clone(self):
        self.env["TEST_PROBE_STATUS"] = "130"
        self.assertEqual(self.clone().returncode, 130)
        self.assertEqual(self.clones, [])

    def test_cancelled_clone_does_not_retry(self):
        self.env["TEST_SSH_CLONE_STATUS"] = "130"
        self.assertEqual(self.clone().returncode, 130)
        self.assertEqual(len(self.clones), 1)

    def test_private_https_failure_is_reported(self):
        self.env.update(TEST_PROBE_STATUS="128", TEST_HTTPS_FAIL="1")
        self.assertEqual(self.clone().returncode, 128)
        self.assertFalse(self.dest.exists())

    def test_existing_destination_is_preserved(self):
        self.dest.mkdir()
        marker = self.dest / "user-file"
        marker.write_text("keep")
        self.assertNotEqual(self.clone().returncode, 0)
        self.assertEqual(marker.read_text(), "keep")

    def test_bootstrap_can_clone_and_run_setup(self):
        self.assertEqual(self.run_bootstrap("--directory", self.dest, "--branch", "review", "--setup").returncode, 0)
        self.assertIn("--branch", self.clones[0]["args"])
        self.assertEqual((self.root / "setup-ran").read_text(), "setup")

    def test_submodules_prefer_ssh_and_use_command_local_settings(self):
        self.assertEqual(self.run_bootstrap("--submodules", self.root).returncode, 0)
        update = next(call for call in self.calls if "submodule" in call["args"])
        self.assertIn("submodule.devBenches.pyBench.url=git@github.com:opensoft/pyBench.git", update["config"])
        self.assertFalse(any("--global" in call["args"] for call in self.calls))

    def test_submodule_failure_retries_over_https(self):
        self.env["TEST_SUBMODULE_FAIL"] = "1"
        self.assertEqual(self.run_bootstrap("--submodules", self.root).returncode, 0)
        updates = [call for call in self.calls if "submodule" in call["args"]]
        self.assertEqual(len(updates), 2)
        self.assertIn("url.https://github.com/.insteadOf=git@github.com:", updates[1]["config"])

    def test_real_git_initializes_pinned_submodule_without_ssh(self):
        # Map HTTPS to a local repository: exercise Git's real submodule/config
        # behavior without contacting GitHub or reading workstation SSH state.
        source = self.root / "source"
        checkout = self.root / "parent"
        source.mkdir(); checkout.mkdir()
        env = dict(self.env, PATH="/usr/bin:/bin", GIT_CONFIG_GLOBAL="/dev/null",
                   GIT_CONFIG_SYSTEM="/dev/null", GIT_SSH_COMMAND="false",
                   GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                   GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
        git = shutil.which("git")
        def run_git(root, *args):
            return subprocess.run([git, "-C", str(root), *args], env=env,
                                  check=True, capture_output=True, text=True).stdout.strip()
        run_git(source, "init", "-q")
        (source / "fixture").write_text("content")
        run_git(source, "add", "fixture")
        run_git(source, "commit", "-qm", "fixture")
        commit = run_git(source, "rev-parse", "HEAD")
        run_git(checkout, "init", "-q")
        (checkout / ".gitmodules").write_text('[submodule "bench"]\npath = devBenches/testBench\nurl = https://github.com/example/bench.git\n')
        run_git(checkout, "add", ".gitmodules")
        run_git(checkout, "update-index", "--add", "--cacheinfo", f"160000,{commit},devBenches/testBench")
        env.update(GIT_CONFIG_COUNT="2", GIT_CONFIG_KEY_0="url." + source.as_uri() + ".insteadOf",
                   GIT_CONFIG_VALUE_0="https://github.com/example/bench.git",
                   GIT_CONFIG_KEY_1="protocol.file.allow", GIT_CONFIG_VALUE_1="always")
        result = subprocess.run(["bash", str(BOOTSTRAP), "--submodules", str(checkout)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(run_git(checkout / "devBenches/testBench", "rev-parse", "HEAD"), commit)


if __name__ == "__main__":
    unittest.main(verbosity=2)
