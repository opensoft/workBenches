#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check, and re-take, the COPIES this repository holds of other repositories.

    python3 devBenches/base-image/update-upstream.py check [--source <id>]
    python3 devBenches/base-image/update-upstream.py apply --source <id> \
        --at <40-hex commit> --yes [--add <path>]... [--remove <path>]...
    python3 devBenches/base-image/update-upstream.py list

THE REFLECTION OF openRepoShape's `update-shape.py`, from the consumer's side
and with the same two verbs on purpose, so that a reader who knows one knows
this one. There, a project holds copies of the standard's validators and
re-syncs them; here, this repository holds copies of another repository's
COMMANDS, because the Docker build that installs them cannot reach github.com
reliably — the build network may route it through a VPN tunnel whose MTU breaks
TLS mid-transfer, which is why the Oh My Zsh plugins in the Dockerfile beside
these come from apt rather than from a clone. So the bytes live in this tree,
and their identity is `upstream-pin.yaml`.

WHAT `check` IS FOR. It is the run that says the copies still are what the pin
says they are, and it is wired into the two places that both matter: the
`regression` job of `.github/workflows/speckit-git-bash.yml`, and one scenario
of `devBenches/devcontainer.test/test-speckit-git-feature.sh` — which also runs
inside two containers that mount the workspace READ-ONLY. `check` therefore
writes nothing at all: no temporary file, no cache, no rewritten row, and it
needs no network.

IT NEVER OFFERS TO RECOMPUTE A ROW. Recomputing the digest of a file somebody
edited locally records the local edit as the upstream, which is the failure
`shape-pin.yaml`'s own header spends a paragraph forbidding. The two ways out
of a drift finding are to restore the bytes, or to take a new upstream commit
ON PURPOSE, and the finding names both.

EVERY FILE UNDER A VENDOR DIRECTORY IS A PINNED COPY, by construction. A file
there with no row is a finding as loud as a changed byte: it is bytes from
somewhere nobody recorded, sitting in the directory a reader trusts. So is a
copy that stopped being a regular file, or one that resolves out of the tree:
a link is followed by every read and write in the standard library, so neither
verb will touch a path whose `realpath` leaves the vendor directory.

A NEW SOURCE'S ROWS ARE HAND-WRITTEN, ONCE. The block — id, repository,
`vendor_dir` and one `- path: <upstream path>` per file, with no `sha256:` or
an empty one — is a human's decision. The first `apply` fetches those paths and
fills the digests in; `check` refuses an unfilled row, because a row with no
digest pins nothing. Both refusals name that sequence.

WHAT `apply` REFUSES, because a pin it cannot justify must not be recorded:

  * an `--at` that is not a full 40-character commit — a tag can be moved and
    a commit cannot;
  * a `--source` the pin does not name: a new source is a new block in that
    file and a human's decision, not a flag;
  * a commit that is NOT reachable from the source repository's default
    branch. openRepoShape squash-merges, so a commit on a pull-request branch
    is orphaned by the merge and a raw fetch of it 404s for the next person. A
    pin the rest of the world cannot fetch is a pin nobody can reproduce;
  * a fetch that failed for ANY file in the set: NOTHING is written, no
    vendored copy is replaced, and every file it could not get is named, with
    both forms it tried. All the bytes in hand before any one of them is
    placed — openRepoShape #82's F10 rule, for its reason;
  * a path whose mode, in the source repository's tree at that commit, is not
    an ordinary file's or one whose executable bit git tracks — a symlink, a
    submodule, a directory. A pin records copies of regular files, and a row
    naming one of those is not one;
  * a `--remove` set that would leave a source with NO rows. An empty `files:`
    block is a pin this tool's own `check` refuses, so `apply` must not be able
    to write one and then print `NEXT … check`; emptying a source means
    deleting its block, by hand and on purpose;
  * a repeated `--add` or `--remove` value, and a destination that is a link
    or resolves outside the vendor directory.

THE FETCH ORDER IS THE SHIMS'. `gh api …/contents/<path>?ref=<sha>` with
`Accept: application/vnd.github.raw` first, because it is authenticated and so
still works inside an organisation whose policy blocks
raw.githubusercontent.com; `curl` at the raw URL second, for a machine with no
`gh`. Each attempt is written to a temporary file and checked before its bytes
are used, so a half-written first attempt is never mistaken for a fetch.

MODES ARE PINNED FROM UPSTREAM, NOT GUESSED FROM BYTES. `apply` reads each
file's own mode from the source repository's git tree at the pinned commit —
one `git/trees/<commit>?recursive=1` call per source, cached for the run —
because a byte-content heuristic is lossy: a `.py` upstream ships 0644 does
not become a command by starting with `#!`, and nothing about the bytes says
whether upstream tracks the executable bit at all. The mode is recorded as an
OPTIONAL `mode:` field on a row, `"100755"` or `"100644"`; `apply` writes it
for every row it touches. A row written before this existed, or written by
hand for a new source, carries no `mode:` and stays valid — UNRECORDED, not
unchecked because broken — so the pin stays readable across the change.

`check` compares the working tree's own executable bit against a row's
`mode:` ONLY when the row has one; a mismatch is drift, exactly like a
changed byte, and the fix it names is `chmod`. The Dockerfile still chmods
0755 explicitly when it installs the commands into the image, unaffected by
any of this: that bit is about the image, and this one is about the copy
sitting in this tree.

STANDARD LIBRARY ONLY, and its own reader for the small subset of YAML the pin
is written in. Importing the upstream's `repo_shape.py` would give this checker
the one property it must not have: breaking on exactly the refactor it exists
to notice.

EXIT CODES
    check   0  every row matches its bytes (and its mode, where recorded)
            1  a FINDING: a copy drifted, went missing, stopped being a
               regular file, its recorded mode no longer matches, or a file
               under a vendor directory has no row
            2  a REFUSAL: no pin, an unreadable or malformed pin, an unknown
               --source
    apply   0  applied
            2  a REFUSAL, including the plan printed without --yes
    list    0  the sources; 2 if the pin cannot be read
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path


