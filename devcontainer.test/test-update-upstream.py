#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""`update-upstream.py apply`: the default-branch path and the release path.

opensoft/workBenches#153. openRepoShape v1.0.1 is a commit that `main` never
carries, cut on `release/v1.0`, and `apply` refused it. `--tag` and
`--branch` now take such a commit as a NAMED RELEASE. These tests pin both
halves: the new path accepts exactly a tag that peels to `--at` on a branch
that carries it and refuses every other case by name, and the old
default-branch path is unchanged, its refusal included word for word.

THE REAL TOOL, RUN AS A COMMAND, AGAINST A THROWAWAY PIN. A stub `gh` is
first on PATH. It answers from a per-test table of GitHub REST bodies and
evaluates the tool's own `-q` expression with `jq -r`, as `gh -q` does, so a
wrong jq expression in the tool fails here too. It logs every call, so a test
can say which endpoints a path consulted. A stub `curl` always fails,
`GH_TOKEN` is bogus and `GH_CONFIG_DIR` is empty: no test can reach GitHub.

Needs python3, git (the tool asks it for its own path) and jq.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "devBenches/base-image/update-upstream.py"
REPO = "test/upstream"


def sha1(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


OLD = sha1("the commit the pin names now")
NEW = sha1("the release commit")
OTHER = sha1("some other commit")
TAG_OBJECT = sha1("the annotated tag object")
INNER_TAG_OBJECT = sha1("a tag object the outer one tags")
TREE = sha1("a tree")
BLOB = sha1("a blob")
#: The one compare the release path asks: the base spelled as a BRANCH
#: ref, because `compare` takes a tag or a commit as its base too.
RELEASE_COMPARE = f"repos/{REPO}/compare/refs/heads/release/v1.0...{NEW}"

OLD_TOOL = b"#!/bin/sh\necho old\n"
NEW_TOOL = b"#!/bin/sh\necho new\n"
OLD_TEMPLATE = b"kind: old\n"
NEW_TEMPLATE = b"kind: new\n"

PIN_TEMPLATE = """schema_version: 1
kind: pinned_copy_manifest

# A throwaway pin for devcontainer.test/test-update-upstream.py.

digest_algorithm: sha256

sources:
  - id: demo
    source_repository: test/upstream
    materialization: copied
    revision_kind: commit
    commit: "{commit}"
    vendor_dir: files/demo
    files:
      - path: tool
        sha256: "{tool}"
        mode: "100755"
      - path: templates/x.yaml
        sha256: "{template}"
        mode: "100644"
"""

OLD_PIN = PIN_TEMPLATE.format(commit=OLD, tool=sha256(OLD_TOOL),
                              template=sha256(OLD_TEMPLATE))
#: What `apply` must leave behind on either path: the commit and both digests
#: moved, and NOT ONE other byte, so no key was added to record a tag.
NEW_PIN = PIN_TEMPLATE.format(commit=NEW, tool=sha256(NEW_TOOL),
                              template=sha256(NEW_TEMPLATE))

STUB_GH = r'''#!{python}
import json, os, subprocess, sys
argv = sys.argv[1:]
with open(os.environ["FAKE_GH_LOG"], "a", encoding="utf-8") as log:
    log.write(json.dumps(argv) + "\n")
if len(argv) < 2 or argv[0] != "api":
    sys.stderr.write("stub gh: only `gh api <endpoint>` is answered\n")
    sys.exit(4)
endpoint, rest = argv[1], argv[2:]
query, raw = None, False
while rest:
    flag = rest.pop(0)
    if flag == "-q":
        query = rest.pop(0)
    elif flag == "-H":
        raw = rest.pop(0) == "Accept: application/vnd.github.raw"
    else:
        sys.stderr.write("stub gh: unexpected argument %r\n" % flag)
        sys.exit(4)
with open(os.environ["FAKE_GH_TABLE"], encoding="utf-8") as handle:
    table = json.load(handle)
if endpoint not in table:
    # What the real `gh api` does on a 404: the body on stdout, the status
    # on stderr, exit 1.
    sys.stdout.write('{"message":"Not Found","status":"404"}')
    sys.stderr.write("gh: Not Found (HTTP 404)\n")
    sys.exit(1)
answer = table[endpoint]
if raw:
    sys.stdout.write(answer["raw"])
    sys.exit(0)
body = json.dumps(answer["json"])
if query is None:
    sys.stdout.write(body)
    sys.exit(0)
done = subprocess.run(["jq", "-r", query], input=body, text=True,
                      capture_output=True)
if done.returncode != 0:
    sys.stderr.write("stub gh: jq failed on %r: %s" % (query, done.stderr))
    sys.exit(1)
sys.stdout.write(done.stdout)
'''


class ApplyTestCase(unittest.TestCase):
    """One throwaway pin, one stubbed upstream, per test."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="update-upstream-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        stubs = self.base / "bin"
        stubs.mkdir()
        gh = stubs / "gh"
        gh.write_text(STUB_GH.replace("{python}", sys.executable),
                      encoding="utf-8")
        gh.chmod(0o755)
        curl = stubs / "curl"
        curl.write_text("#!/bin/sh\nexit 22\n", encoding="utf-8")
        curl.chmod(0o755)
        gh_config = self.base / "gh-config"
        gh_config.mkdir()
        self.log = self.base / "gh-calls.jsonl"
        self.log.write_text("", encoding="utf-8")
        self.table_path = self.base / "upstream.json"
        self.env = {
            "PATH": f"{stubs}{os.pathsep}{os.environ.get('PATH', '')}",
            "HOME": str(self.base),
            "GH_TOKEN": "bogus-token-for-test-update-upstream",
            "GH_CONFIG_DIR": str(gh_config),
            "FAKE_GH_TABLE": str(self.table_path),
            "FAKE_GH_LOG": str(self.log),
            "PYTHONIOENCODING": "utf-8",
            "PYTHONDONTWRITEBYTECODE": "1",
        }

        pin_dir = self.base / "pin"
        self.vendor = pin_dir / "files/demo"
        (self.vendor / "templates").mkdir(parents=True)
        (self.vendor / "tool").write_bytes(OLD_TOOL)
        (self.vendor / "tool").chmod(0o755)
        (self.vendor / "templates/x.yaml").write_bytes(OLD_TEMPLATE)
        (self.vendor / "templates/x.yaml").chmod(0o644)
        self.pin = pin_dir / "upstream-pin.yaml"
        self.pin.write_text(OLD_PIN, encoding="utf-8")

        # The upstream every test starts from: NEW is the release commit,
        # tagged v1.0.1 (annotated) and the tip of release/v1.0, and NOT on
        # main, which has diverged from it -- openRepoShape v1.0.1's shape.
        self.table = {
            f"repos/{REPO}": {"json": {"default_branch": "main"}},
            f"repos/{REPO}/compare/main...{NEW}":
                {"json": {"status": "diverged"}},
            RELEASE_COMPARE:
                {"json": {"status": "identical"}},
            f"repos/{REPO}/git/ref/tags/v1.0.1":
                {"json": {"ref": "refs/tags/v1.0.1",
                          "object": {"type": "tag", "sha": TAG_OBJECT}}},
            f"repos/{REPO}/git/tags/{TAG_OBJECT}":
                {"json": {"sha": TAG_OBJECT, "tag": "v1.0.1",
                          "object": {"type": "commit", "sha": NEW}}},
            f"repos/{REPO}/git/trees/{NEW}?recursive=1":
                {"json": {"sha": TREE, "tree": [
                    {"path": "templates", "mode": "040000", "type": "tree"},
                    {"path": "templates/x.yaml", "mode": "100644",
                     "type": "blob"},
                    {"path": "tool", "mode": "100755", "type": "blob"}]}},
            f"repos/{REPO}/contents/tool?ref={NEW}":
                {"raw": NEW_TOOL.decode("utf-8")},
            f"repos/{REPO}/contents/templates/x.yaml?ref={NEW}":
                {"raw": NEW_TEMPLATE.decode("utf-8")},
        }

    # -- running ------------------------------------------------------------

    def run_tool(self, *argv):
        self.table_path.write_text(json.dumps(self.table), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(TOOL), *argv], cwd=self.base, env=self.env,
            capture_output=True, text=True, encoding="utf-8", check=False)

    def apply(self, *extra, yes=True):
        argv = ["apply", "--pin", str(self.pin), "--source", "demo",
                "--at", NEW, *extra]
        if yes:
            argv.append("--yes")
        return self.run_tool(*argv)

    def release(self, yes=True):
        return self.apply("--tag", "v1.0.1", "--branch", "release/v1.0",
                          yes=yes)

    def endpoints(self):
        return [json.loads(line)[1]
                for line in self.log.read_text(encoding="utf-8").splitlines()]

    # -- assertions ---------------------------------------------------------

    def assertRefused(self, done, code):
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertTrue(done.stderr.startswith(f"REFUSED {code}:"),
                        f"wanted REFUSED {code}, got:\n{done.stderr}")

    def assertNothingWritten(self):
        self.assertEqual(self.pin.read_text(encoding="utf-8"), OLD_PIN)
        self.assertEqual((self.vendor / "tool").read_bytes(), OLD_TOOL)
        self.assertEqual((self.vendor / "templates/x.yaml").read_bytes(),
                         OLD_TEMPLATE)

    def assertApplied(self, done):
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.pin.read_text(encoding="utf-8"), NEW_PIN)
        self.assertEqual((self.vendor / "tool").read_bytes(), NEW_TOOL)
        self.assertEqual((self.vendor / "tool").stat().st_mode & 0o777,
                         0o755)
        self.assertEqual((self.vendor / "templates/x.yaml").read_bytes(),
                         NEW_TEMPLATE)
        self.assertEqual(
            (self.vendor / "templates/x.yaml").stat().st_mode & 0o777, 0o644)
        # The pin it wrote is one its own offline `check` accepts.
        check = self.run_tool("check", "--pin", str(self.pin))
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

    def assertNoGitHubCall(self):
        self.assertEqual(self.endpoints(), [])


class DefaultBranchPathTests(ApplyTestCase):
    """Without --tag/--branch, `apply` is exactly what it was."""

    def test_default_branch_path_takes_a_commit_main_carries(self):
        self.table[f"repos/{REPO}/compare/main...{NEW}"] = {
            "json": {"status": "behind"}}
        done = self.apply()
        self.assertApplied(done)
        self.assertIn(f"target      {NEW[:12]} (on main)\n", done.stdout)
        calls = self.endpoints()
        self.assertEqual(calls[:2], [f"repos/{REPO}",
                                     f"repos/{REPO}/compare/main...{NEW}"])
        self.assertFalse([c for c in calls if "/git/ref/" in c
                          or "/git/tags/" in c], calls)

    def test_default_branch_path_refuses_a_diverged_commit_word_for_word(self):
        done = self.apply()
        self.assertEqual(done.returncode, 2)
        self.assertEqual(done.stdout, "")
        self.assertEqual(
            done.stderr,
            f"REFUSED upstream-not-on-default-branch: {NEW[:12]} is not on "
            f"test/upstream's main; `compare` says 'diverged'.\n"
            "A pin the rest of the world cannot fetch is a pin nobody can "
            "reproduce — land\nthe change first, then pin the commit main "
            "carries.\n")
        self.assertNothingWritten()
        self.assertEqual(self.endpoints(),
                         [f"repos/{REPO}",
                          f"repos/{REPO}/compare/main...{NEW}"])


class ReleasePathTests(ApplyTestCase):
    """--tag T --branch B: a commit off the default branch, as a release."""

    def test_release_path_takes_an_annotated_tag_on_the_named_branch(self):
        done = self.release()
        self.assertApplied(done)
        self.assertIn(f"target      {NEW[:12]} (tag v1.0.1, on release/v1.0)\n",
                      done.stdout)
        calls = self.endpoints()
        self.assertEqual(calls[:3], [
            f"repos/{REPO}/git/ref/tags/v1.0.1",
            f"repos/{REPO}/git/tags/{TAG_OBJECT}",
            RELEASE_COMPARE])
        # The default-branch rule is not consulted at all on this path.
        self.assertNotIn(f"repos/{REPO}", calls)
        self.assertNotIn(f"repos/{REPO}/compare/main...{NEW}", calls)

    def test_release_path_takes_a_lightweight_tag(self):
        self.table[f"repos/{REPO}/git/ref/tags/v1.0.1"] = {
            "json": {"ref": "refs/tags/v1.0.1",
                     "object": {"type": "commit", "sha": NEW}}}
        del self.table[f"repos/{REPO}/git/tags/{TAG_OBJECT}"]
        done = self.release()
        self.assertApplied(done)
        self.assertFalse([c for c in self.endpoints() if "/git/tags/" in c])

    def test_release_path_peels_a_tag_of_a_tag(self):
        self.table[f"repos/{REPO}/git/tags/{TAG_OBJECT}"] = {
            "json": {"object": {"type": "tag", "sha": INNER_TAG_OBJECT}}}
        self.table[f"repos/{REPO}/git/tags/{INNER_TAG_OBJECT}"] = {
            "json": {"object": {"type": "commit", "sha": NEW}}}
        self.assertApplied(self.release())

    def test_release_path_rehearsal_writes_nothing(self):
        done = self.release(yes=False)
        self.assertRefused(done, "upstream-declined")
        self.assertIn("  take      tool  ", done.stdout)
        self.assertIn(f"  re-pin    commit {OLD[:12]} -> {NEW[:12]}\n",
                      done.stdout)
        self.assertNothingWritten()

    def test_no_such_tag_is_refused(self):
        del self.table[f"repos/{REPO}/git/ref/tags/v1.0.1"]
        done = self.release()
        self.assertRefused(done, "upstream-tag-not-found")
        self.assertIn("test/upstream has no tag 'v1.0.1'", done.stderr)
        self.assertNothingWritten()
        self.assertEqual(self.endpoints(),
                         [f"repos/{REPO}/git/ref/tags/v1.0.1"])

    def test_a_tag_peeling_to_another_commit_is_refused(self):
        cases = {
            "annotated": {
                f"repos/{REPO}/git/tags/{TAG_OBJECT}":
                    {"json": {"object": {"type": "commit", "sha": OTHER}}}},
            "lightweight": {
                f"repos/{REPO}/git/ref/tags/v1.0.1":
                    {"json": {"ref": "refs/tags/v1.0.1",
                              "object": {"type": "commit", "sha": OTHER}}}},
        }
        base = dict(self.table)
        for name, changes in cases.items():
            with self.subTest(name):
                self.table = {**base, **changes}
                self.log.write_text("", encoding="utf-8")
                done = self.release()
                self.assertRefused(done, "upstream-tag-elsewhere")
                self.assertIn(f"peels to {OTHER},\nnot to --at {NEW}",
                              done.stderr)
                self.assertNothingWritten()
                self.assertFalse([c for c in self.endpoints()
                                  if "/compare/" in c or "/contents/" in c])

    def test_an_answer_naming_another_ref_or_no_object_is_refused(self):
        answers = {
            "another ref": {"ref": "refs/tags/v1.0.10",
                            "object": {"type": "commit", "sha": NEW}},
            "no object sha": {"ref": "refs/tags/v1.0.1",
                              "object": {"type": "commit", "sha": "HEAD"}},
        }
        for name, answer in answers.items():
            with self.subTest(name):
                self.table[f"repos/{REPO}/git/ref/tags/v1.0.1"] = {
                    "json": answer}
                done = self.release()
                self.assertRefused(done, "upstream-tag-unreadable")
                self.assertNothingWritten()

    def test_a_tag_naming_a_tree_is_refused(self):
        self.table[f"repos/{REPO}/git/tags/{TAG_OBJECT}"] = {
            "json": {"object": {"type": "tree", "sha": TREE}}}
        done = self.release()
        self.assertRefused(done, "upstream-tag-not-a-commit")
        self.assertNothingWritten()

    def test_a_tagged_commit_on_no_branch_is_refused(self):
        # `ahead`: the commit is only reachable from the tag; `diverged`: it
        # sits on some other line of history than the named branch.
        for status in ("ahead", "diverged"):
            with self.subTest(status):
                self.table[RELEASE_COMPARE] = {
                    "json": {"status": status}}
                done = self.release()
                self.assertRefused(done, "upstream-not-on-branch")
                self.assertIn(f"`compare` says '{status}'", done.stderr)
                self.assertNothingWritten()
                self.assertFalse([c for c in self.endpoints()
                                  if "/contents/" in c])

    def test_a_branch_the_upstream_does_not_have_is_refused(self):
        del self.table[RELEASE_COMPARE]
        done = self.release()
        self.assertRefused(done, "upstream-branch-unreadable")
        self.assertIn("HTTP 404", done.stderr)
        self.assertNothingWritten()

    def test_a_tag_or_commit_named_as_the_branch_is_refused(self):
        # What GitHub really answers (RV154 on #154): `compare` resolves a
        # tag or a commit as its base as readily as a branch, so a bare
        # `compare/v1.0.1...NEW` or `compare/NEW...NEW` says `identical`, and
        # `--branch` naming the tag itself would pass a tag on a stray
        # commit. Only `refs/heads/<name>` is asked, which neither is.
        self.table[f"repos/{REPO}/compare/v1.0.1...{NEW}"] = {
            "json": {"status": "identical"}}
        self.table[f"repos/{REPO}/compare/{NEW}...{NEW}"] = {
            "json": {"status": "identical"}}
        for branch in ("v1.0.1", NEW):
            with self.subTest(branch=branch[:12]):
                self.log.write_text("", encoding="utf-8")
                done = self.apply("--tag", "v1.0.1", "--branch", branch)
                self.assertRefused(done, "upstream-branch-unreadable")
                self.assertNothingWritten()
                self.assertIn(
                    f"repos/{REPO}/compare/refs/heads/{branch}...{NEW}",
                    self.endpoints())

    def test_a_tag_object_that_tags_itself_is_refused_after_the_limit(self):
        self.table[f"repos/{REPO}/git/tags/{TAG_OBJECT}"] = {
            "json": {"object": {"type": "tag", "sha": TAG_OBJECT}}}
        done = self.release()
        self.assertRefused(done, "upstream-tag-unreadable")
        self.assertIn("more than 10 annotated tag objects deep", done.stderr)
        self.assertNothingWritten()
        peels = [c for c in self.endpoints() if "/git/tags/" in c]
        self.assertEqual(len(peels), 10, peels)
        self.assertFalse([c for c in self.endpoints() if "/compare/" in c])

    def test_a_tag_whose_ref_names_a_blob_is_refused(self):
        self.table[f"repos/{REPO}/git/ref/tags/v1.0.1"] = {
            "json": {"ref": "refs/tags/v1.0.1",
                     "object": {"type": "blob", "sha": BLOB}}}
        done = self.release()
        self.assertRefused(done, "upstream-tag-not-a-commit")
        self.assertIn("names a blob", done.stderr)
        self.assertNothingWritten()

    def test_no_gh_on_path_is_refused_on_both_paths(self):
        # PATH holds nothing at all: no `gh` (and no `git`, which the tool
        # only asks for its own path and does without).
        empty = self.base / "empty-bin"
        empty.mkdir()
        self.env["PATH"] = str(empty)
        for name, extra in (("release path", ("--tag", "v1.0.1",
                                               "--branch", "release/v1.0")),
                            ("default-branch path", ())):
            with self.subTest(name):
                done = self.apply(*extra)
                self.assertRefused(done, "upstream-no-gh")
                self.assertNothingWritten()
        self.assertNoGitHubCall()

    def test_tag_and_branch_come_together_or_not_at_all(self):
        done = self.apply("--tag", "v1.0.1")
        self.assertRefused(done, "upstream-tag-without-branch")
        done = self.apply("--branch", "release/v1.0")
        self.assertRefused(done, "upstream-branch-without-tag")
        self.assertNothingWritten()
        self.assertNoGitHubCall()

    def test_names_that_would_bend_the_request_are_refused_unasked(self):
        bad = ["", "../v1", "v1..2", "v1?per_page=1", "v1#x", "-v1", "v 1",
               "v1.lock", "release//v1", "release/", ".hidden", "v1.",
               "a" * 256, "v1\nREFUSED forged"]
        for flag in ("--tag", "--branch"):
            for value in bad:
                with self.subTest(flag=flag, value=value[:20]):
                    other = ("--branch=release/v1.0" if flag == "--tag"
                             else "--tag=v1.0.1")
                    done = self.apply(f"{flag}={value}", other)
                    self.assertRefused(done, "upstream-bad-ref")
                    self.assertNotIn("forged", done.stderr)
                    self.assertNotIn("a" * 256, done.stderr)
        self.assertNothingWritten()
        self.assertNoGitHubCall()


if __name__ == "__main__":
    unittest.main(verbosity=2)
