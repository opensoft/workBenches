# Review and verification

Run `./setup.sh`, open G Profiles → Personal & companies, add/open a company or
personal identity, then open AI profiles (or F). Use a disposable metadata-only
file to review source/selection/cancellation first. Imported sources can then be
refreshed; Recover credentials is separate and restricted to that scope.

For isolated verification run the commands recorded in tasks.md. The validation
source copy is `/tmp/openbenches-profile-implementation-qt85prwg`; detailed unit
output is `/tmp/openbenches-profile-validation.log`. Temporary fixture files and
runtime containers never use production provider tokens. The runtime service
uses its declared Compose definition and cleans its own tools/connection fixtures.

The 1.6.2 worktree preserves its existing build cache and cloudBench checkout.
Do not change release pins or treat code application as a release publication.
Native file selection is tested through fake platform executables and host RPC;
attended dialog/provider/vault acceptance remains pending.

The source lock passed in a clean, committed validation snapshot. Running the
release gate directly in the development worktree still encounters its preserved
cloudBench checkout at e825af4 while the release lock pins 1d4623d, plus the
uncommitted implementation. These existing/development differences are not a
reason to rewrite release pins or discard the installed bench.