def _tool_path() -> str:
    """This tool's own path, relative to the repository root it sits in.

    Derived from `__file__` and `git rev-parse --show-toplevel` (run with
    `-C` at this file's own directory, so the caller's cwd never enters it),
    so every remediation line prints a path that is right to type from any
    cwd — not the one path this file happens to sit at in the repository
    `apply` was authored against. A reviewer's throwaway copy, a worktree,
    or a clone at a different name all get their OWN right answer.

    Falls back to the literal when there is nothing to ask: no `git` on
    PATH, this file not inside a checkout (`rev-parse` fails), or its
    directory outside the toplevel `rev-parse` names.
    """
    literal = "devBenches/base-image/" + Path(__file__).name
    here = Path(__file__).resolve()
    try:
        proc = subprocess.run(
            ["git", "-C", str(here.parent), "rev-parse", "--show-toplevel"],
            capture_output=True, check=False)
    except FileNotFoundError:
        return literal
    if proc.returncode != 0:
        return literal
    toplevel = proc.stdout.decode("utf-8", "replace").strip()
    if not toplevel:
        return literal
    try:
        return here.relative_to(Path(toplevel).resolve()).as_posix()
    except ValueError:
        return literal


TOOL = _tool_path()
DEFAULT_PIN = Path(__file__).resolve().parent / "upstream-pin.yaml"

SCHEMA_VERSION = "1"
KIND = "pinned_copy_manifest"
DIGEST_ALGORITHM = "sha256"

COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
#: The only two shapes `apply` ever writes: an ordinary file, or one whose
#: executable bit git tracks. Anything else a row's `mode:` might otherwise
#: hold is not a shape a vendored copy can be.
MODE_RE = re.compile(r"^(?:100644|100755)$")
SOURCE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")

#: Every key a `sources:` block must carry. `files:` is checked separately,
#: because it is a block and not a scalar.
SOURCE_KEYS = ("id", "source_repository", "materialization", "revision_kind",
               "commit", "vendor_dir")

GH_RAW_ACCEPT = "Accept: application/vnd.github.raw"


class Refusal(Exception):
    """A named refusal that names its own fix.

    `code` is machine-readable and `detail` is for a human; `str(exc)` renders
    both, so a caller that prints the exception cannot drop the remedy.
    """

    def __init__(self, code: str, detail: str):
        super().__init__(code, detail)
        self.code = code
        self.detail = detail

    def __str__(self) -> str:
        return f"REFUSED {self.code}: {self.detail}"


# ---------------------------------------------------------------------------
# The pin reader
# ---------------------------------------------------------------------------
#
# SUPPORTED, and nothing else: one document, `#` comment lines, blank lines,
# indent-zero `key: value` scalars, one indent-zero `sources:` key whose value
# is a block sequence of mappings, and inside each of those a `files:` key
# whose value is a block sequence of mappings. Scalars may be bare or wrapped
# in one pair of single or double quotes.
#
# REFUSED, by line number: a tab in the indentation, a construct this reader
# would have to invent a meaning for, a key at an indentation the shape does
# not put a key at. An invented meaning in a checker is a wrong answer with a
# confident tone — and this reader's whole job is to be unable to mis-read the
# file it is the checker for.
#
# The reader also records LINE NUMBERS, because `apply` rewrites the rows it
# owns in place rather than re-emitting the file: the header prose, the key
# order and every other source's block survive an `apply` byte for byte, so a
# reviewer reading `git diff` after one sees the commit and the digests move
# and nothing else.


class Row:
    """One `- path: … / sha256: … / mode: …` record, and where it sits.

    `mode` is OPTIONAL: a row written before it existed, or by hand for a
    new source, carries none, and stays valid unrecorded rather than
    refused.
    """

    def __init__(self, path: str, line: int):
        self.path = path
        self.sha256: str | None = None
        self.mode: str | None = None
        self.first_line = line
        self.last_line = line


class Source:
    """One `sources:` block: its scalars, its rows, and their line spans."""

    def __init__(self, line: int, indent: int):
        self.values: dict[str, str] = {}
        self.rows: list[Row] = []
        self.item_line = line
        self.item_indent = indent
        self.key_indent = indent + 2
        self.commit_line: int | None = None
        self.files_line: int | None = None
        self.files_indent: int | None = None

    def value(self, key: str) -> str:
        return self.values.get(key, "")

    @property
    def id(self) -> str:
        return self.value("id")


def _unquote(raw: str) -> str:
    text = raw.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    return text


def _split_key(text: str, path: Path, number: int) -> tuple[str, str]:
    if ":" not in text:
        raise Refusal("pin-unparsable",
                      f"{display(path)}:{number}: expected `key: value`, got {text!r}")
    key, _, value = text.partition(":")
    return key.strip(), _unquote(value)


