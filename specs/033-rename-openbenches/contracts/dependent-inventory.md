# Dependent inventory and landing order

Status values: `pending`, `in-progress`, `ready`, `landed`, `verified`, `blocked`, or `not-required`. Update this record with relative PR/issue references as work lands; do not duplicate implementation tasks owned by dependent repositories.

| Dependency | Required compatibility or slug change | Order | Status / evidence |
|---|---|---|---|
| Current repository publisher | Exact `opensoft/workBenches` + `opensoft/openBenches` allowlist before cutover | Pre-rename | landed — opensoft/workBenches#216 merged as `6809446`; 6 contract, 15 installer, 11 release-version, and 53 release-automation tests pass |
| Active release lines | Same publisher guard on `main`, `release/1.6.0`, and `release/1.7.0`, where recent publication runs occurred | Pre-rename | landed — #217 merged as `d51a19b` and #218 as `832b8b4`; 15 installer tests pass on each line |
| openRepoProject | New/old checkout discovery; preserve root/marker/flag overrides; current docs after cutover | Consumer first | landed — opensoft/openRepoProject#40 merged as `f271a39`; 103 tests and split-root/precedence smoke tests pass |
| openRepoKit | Accept either checkout basename; preserve existing root ABI; propagate component/spec/assembly pins in order | Consumer first | landed — code#2 `b0d847e`, spec#2 `c2a5f62`, assembly#2 `78dfd4b`; lockstep pins, `make validate`, `openRepoKit verify`, and 19 tests pass |
| new-workstation | New/old checkout and config discovery; preserve AI-Credentials boundary and recovery identity | Consumer first | landed — brettheap/new-workstation#63 merged as `353a2086`; 30 synthetic tests and coordinated Codex CLI review pass at `e4b2a83` |
| openProfiler | Native/WSL new-first/legacy-fallback manifest selection; no duplicate profiles; docs after cutover | Consumer first | landed — opensoft/openProfiler#29 merged as `1f3f375`; 27 Rust + 6 frontend tests, lint/format/build, and Windows-target checks pass |
| Install-Wave-Terminal | New/old checkout discovery and root aliases; preserve generated artifacts and caches | Consumer first | landed — opensoft/Install-Wave-Terminal#6 merged as `b4cbc56`; compatibility, generated-widget, lifecycle, syntax, and ShellCheck checks pass |
| pyBench | Config/lib/state mount compatibility and checkout CI slug update | Consumer first, then immediate slug sweep | landed — opensoft/pyBench#8 merged as `b105c4a`; 19 mount cases, devcontainer checks, and disposable Docker lifecycle with literal-dollar/apostrophe paths pass |
| cloudBench | Config mount compatibility and checkout CI slug update | Consumer first, then immediate slug sweep | landed — opensoft/cloudBench#9 merged as `f24a323`; mount matrix including spaced initialization, 21 existing tests, read-only bind smoke, and immutable bench checker pass |
| openRepoTools | New-first/legacy lane-handoff environment reads; canonical/legacy repo aliases after cutover | Consumer first, then immediate slug sweep | landed — opensoft/openRepoTools#341 merged as `ee07c0e`; Codex review clean; 262 handoff tests and 4,891 shell checks pass; required `tests` and `tests-no-submodule` CI jobs pass (2,080 passed, 977 skipped) |
| flutterBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| frappeBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| goBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| phpBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| Opensoft-Tenant / AI-Credentials | Owner-led provider/path compatibility review without exposing inventories or payloads | Before fresh roots | landed — Opensoft-Tenant#240 merged as `112508f`; AI-Credentials#3 merged as `4aacee76`; 51 synthetic checks and final Codex CLI review pass at `1e87cd3`, without real credential access |
| openWorkBenchesCli | Update current extraction-source links after cutover; do not consolidate the family | Immediate slug sweep | pending |
| GitHub repository/settings | Controlled admin rename; description/topics/ruleset display; verify org rules and environments | Gated cutover | verified — T008 completed on 2026-10-26 for repository ID `1072217222`; canonical URL PR #232 is open; redirects, settings, releases, tags, environments, and rules are verified |
| Release/QA runners | Dual labels, environment aliases, config fallback; pause only at approved cutover window | Runtime compatibility | pending |
| openWorkBenches App/Service/assembly | No implementation dependency detected; document product boundary only | Not required | not-required |

## T007 authorized cutover evidence

- Brett Heap explicitly approved the administrative rename on 2026-10-26: "approved, change the name". No release publication was authorized.
- At 2026-10-26T10:59:41Z, `opensoft/openBenches` returned HTTP 404. The source remained repository ID `1072217222`, `opensoft/workBenches`, with protected `main` at `409b75385b85ae417a0b89b5a78d77aa64c0d2fc`.
- Remote `main` and `033-rename-openbenches-cutover` matched the reviewed `409b753` base and `8543e172a1382e1615fcfd36673be69e047cb597` head. Release guards at `d51a19b44d73885f03e79ca0395e46409d4a04ad` and `832b8b4c0af4420ec9130fea8b513fb9692726dc` were unchanged.
- Remote `main`, `release/1.6.0`, and `release/1.7.0` each allowed publication only from the exact old/new repository pair. The cutover workflows contained no hosted-Action `uses:` reference to either repository.
- No active workflow runs remained. `GitHub QA session renewal and team authorization` (391043951) and `Release validation` (389947512) were disabled for the cutover window and confirmed `disabled_manually`; the existing nightly QA variable was `false`.
- The seven naming-contract checks and strict OpenSpec validation passed in `py-bench`. Existing repository rulesets, organization rulesets, environments, Actions permissions, release IDs, and tag targets were recorded for post-cutover comparison without reading secret payloads.

## T008 completed administrative cutover

- GitHub now serves repository ID `1072217222` as `opensoft/openBenches`; the old API name resolves to that same repository. The old name was not recreated. Protected `main` remains `409b75385b85ae417a0b89b5a78d77aa64c0d2fc`.
- Old and new Git `ls-remote` calls returned that same `main`. Old web and PR #231 URLs redirected to `openBenches` with HTTP 200. Old and new raw `v1.6.1/bootstrap.sh` responses had identical SHA-256 `95b59a95b938ea3b3ee6205a08c63b7a8068b2d37321e15ecff5803a395ac5e0`.
- All 14 pre-existing release IDs and 14 tag targets remained unchanged. The old-slug release URL downloaded the existing 742-byte `shared-images.json` asset successfully with HTTP 200. Historical frozen-install acceptance remains a later release-validation task.
- Description and topics now use `openBenches`, retaining `workbenches` as a search topic. Repository tag ruleset `25178577` is now displayed as `Immutable openBenches releases`; its tag condition and deletion/update protections are unchanged. Organization and branch rules, environment IDs and protection rules, Actions variables, and enabled/all Actions permissions match their pre-cutover state.
- The two scheduled workflows paused for the administrative window were restored to `active` at 2026-10-26T11:07:45Z. No publication workflow was dispatched.
- Both local clone families now use `https://github.com/opensoft/openBenches.git` as `origin`; their checkout directories and linked worktrees were not moved. Post-cutover 21 transport, 19 installer, and 7 naming-contract tests pass in `py-bench`.

## Cutover evidence required

- Target-name availability and no new hosted-Action references.
- Quiet release/QA window and explicit admin approval.
- Old/new Git, raw bootstrap, release-asset, issue, and bench workflow verification.
- Org rulesets, repo tag ruleset, environments, variables, and Actions permissions verified without exposing secrets.
- Current direct-reference sweep complete; old strings remain only in the approved compatibility/history allowlist.
