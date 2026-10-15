# workBenches releases

The first numbered release is **v1.5.0**. `VERSION` is the product version;
`./setup.sh --version`, the TUI, and setup logs read that file. The current
working tree is a release candidate until its reviewed commit is tagged.

The [approved 1.5.0 scope and release gates](release-1.5.0.md) define what ships
in this release. Separate provider vault sign-ins are accepted for 1.5.0;
single-login credential recovery is deferred to a later feature release.

Use patch releases for fixes (`1.5.1`), minor releases for compatible features
(`1.6.0`), and major releases for breaking changes (`2.0.0`). Existing Tools,
Vault, and shared-image recipe tags have their own identities; do not rename
them just because the product version changes.

## Freeze and validate

1. Merge the intended changes and choose a candidate commit. Create
   `release/1.5.0` from it. After this point, admit only release fixes to that
   branch; new features continue separately.
2. Set `VERSION` to `1.5.0`. Run the freeze command below. It records exact
   commits for every catalog bench and assembly submodule in
   `config/release-lock.json`, including separately cloned repositories.
   Local checkouts must be clean and submodules must match the assembly pins.
   Missing repositories are resolved from their public remote HEAD or existing
   gitlink. Freezing records source identity; it does not certify untested code.
3. Review and commit the version, lock, release notes, and release fixes. Run
   the source-lock check and the setup/container acceptance checks below on
   that exact commit. An additional change requires another validation run.
4. Merge the approved candidate and repeat the release checks on the resulting
   clean `main` commit. Create the annotated tag on that tested commit, then
   publish the tag and GitHub release. Never move or reuse a published tag.

Run these commands inside the declared development/test environment, or use
`scripts/tools-command.sh python3 ...` for Python commands from the host:

```bash
python3 scripts/release-workbenches.py freeze
# Review and commit the candidate before checking it.
python3 scripts/release-workbenches.py check
python3 devcontainer.test/test-release-version.py
python3 devcontainer.test/test-setup-requirements.py
python3 devcontainer.test/test-setup-async.py
```

Run the Workstation Setup workflow's full regression, Tools runtime, credential,
and component lifecycle jobs. Validate a fresh workstation install as well as
upgrade/removal behavior; capture the workflow and manual-test results in the
release notes. To exercise frozen source preparation before tagging, run
`WORKBENCHES_FROZEN=1 ./setup.sh` from the clean candidate checkout. This uses
normal setup authorization and the selected components; it is a real install.

After the tested commit is on `main`, publish from its clean checkout:

```bash
git tag -a v1.5.0 -m 'workBenches 1.5.0'
python3 scripts/release-workbenches.py check --tag v1.5.0
git push origin refs/tags/v1.5.0
```

Wait for the tag's Release source freeze and Workstation Setup workflows to
succeed, then publish the GitHub release:

```bash
gh release create v1.5.0 --verify-tag --title 'workBenches 1.5.0' --notes-file RELEASE_NOTES.md
```

Prepare `RELEASE_NOTES.md` with the final tested changes and validation evidence
before running the publication command. Tag checking verifies the annotated
tag, version, clean assembly tree, and complete source-lock coverage. CI also
performs this check for `v*` tags. Protect release tags from updates/deletion in
the GitHub repository rules. The active **Immutable workBenches releases** tag
ruleset protects `refs/tags/v*` against updates and deletion, with no bypass
actors. Creating a new version tag remains allowed.

## Install a published release

Once the tag has been published:

```bash
curl -fsSL https://raw.githubusercontent.com/opensoft/workBenches/v1.5.0/bootstrap.sh -o workbenches-bootstrap.sh
bash workbenches-bootstrap.sh --branch v1.5.0 --setup
```

SSH access remains preferred, with HTTPS fallback. An exact release-tag checkout
automatically uses frozen source mode. Before applying selections, setup verifies
the source lock and prepares selected benches at their recorded commits. It
skips the setup TUI's fetch/pull-to-latest behavior. A mismatched or edited
existing bench stops the install; setup does not reset or overwrite local work.
Use a fresh directory (`--directory PATH`) to try another release alongside an
existing workstation checkout.

The source freeze covers assembly and bench repositories. It does **not** yet
promise a byte-identical workstation: external package managers, vendor CLI
installers, mutable base-image references, and bench-owned installer downloads
can still resolve newer packages. Shared-image manifests already use verified
digests where available. Full binary reproducibility requires locking and
validating the remaining external artifacts as a further release requirement.

Rolling back source means selecting the older release in a fresh checkout.
It does not automatically downgrade installed tools, containers, or user data;
those need a tested migration or restore procedure.