def read_pin(path: Path) -> tuple[dict[str, str], list[Source], list[str]]:
    """Parse the pin. Returns its top-level scalars, its sources, its lines."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise Refusal("pin-unreadable", f"{exc}") from exc
    except UnicodeDecodeError as exc:
        # A pin is text. Bytes that are not UTF-8 are a mis-written file, and
        # a mis-written file must exit 2 with a name, not a traceback.
        raise Refusal("pin-not-utf8", f"{display(path)}: {exc}") from exc
    lines = text.split("\n")

    top: dict[str, str] = {}
    sources: list[Source] = []
    in_sources = False
    source: Source | None = None
    row: Row | None = None

    for index, raw in enumerate(lines):
        number = index + 1
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.startswith("\t") or (raw[: len(raw) - len(raw.lstrip())]
                                    .count("\t")):
            raise Refusal("pin-unparsable",
                          f"{display(path)}:{number}: a tab in the indentation")
        indent = len(raw) - len(raw.lstrip(" "))
        body = raw.strip()

        if indent == 0:
            in_sources = False
            source = None
            row = None
            key, value = _split_key(body, path, number)
            if key == "sources":
                if value:
                    raise Refusal(
                        "pin-unparsable",
                        f"{display(path)}:{number}: `sources:` takes a block "
                        f"sequence, "
                        f"not {value!r}")
                if "sources" in top:
                    raise Refusal(
                        "pin-duplicate-key",
                        f"{display(path)}:{number}: `sources:` is set twice; "
                        f"the second block would merge into the first")
                top["sources"] = ""
                in_sources = True
                continue
            if key in top:
                raise Refusal("pin-duplicate-key",
                              f"{display(path)}:{number}: `{key}:` is set "
                              f"twice at the top level")
            top[key] = value
            continue

        if not in_sources:
            raise Refusal("pin-unparsable",
                          f"{display(path)}:{number}: indented line outside "
                          f"`sources:`")

        # A new `- ` item at the sources indentation opens a source block.
        if source is None or indent == source.item_indent:
            if not body.startswith("- "):
                raise Refusal(
                    "pin-unparsable",
                    f"{display(path)}:{number}: expected a `- ` source item at "
                    f"indent "
                    f"{indent}")
            source = Source(number, indent)
            sources.append(source)
            row = None
            key, value = _split_key(body[2:], path, number)
            if key == "files":
                raise Refusal(
                    "pin-unparsable",
                    f"{display(path)}:{number}: a source opens with a scalar "
                    f"key, not `files:`")
            source.values[key] = value
            if key == "commit":
                source.commit_line = number
            continue

        if source.files_indent is not None and indent > source.files_indent:
            item_indent = source.files_indent + 2
            if indent == item_indent:
                if not body.startswith("- "):
                    raise Refusal(
                        "pin-unparsable",
                        f"{display(path)}:{number}: expected a `- ` file row at "
                        f"indent "
                        f"{indent}")
                key, value = _split_key(body[2:], path, number)
                if key != "path":
                    raise Refusal(
                        "pin-unparsable",
                        f"{display(path)}:{number}: a file row opens with `path:`, "
                        f"not "
                        f"{key!r}")
                row = Row(value, number)
                source.rows.append(row)
                continue
            if indent == item_indent + 2 and row is not None:
                key, value = _split_key(body, path, number)
                if key not in ("sha256", "mode"):
                    raise Refusal(
                        "pin-unparsable",
                        f"{display(path)}:{number}: a file row carries `path:`, "
                        f"`sha256:` and an optional `mode:`, not {key!r}")
                if key == "sha256":
                    if row.sha256 is not None:
                        raise Refusal(
                            "pin-duplicate-key",
                            f"{display(path)}:{number}: '{row.path}' sets "
                            f"`sha256:` twice")
                    row.sha256 = value
                else:
                    if row.mode is not None:
                        raise Refusal(
                            "pin-duplicate-key",
                            f"{display(path)}:{number}: '{row.path}' sets "
                            f"`mode:` twice")
                    row.mode = value
                row.last_line = number
                continue
            raise Refusal("pin-unparsable",
                          f"{display(path)}:{number}: unexpected indent {indent} inside "
                          f"`files:`")

        if indent != source.key_indent:
            raise Refusal("pin-unparsable",
                          f"{display(path)}:{number}: unexpected indent {indent} in "
                          f"source '{source.id or '?'}'")
        key, value = _split_key(body, path, number)
        if key == "files":
            if value:
                raise Refusal(
                    "pin-unparsable",
                    f"{display(path)}:{number}: `files:` takes a block "
                    f"sequence, not {value!r}")
            if source.files_line is not None:
                raise Refusal(
                    "pin-duplicate-key",
                    f"{display(path)}:{number}: source '{source.id}' has two "
                    f"`files:` blocks")
            source.files_line = number
            source.files_indent = indent
            row = None
            continue
        if key in source.values:
            raise Refusal("pin-duplicate-key",
                          f"{display(path)}:{number}: source '{source.id}' "
                          f"sets `{key}:` twice")
        source.values[key] = value
        if key == "commit":
            source.commit_line = number
        row = None

    return top, sources, lines


def validate_pin(path: Path, top: dict[str, str], sources: list[Source],
                 digests_required: bool) -> None:
    """Refuse a pin that does not say what it claims to say.

    `digests_required` is False for `apply`, and only for `apply`: a source
    block is HAND-WRITTEN with its `path:` rows and no digests, once, and the
    first `apply` is what fills them in. `check` requires every one of them,
    because a row with no digest pins nothing.
    """
    if top.get("schema_version") != SCHEMA_VERSION:
        raise Refusal("pin-schema",
                      f"{display(path)}: schema_version is "
                      f"{top.get('schema_version')!r}, not {SCHEMA_VERSION!r}")
    if top.get("kind") != KIND:
        raise Refusal("pin-kind",
                      f"{display(path)}: kind is {top.get('kind')!r}, not {KIND!r}")
    if top.get("digest_algorithm") != DIGEST_ALGORITHM:
        raise Refusal(
            "pin-digest-algorithm",
            f"{display(path)}: digest_algorithm is "
            f"{top.get('digest_algorithm')!r}, not {DIGEST_ALGORITHM!r}")
    if not sources:
        raise Refusal("pin-no-sources",
                      f"{display(path)}: `sources:` names no source")

    seen_ids: set[str] = set()
    seen_dirs: dict[str, str] = {}
    for source in sources:
        where = f"{display(path)}:{source.item_line}"
        missing = [key for key in SOURCE_KEYS if not source.value(key)]
        if missing:
            raise Refusal("pin-source-keys",
                          f"{where}: source '{source.id or '?'}' is missing "
                          + ", ".join(missing))
        if not SOURCE_ID_RE.match(source.id):
            raise Refusal("pin-source-id",
                          f"{where}: {source.id!r} is not a lowercase id")
        if source.id in seen_ids:
            raise Refusal("pin-source-duplicate",
                          f"{where}: '{source.id}' is named twice")
        seen_ids.add(source.id)
        if not REPOSITORY_RE.match(source.value("source_repository")):
            raise Refusal(
                "pin-source-repository",
                f"{where}: source_repository "
                f"{source.value('source_repository')!r} is not `owner/repo`")
        if source.value("materialization") != "copied":
            raise Refusal(
                "pin-materialization",
                f"{where}: materialization is "
                f"{source.value('materialization')!r}; this pin records copies")
        if source.value("revision_kind") != "commit":
            raise Refusal(
                "pin-revision-kind",
                f"{where}: revision_kind is "
                f"{source.value('revision_kind')!r}, not 'commit'")
        if not COMMIT_RE.match(source.value("commit")):
            raise Refusal(
                "pin-commit",
                f"{where}: commit {source.value('commit')!r} is not 40 "
                f"lowercase hex — a tag can be moved and a commit cannot")
        vendor_dir = source.value("vendor_dir")
        _checked_relative(vendor_dir, where, "vendor_dir")
        for other, owner in seen_dirs.items():
            if vendor_dir == other or _under(vendor_dir, other) \
                    or _under(other, vendor_dir):
                raise Refusal(
                    "pin-vendor-dir-shared",
                    f"{where}: '{source.id}' vendors into {vendor_dir} and "
                    f"'{owner}' into {other}; one directory per source, and "
                    f"never one inside another — the outer source's walk "
                    f"would report the inner source's files as unpinned")
        seen_dirs[vendor_dir] = source.id
        if source.files_line is None:
            raise Refusal("pin-no-files",
                          f"{where}: source '{source.id}' has no `files:` key")
        if not source.rows:
            raise Refusal(
                "pin-no-rows",
                f"{where}: source '{source.id}' has no `files:` rows.\n"
                f"A source's rows are HAND-WRITTEN once, one `- path: "
                f"<path in {source.value('source_repository')}>` per file,\n"
                f"with no `sha256:` (or an empty one); the first `apply` "
                f"fetches the bytes and fills\nthe digests in:\n"
                f"    python3 {TOOL} apply --source {source.id} "
                f"--at <40-hex> --yes")
        seen_paths: set[str] = set()
        for row in source.rows:
            row_where = f"{display(path)}:{row.first_line}"
            _checked_relative(row.path, row_where, "path")
            if row.path in seen_paths:
                raise Refusal("pin-row-duplicate",
                              f"{row_where}: '{row.path}' has two rows")
            for other in seen_paths:
                if _under(row.path, other) or _under(other, row.path):
                    raise Refusal(
                        "pin-row-nested",
                        f"{row_where}: '{row.path}' and '{other}' cannot both "
                        f"be files; one is inside the other")
            seen_paths.add(row.path)
            if not row.sha256:
                # A row written with no digest, or an empty one, is a row
                # WAITING to be filled: that is how a new source block is
                # hand-written. `apply` fills it; `check` refuses it, because
                # a row with no digest pins nothing.
                if digests_required:
                    raise Refusal(
                        "pin-row-unfilled",
                        f"{row_where}: '{row.path}' has no sha256, so it pins "
                        f"nothing.\nFill it from the upstream bytes:\n"
                        f"    python3 {TOOL} apply --source {source.id} "
                        f"--at {source.value('commit')} --yes")
            elif not SHA256_RE.match(row.sha256):
                raise Refusal(
                    "pin-row-digest",
                    f"{row_where}: '{row.path}' has sha256 {row.sha256!r}, "
                    f"which is not 64 lowercase hex")
            if row.mode is not None and not MODE_RE.match(row.mode):
                raise Refusal(
                    "pin-row-mode",
                    f"{row_where}: '{row.path}' has mode {row.mode!r}, which "
                    f"is not '100644' or '100755'")


#: A path that is not relative-and-downward. Anchored at the front so a drive
#: letter, a UNC prefix and a leading slash are all one check.
NOT_RELATIVE_RE = re.compile(r"^(?:/|\\\\|[A-Za-z]:)")


def _under(inner: str, outer: str) -> bool:
    """True when `inner` sits beneath `outer`, compared segment by segment.

    String prefixes are not enough: `files/openreposhapex` starts with
    `files/openreposhape` and is a different directory.
    """
    a, b = inner.split("/"), outer.split("/")
    return len(a) > len(b) and a[:len(b)] == b


def _checked_relative(value: str, where: str, label: str) -> None:
    """A path in the pin is relative, and stays inside the vendor tree."""
    if not value:
        raise Refusal("pin-path-empty", f"{where}: {label} is empty")
    if NOT_RELATIVE_RE.match(value) or "\\" in value:
        raise Refusal("pin-path-absolute",
                      f"{where}: {label} {value!r} is not a relative POSIX "
                      f"path")
    if any(part in ("", ".", "..") for part in value.split("/")):
        raise Refusal("pin-path-traversal",
                      f"{where}: {label} {value!r} does not stay inside the "
                      f"vendor directory")


# ---------------------------------------------------------------------------
# Digests and the tree
# ---------------------------------------------------------------------------


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_executable(path: Path) -> bool:
    """True when ANY of the file's own executable bits is set.

    A row's `mode:` records one bit, not a full permission triple — `apply`
    only ever writes 0755 or 0644 (`fetch_tree_modes`) — so this only needs
    to answer the same question the row does: does this run as a command.
    """
    return bool(path.stat().st_mode & 0o111)


def contained(base: Path, target: Path) -> bool:
    """True when `target` REALLY lives under `base`, every link resolved.

    `_checked_relative` rejects `..` and an absolute path, which is lexical.
    This is the other half: a symlinked `vendor_dir`, or a symlinked directory
    inside one, would otherwise let `check` hash — and `apply` write — bytes
    outside the tree the pin describes. `realpath` resolves what exists and
    leaves the rest alone, so it answers for a destination not created yet.
    """
    base_real = Path(os.path.realpath(base))
    target_real = Path(os.path.realpath(target))
    return target_real == base_real or base_real in target_real.parents


def vendor_root(pin_path: Path, source: Source) -> Path:
    """`vendor_dir` is relative to the pin file's own directory.

    REFUSES a vendor directory that resolves outside the pin's own directory:
    that is a link, and a pin cannot describe bytes it does not sit above.
    """
    pin_dir = pin_path.resolve().parent
    root = pin_dir / source.value("vendor_dir")
    if not contained(pin_dir, root):
        raise Refusal(
            "pin-vendor-dir-escapes",
            f"{source.value('vendor_dir')} resolves outside the pin's own "
            f"directory ({pin_dir}); a vendor directory is a real directory "
            f"beside the pin, never a link")
    return root


def display(path: Path) -> str:
    """A path as a reader of this repository would type it.

    Relative to the working directory when it is INSIDE it, so the strings in
    every message are the strings a person can paste — and so that no output
    of this tool carries a host-absolute path when it is run from the
    repository root, which is the only place CI runs it from. A path outside
    the working directory is printed in full rather than as a ladder of `..`.
    """
    here = Path.cwd().resolve()
    resolved = Path(path).resolve()
    if here == Path(here.root):
        # Run from `/`, every path is "under" the working directory and
        # `relative_to` would strip the leading slash off an absolute path.
        return str(resolved)
    if resolved == here or here in resolved.parents:
        return str(resolved.relative_to(here))
    return str(resolved)


def walk_vendor_dir(root: Path) -> list[tuple[str, bool]]:
    """Every entry under a vendor directory: (relative path, is a symlink).

    Links are never followed and a linked DIRECTORY is reported as an entry
    of its own, because `os.walk` does not descend into one — a file hidden
    behind a link would otherwise be a file under a vendor directory that no
    row records and no walk sees.
    """
    found: list[tuple[str, bool]] = []
    if not root.is_dir():
        return found
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        here = Path(dirpath)
        names = list(filenames)
        names += [name for name in dirnames
                  if (here / name).is_symlink()]
        for name in sorted(names):
            full = here / name
            found.append((full.relative_to(root).as_posix(),
                          full.is_symlink()))
        dirnames.sort()
    return found


# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------


def selected(sources: list[Source], wanted: str | None,
             pin_path: Path) -> list[Source]:
    if wanted is None:
        return sources
    for source in sources:
        if source.id == wanted:
            return [source]
    raise Refusal(
        "upstream-unknown-source",
        f"{display(pin_path)} names no source '{wanted}'.\n"
        "It names: " + ", ".join(s.id for s in sources) + ".\n"
        "A new source is a new block in that file and a decision, not a flag.")


def _blame(guilty: list[Source], source: Source) -> None:
    if source not in guilty:
        guilty.append(source)


def cmd_check(args: argparse.Namespace) -> int:
    pin_path = Path(args.pin)
    top, sources, _ = read_pin(pin_path)
    validate_pin(pin_path, top, sources, digests_required=True)

    drift: list[str] = []
    modes: list[str] = []
    #: (shown path, wanted octal) per `modes` line, so the remediation can
    #: print the exact `chmod` rather than send the reader back to work it
    #: out from the finding.
    mode_fixes: list[tuple[str, str]] = []
    unpinned: list[str] = []
    #: The sources a finding was raised against, so the remediation can name
    #: the directory to restore rather than a `<id>` the reader must expand.
    guilty: list[Source] = []
    checked = 0

    for source in selected(sources, args.source, pin_path):
        root = vendor_root(pin_path, source)
        rows = {row.path: row for row in source.rows}
        print(f"source      {source.id} ({source.value('source_repository')}) "
              f"@ {source.value('commit')[:12]}")
        for row in source.rows:
            copy = root / row.path
            shown = f"{source.value('vendor_dir')}/{row.path}"
            if copy.is_symlink():
                drift.append(f"  SYMLINK  {shown}  a vendored copy is a "
                             f"regular file, never a link")
                _blame(guilty, source)
                continue
            if copy.exists() and not contained(root, copy):
                drift.append(f"  ESCAPES  {shown}  resolves outside the "
                             f"vendor directory")
                _blame(guilty, source)
                continue
            if not copy.is_file():
                drift.append(f"  MISSING  {shown}")
                _blame(guilty, source)
                continue
            computed = file_sha256(copy)
            checked += 1
            if computed != row.sha256:
                drift.append(f"  CHANGED  {shown}  recorded {row.sha256[:8]}  "
                             f"computed {computed[:8]}")
                _blame(guilty, source)
                continue
            if row.mode is not None:
                # UNRECORDED rows (no `mode:`) are not checked at all — the
                # pin stays readable across the change that added this.
                want_exec = row.mode == "100755"
                have_exec = is_executable(copy)
                if have_exec != want_exec:
                    want_octal = "0755" if want_exec else "0644"
                    have_octal = "0755" if have_exec else "0644"
                    modes.append(f"  MODE     {shown}  recorded {want_octal}  "
                                 f"working tree {have_octal}")
                    mode_fixes.append((shown, want_octal))
                    _blame(guilty, source)
                    continue
            print(f"  ok      {shown}  {computed[:12]}")
        for found, is_link in walk_vendor_dir(root):
            if found in rows:
                continue
            unpinned.append(f"  UNPINNED {source.value('vendor_dir')}/{found}"
                            + ("  (a symbolic link)" if is_link else ""))
            _blame(guilty, source)

    if not drift and not modes and not unpinned:
        print()
        print(f"{checked} vendored copy(ies) match {display(pin_path)}")
        return 0

    print()
    sys.stdout.flush()
    if drift:
        print(f"REFUSED: {len(drift)} vendored copy(ies) no longer match "
              f"{display(pin_path)}.", file=sys.stderr)
        for line in drift:
            print(line, file=sys.stderr)
        print(
            "Do not recompute the row to make this pass — that records the "
            "local edit as\nthe upstream. Either restore the bytes:",
            file=sys.stderr)
        for source in guilty:
            print(f"    git checkout -- "
                  f"{display(vendor_root(pin_path, source))}/",
                  file=sys.stderr)
        print("or take a NEW upstream revision on purpose:", file=sys.stderr)
        for source in guilty:
            print(f"    python3 {TOOL} apply --source {source.id} "
                  f"--at <40-hex> --yes", file=sys.stderr)
    if modes:
        if drift:
            print(file=sys.stderr)
        print(f"REFUSED: {len(modes)} vendored copy(ies) no longer have the "
              f"executable bit {display(pin_path)} records.", file=sys.stderr)
        for line in modes:
            print(line, file=sys.stderr)
        print("The bytes are right; only the working-tree permission bit "
              "drifted. Fix it:", file=sys.stderr)
        for shown, octal in mode_fixes:
            print(f"    chmod {octal} {shown}", file=sys.stderr)
    if unpinned:
        if drift or modes:
            print(file=sys.stderr)
        print(f"REFUSED: {len(unpinned)} file(s) under a vendor directory have "
              f"no row in {display(pin_path)}.", file=sys.stderr)
        for line in unpinned:
            print(line, file=sys.stderr)
        print("Every file under a vendor directory is a pinned copy by "
              "construction.\nTake it from upstream:", file=sys.stderr)
        for source in guilty:
            print(f"    python3 {TOOL} apply --source {source.id} "
                  f"--at {source.value('commit')} --add <path> --yes",
                  file=sys.stderr)
        print("or delete it.", file=sys.stderr)
    return 1


# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------


def cmd_list(args: argparse.Namespace) -> int:
    pin_path = Path(args.pin)
    top, sources, _ = read_pin(pin_path)
    validate_pin(pin_path, top, sources, digests_required=True)
    print(f"{display(pin_path)}  schema_version {top['schema_version']}  "
          f"{top['kind']}  {top['digest_algorithm']}")
    for source in sources:
        print()
        print(f"{source.id}")
        print(f"  source_repository  {source.value('source_repository')}")
        print(f"  materialization    {source.value('materialization')}")
        print(f"  revision_kind      {source.value('revision_kind')}")
        print(f"  commit             {source.value('commit')}")
        print(f"  vendor_dir         {source.value('vendor_dir')}")
        for row in source.rows:
            print(f"    {row.sha256[:12]}  {row.path}")
    return 0


# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------


def run_capture(argv: list[str]) -> tuple[int, bytes, str]:
    """Run a command, never through a shell. Missing binary is returncode 127."""
    try:
        proc = subprocess.run(argv, capture_output=True, check=False)
    except FileNotFoundError as exc:
        return 127, b"", str(exc)
    return (proc.returncode, proc.stdout,
            proc.stderr.decode("utf-8", "replace").strip())


def gh_api(endpoint: str, jq: str | None = None) -> tuple[int, str, str]:
    argv = ["gh", "api", endpoint]
    if jq is not None:
        argv += ["-q", jq]
    code, out, err = run_capture(argv)
    return code, out.decode("utf-8", "replace").strip(), err


def default_branch(repository: str) -> str:
    code, out, err = gh_api(f"repos/{repository}", ".default_branch")
    if code == 127:
        raise Refusal(
            "upstream-no-gh",
            f"`apply` needs the `gh` CLI to prove that a commit is reachable "
            f"from\n{repository}'s default branch, and it is not on PATH: "
            f"{err}\n`check` needs no network and no `gh` at all.")
    if code != 0 or not out:
        raise Refusal(
            "upstream-default-branch",
            f"could not read {repository}'s default branch: {err or code}")
    return out


def assert_on_default_branch(repository: str, commit: str) -> str:
    """Refuse a commit the rest of the world cannot fetch.

    `compare/<default>...<commit>` answers `identical` when the commit IS the
    branch tip and `behind` when the branch has moved on past it. `ahead` and
    `diverged` both mean the commit is not on that branch: for a repository
    that squash-merges, that is exactly a pull-request branch commit, which the
    merge orphans and a raw fetch of which 404s for the next person.
    """
    branch = default_branch(repository)
    code, out, err = gh_api(
        f"repos/{repository}/compare/{branch}...{commit}", ".status")
    if code != 0 or not out:
        raise Refusal(
            "upstream-unreachable-commit",
            f"could not compare {commit[:12]} against {repository}'s "
            f"{branch}: {err or code}")
    if out not in ("identical", "behind"):
        raise Refusal(
            "upstream-not-on-default-branch",
            f"{commit[:12]} is not on {repository}'s {branch}; `compare` says "
            f"'{out}'.\nA pin the rest of the world cannot fetch is a pin "
            f"nobody can reproduce — land\nthe change first, then pin the "
            f"commit {branch} carries.")
    return branch


def fetch_file(repository: str, commit: str, path: str) -> bytes | None:
    """The shims' order: the API first, the raw URL second.

    THE EXIT CODE IS THE CHECK, and the body's length is not: both `gh api`
    and `curl -f` exit non-zero on a 404 or a truncated transfer, and a
    zero-byte file is a perfectly ordinary git blob that this must be able to
    vendor. The bytes are RETURNED and held in memory rather than written
    anywhere: nothing reaches a vendor directory until every file in the set
    is in hand. Returns None rather than dying, so the caller can report the
    whole set of failures instead of stopping at the first.
    """
    code, out, _ = run_capture(
        ["gh", "api", f"repos/{repository}/contents/{path}?ref={commit}",
         "-H", GH_RAW_ACCEPT])
    if code == 0:
        return out
    code, out, _ = run_capture(
        ["curl", "-fsSL",
         f"https://raw.githubusercontent.com/{repository}/{commit}/{path}"])
    if code == 0:
        return out
    return None


def fetch_tree_modes(repository: str, commit: str) -> dict[str, str]:
    """Every path's own git mode at a commit, in ONE call, cached for the run.

    `git/trees/<commit>?recursive=1` lists the whole tree; each entry's own
    `mode` is the only way to reproduce the bit upstream actually carries —
    a `.py` upstream ships 0644 is not made a command by the fact that its
    bytes are still correct, and a byte-content heuristic cannot tell a
    directory or a symlink from a file at all. The result maps every path in
    the tree to its mode string (`"100644"`, `"100755"`, or something else
    entirely for a shape a vendored copy cannot be); the caller looks up only
    the paths it wants.
    """
    code, out, err = gh_api(
        f"repos/{repository}/git/trees/{commit}?recursive=1",
        r'.tree[] | .path + "\t" + .mode')
    if code == 127:
        raise Refusal(
            "upstream-no-gh",
            f"`apply` needs the `gh` CLI to read {repository}'s tree modes "
            f"at\n{commit[:12]}, and it is not on PATH: {err}")
    if code != 0:
        raise Refusal(
            "upstream-tree-unreadable",
            f"could not read {repository}'s tree at {commit[:12]}: "
            f"{err or code}")
    modes: dict[str, str] = {}
    for line in out.split("\n"):
        if not line:
            continue
        entry_path, _, mode = line.rpartition("\t")
        modes[entry_path] = mode
    return modes


def rewrite_pin(pin_path: Path, lines: list[str], source: Source,
                commit: str, rows: list[tuple[str, str, str]]) -> None:
    """Move this source's `commit:` and re-emit its `files:` rows, in place.

    Only those lines change. The header prose, every other source's block, the
    key order and the trailing bytes of the file survive an `apply` exactly as
    they were — which is what makes `git diff` after one readable. Comment
    lines BETWEEN two file rows do not survive, because the rows are re-emitted
    as a block; the pin's own header says so.
    """
    assert source.commit_line is not None
    assert source.files_line is not None and source.files_indent is not None
    commit_index = source.commit_line - 1
    original = lines[commit_index]
    # Everything in front of the key, so a `  - commit:` opening item keeps
    # its sequence marker and an ordinary `    commit:` keeps its indentation.
    # The bare word, not `commit:`: the reader tolerates `commit : "…"` (it
    # strips the key before comparing), and searching for the colon spelling
    # raised ValueError on one — a traceback where this file's own rule is
    # that a mis-written pin exits 2 with a name. Only whitespace and an
    # optional `- ` can precede the key, so the first occurrence is the key.
    prefix = original[:original.index("commit")]
    lines[commit_index] = f'{prefix}commit: "{commit}"'

    item_indent = " " * (source.files_indent + 2)
    key_indent = " " * (source.files_indent + 4)
    block: list[str] = []
    for path, digest, mode in rows:
        block.append(f"{item_indent}- path: {path}")
        block.append(f'{key_indent}sha256: "{digest}"')
        block.append(f'{key_indent}mode: "{mode}"')

    start = source.files_line          # the line after `files:`
    end = max((row.last_line for row in source.rows), default=start)
    pin_path.write_text("\n".join(lines[:start] + block + lines[end:]),
                        encoding="utf-8")


def cmd_apply(args: argparse.Namespace) -> int:
    pin_path = Path(args.pin)
    if not COMMIT_RE.match(args.at):
        raise Refusal(
            "upstream-bad-commit",
            f"--at {args.at!r} is not a commit. `apply` takes a full "
            f"40-character\nlowercase commit; a tag can be moved and a commit "
            f"cannot.")
    top, sources, lines = read_pin(pin_path)
    validate_pin(pin_path, top, sources, digests_required=False)
    source = selected(sources, args.source, pin_path)[0]
    repository = source.value("source_repository")
    root = vendor_root(pin_path, source)

    have = [row.path for row in source.rows]
    for flag, given in (("--add", args.add), ("--remove", args.remove)):
        for path in given:
            if given.count(path) > 1:
                raise Refusal(
                    "upstream-repeated-flag",
                    f"{flag} {path!r} is given {given.count(path)} times; "
                    f"one row is one row")
    for path in args.add:
        _checked_relative(path, "--add", "path")
        if path in have:
            raise Refusal(
                "upstream-already-pinned",
                f"--add {path!r}: source '{source.id}' already has a row for "
                f"it.")
    for path in args.remove:
        if path not in have:
            raise Refusal(
                "upstream-not-pinned",
                f"--remove {path!r}: source '{source.id}' has no row for it. "
                f"It has: " + ", ".join(have))
        if path in args.add:
            raise Refusal("upstream-add-and-remove",
                          f"{path!r} is both --add and --remove")
    wanted = [path for path in have if path not in args.remove]
    wanted += [path for path in args.add if path not in wanted]
    if not wanted:
        # Refused HERE, before the fetch and before any byte moves: an empty
        # `files:` block is a pin its own `check` refuses, so `apply` must not
        # be able to write one and then print `NEXT … check`.
        raise Refusal(
            "upstream-empty-source",
            f"--remove would leave source '{source.id}' with no rows, and a "
            f"source with no\nfiles is a source that should not be in the "
            f"pin — `check` refuses one. Delete the\nblock from "
            f"{display(pin_path)} by hand, on purpose, instead.")

    branch = assert_on_default_branch(repository, args.at)
    print(f"source      {source.id} ({repository})")
    print(f"pinned      {source.value('commit')[:12]}")
    print(f"target      {args.at[:12]} (on {branch})")
    print(f"vendor      {source.value('vendor_dir')}")
    print()

    # ONE CALL PER SOURCE, CACHED FOR THE RUN: every path's own mode in the
    # upstream tree, so a row's `mode:` records what upstream actually
    # carries rather than a guess from the bytes.
    tree_modes = fetch_tree_modes(repository, args.at)

    # ALL THE BYTES IN HAND BEFORE ANY ONE OF THEM IS PLACED (#82, F10). A
    # fetch that fails halfway through leaves a vendor directory holding some
    # files from the new commit and some from the old, which no pin describes.
    staged: dict[str, bytes] = {}
    missing: list[str] = []
    bad_modes: list[str] = []
    for path in wanted:
        data = fetch_file(repository, args.at, path)
        if data is None:
            missing.append(path)
        else:
            staged[path] = data
        mode = tree_modes.get(path)
        if mode not in ("100644", "100755"):
            shown_mode = mode if mode is not None else "not in the tree"
            bad_modes.append(f"{path}  ({shown_mode})")
    if missing:
        raise Refusal(
            "upstream-fetch-failed",
            f"{len(missing)} of {len(wanted)} file(s) could not be fetched "
            f"from {repository}\nat {args.at[:12]}, so NOTHING was written and "
            f"no vendored copy was replaced:\n"
            + "".join(f"    {path}\n" for path in missing)
            + "Both ways were tried, for each:\n"
            f"    gh api repos/{repository}/contents/<path>?ref={args.at} "
            f"-H '{GH_RAW_ACCEPT}'\n"
            f"    curl -fsSL https://raw.githubusercontent.com/{repository}/"
            f"{args.at}/<path>")
    if bad_modes:
        raise Refusal(
            "upstream-mode-unusable",
            f"{len(bad_modes)} of {len(wanted)} file(s) are not an ordinary "
            f"file in {repository}'s\ntree at {args.at[:12]}, so NOTHING was "
            f"written:\n"
            + "".join(f"    {line}\n" for line in bad_modes)
            + "A pin records copies of regular files; a row naming a "
            "symlink, a submodule\nor a directory is not one.")

    rows: list[tuple[str, str, str]] = []
    plan: list[str] = []
    for path in wanted:
        data = staged[path]
        digest = hashlib.sha256(data).hexdigest()
        mode = tree_modes[path]
        rows.append((path, digest, mode))
        copy = root / path
        if path not in have:
            plan.append(f"  add       {path}  {digest[:12]}")
        elif copy.is_file() and file_sha256(copy) == digest:
            plan.append(f"  unchanged {path}")
        else:
            plan.append(f"  take      {path}  {digest[:12]}")
    for path in args.remove:
        plan.append(f"  remove    {path}")
    if source.value("commit") != args.at:
        plan.append(f"  re-pin    commit {source.value('commit')[:12]} -> "
                    f"{args.at[:12]}")
    for line in plan:
        print(line)

    if not args.yes:
        print()
        raise Refusal(
            "upstream-declined",
            "NOTHING was written: this is the plan, not the run. Re-run it "
            "with --yes.")

    # EVERY DESTINATION JUDGED BEFORE ANY IS TOUCHED, the same rule as the
    # fetch above: `write_bytes` and `chmod` follow a link, and a refusal
    # raised halfway down the write loop would leave some rows at the new
    # commit and some at the old, which no pin describes.
    escaping = [path for path, _, _ in rows
                if (root / path).is_symlink()
                or not contained(root, root / path)]
    if escaping:
        raise Refusal(
            "upstream-destination-escapes",
            f"{len(escaping)} destination(s) are links, or resolve outside "
            f"the vendor directory,\nso NOTHING was written:\n"
            + "".join(f"    {source.value('vendor_dir')}/{path}\n"
                      for path in escaping)
            + "`write_bytes` and `chmod` follow a link, so this would "
            "overwrite bytes no row\ndescribes. Restore the directory first: "
            f"git checkout -- {display(root)}/")

    print()
    for path, digest, mode in rows:
        copy = root / path
        copy.parent.mkdir(parents=True, exist_ok=True)
        data = staged[path]
        copy.write_bytes(data)
        octal = 0o755 if mode == "100755" else 0o644
        os.chmod(copy, octal)
        print(f"  wrote     {source.value('vendor_dir')}/{path}  {octal:04o}")
    for path in args.remove:
        copy = root / path
        # `is_file()` is False for a directory AND for a broken link, either of
        # which would have outlived its row. Links are unlinked, not followed;
        # a directory is a shape no row ever described, so it is named.
        if copy.is_symlink() or copy.is_file():
            copy.unlink()
            print(f"  deleted   {source.value('vendor_dir')}/{path}")
        elif copy.is_dir():
            print(f"  KEPT      {source.value('vendor_dir')}/{path} is a "
                  f"directory, not a vendored copy; its row is gone and it "
                  f"is not — remove it by hand")
    rewrite_pin(pin_path, lines, source, args.at, rows)
    print(f"  re-pinned {display(pin_path)}  "
          f"{len(rows)} row(s) at {args.at[:12]}")
    print()
    print(f"NEXT  python3 {TOOL} check")
    return 0


# ---------------------------------------------------------------------------
# argv
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=TOOL,
        description="Check, and re-take, this repository's vendored copies.")
    subparsers = parser.add_subparsers(dest="verb", required=True)

    check = subparsers.add_parser(
        "check", help="every vendored copy still matches its row (writes "
                      "nothing, needs no network)")
    check.add_argument("--pin", default=str(DEFAULT_PIN),
                       help="the pin file (default: beside this tool)")
    check.add_argument("--source", default=None,
                       help="check one source instead of all of them")
    check.set_defaults(func=cmd_check)

    apply_ = subparsers.add_parser(
        "apply", help="take one source's files at a commit and re-pin them")
    apply_.add_argument("--pin", default=str(DEFAULT_PIN))
    apply_.add_argument("--source", required=True)
    apply_.add_argument("--at", required=True,
                        metavar="COMMIT", help="a full 40-character commit")
    apply_.add_argument("--yes", action="store_true",
                        help="without it, the plan is printed and nothing runs")
    apply_.add_argument("--add", action="append", default=[], metavar="PATH",
                        help="pin a file this source does not carry yet")
    apply_.add_argument("--remove", action="append", default=[],
                        metavar="PATH",
                        help="drop a row and delete its vendored copy")
    apply_.set_defaults(func=cmd_apply)

    listing = subparsers.add_parser("list", help="what the pin names")
    listing.add_argument("--pin", default=str(DEFAULT_PIN))
    listing.set_defaults(func=cmd_list)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except Refusal as exc:
        # Flush first: a refusal that lands on a terminal ahead of the plan or
        # the per-file report it refers to reads as a refusal about nothing.
        sys.stdout.flush()
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
