# Implementation plan

1. Add validated, private identity metadata storage with stable company IDs.
2. Add personal-first onboarding and verified GitHub linking through the native
   workstation GitHub CLI, then repeated company creation and scoped sign-in.
3. Add the Profiles TUI page without changing queued component selections or
   blocking the immediate first draw on discovery.
4. Connect identity metadata to existing AI setup while preserving other profiles.
5. Document the v1.6 boundary and run isolation, navigation, rendering, account,
   async-startup, and existing AI profile checks.


## Multiple identities and GitHub connections (2026-10-17)

- Version-2 metadata preserves company IDs/session roots and backs up version 1
  on first interactive migration. Each scope has multiple named identities and
  an explicit default; GitHub records are deduplicated by immutable numeric ID.
- Keyboard tree/detail panes support add/edit/default/link/unlink with narrow
  terminal scrolling. Native gh account discovery and device sign-in are in the
  TUI, including URL/code, explicit browser/clipboard actions, and cancellation.
- Existing gh credentials are verified per username without switching accounts;
  new connections use isolated native GH_CONFIG_DIR values. Secrets remain with
  gh and never enter profile metadata or terminal diagnostic output.
- Validate migration, preservation, multiple identities, shared links, defaults,
  account mismatch, check/re-auth states, fake device flow/cancellation, narrow
  frames, and real PTY navigation. Repeat existing workstation and broker suites.


Validation completed for the multiple-identity implementation: 13 dedicated
migration/account-isolation/terminal tests; 15 existing Profiles tests; 15 account
helper tests; all 22 Workstation Setup regression suites; all 30 declared
broker/client/CPC fixture tests; declared Tools-runtime acceptance including
native gh discovery, per-account verification, asynchronous pending approval,
browser/clipboard callbacks, Vault lifecycle, and Profiles cancel/back with a
queued bench retained. Syntax/compile, workflow YAML, and whitespace checks pass.
No real GitHub account was authorized by automated tests. Real browser approval
and Windows/WSL acceptance remain required before release.

## v1.6.1 private bench authentication repair (#210)

Preserve the existing native GitHub credential boundary during bench source
preparation: Git inside Tools appends a GitHub-scoped, command-local gh helper
resolved through the native bridge. Existing helpers and native account choice
remain authoritative; Profiles defaults do not route Git commands. Keep SSH
preference, anonymous public access, immutable source pins and destination
preservation. Add actionable failure guidance and verify authentication fallback,
missing/denied access, retry, submodules, and exact frozen revision checkout.

Verification on Raven, 2026-10-23: all 19 transport tests, all 13 source/version
tests and all 23 setup manifest commands passed in the declared workstation
test container. Five new transport cases and the interrupted submodule retry
case failed before their fixes. A real private cloudBench clone through the
production Tools/native-gh bridge checked out locked revision
`1d4623d9772e3d2fbe48e84ef4136d8108eda66d` and completed submodule preparation;
the temporary checkout was removed. This is source-preparation evidence, not
full bench installation, browser-login or protected release acceptance.

CI follow-up: hosted Ubuntu already provides gh, exposing a retry-test fixture
that mistook executable availability for authentication. Reproduced with an
unauthed system gh stub in the declared test container. The fixture now keeps
gh installed throughout, explicitly denies credentials on the first clone,
then returns synthetic credentials for the retry. No production change is
needed for this correction.
All 19 transport and 13 source/version tests passed with the unauthenticated
system gh stub present after the fixture correction.
