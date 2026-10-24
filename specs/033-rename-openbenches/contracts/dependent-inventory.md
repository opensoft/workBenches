# Dependent inventory and landing order

Status values: `pending`, `in-progress`, `ready`, `landed`, `verified`, `blocked`, or `not-required`. Update this record with relative PR/issue references as work lands; do not duplicate implementation tasks owned by dependent repositories.

| Dependency | Required compatibility or slug change | Order | Status / evidence |
|---|---|---|---|
| Current repository publisher | Exact `opensoft/workBenches` + `opensoft/openBenches` allowlist before cutover | Pre-rename | ready — local `4780e97`; 6 contract, 15 installer, 11 release-version, and 53 release-automation tests pass |
| Active release lines | Same publisher guard on `main`, `release/1.6.0`, and `release/1.7.0`, where recent publication runs occurred | Pre-rename | ready — main `4780e97`; 1.6 `2650068`; 1.7 `e77705f`; 15 installer tests pass on each line |
| openRepoProject | New/old checkout discovery; preserve root/marker/flag overrides; current docs after cutover | Consumer first | ready — local `0a5bf8c` + `edd45e4`; 103 tests and split-root/precedence smoke tests pass |
| openRepoKit | Accept either checkout basename; preserve existing root ABI; propagate component/spec/assembly pins in order | Consumer first | ready — code `f160de8`, spec `c1715d5`, assembly `fbdb889`; assembly validation + 18 tests pass; pins await landed legs |
| new-workstation | New/old checkout and config discovery; preserve AI-Credentials boundary and recovery identity | Consumer first | ready — local `f8c4ce2`; 19 synthetic compatibility tests and shell syntax checks pass |
| openProfiler | Native/WSL new-first/legacy-fallback manifest selection; no duplicate profiles; docs after cutover | Consumer first | ready — local `c630e65`; 27 Rust + 6 frontend tests, lint/format/build, and Windows-target checks pass |
| Install-Wave-Terminal | New/old checkout discovery and root aliases; preserve generated artifacts and caches | Consumer first | ready — local `b2644c2`; compatibility, launcher lifecycle, syntax, and ShellCheck checks pass |
| pyBench | Config/lib/state mount compatibility and checkout CI slug update | Consumer first, then immediate slug sweep | ready — local `98a8422`; mount matrix, devcontainer checks, and immutable bench checker pass |
| cloudBench | Config mount compatibility and checkout CI slug update | Consumer first, then immediate slug sweep | ready — local `e2b6937`; mount matrix, 21 existing tests, read-only bind smoke, and immutable bench checker pass |
| openRepoTools | New-first/legacy lane-handoff environment reads; canonical/legacy repo aliases after cutover | Consumer first, then immediate slug sweep | ready — local `576b39f`; 36 matrix + 100 skill + 105 shell regression tests pass |
| flutterBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| frappeBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| goBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| phpBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| Opensoft-Tenant / AI-Credentials | Owner-led provider/path compatibility review without exposing inventories or payloads | Before fresh roots | pending |
| openWorkBenchesCli | Update current extraction-source links after cutover; do not consolidate the family | Immediate slug sweep | pending |
| GitHub repository/settings | Controlled admin rename; description/topics/ruleset display; verify org rules and environments | Gated cutover | pending |
| Release/QA runners | Dual labels, environment aliases, config fallback; pause only at approved cutover window | Runtime compatibility | pending |
| openWorkBenches App/Service/assembly | No implementation dependency detected; document product boundary only | Not required | not-required |

## Cutover evidence required

- Target-name availability and no new hosted-Action references.
- Quiet release/QA window and explicit admin approval.
- Old/new Git, raw bootstrap, release-asset, issue, and bench workflow verification.
- Org rulesets, repo tag ruleset, environments, variables, and Actions permissions verified without exposing secrets.
- Current direct-reference sweep complete; old strings remain only in the approved compatibility/history allowlist.
