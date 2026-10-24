# Dependent inventory and landing order

Status values: `pending`, `in-progress`, `ready`, `landed`, `verified`, `blocked`, or `not-required`. Update this record with relative PR/issue references as work lands; do not duplicate implementation tasks owned by dependent repositories.

| Dependency | Required compatibility or slug change | Order | Status / evidence |
|---|---|---|---|
| Current repository publisher | Exact `opensoft/workBenches` + `opensoft/openBenches` allowlist before cutover | Pre-rename | in-progress |
| Active release lines | Same publisher guard on any line that may publish during cutover | Pre-rename | pending |
| openRepoProject | New/old checkout discovery; preserve root/marker/flag overrides; current docs after cutover | Consumer first | pending |
| openRepoKit | Accept either checkout basename; preserve existing root ABI; propagate component/spec/assembly pins in order | Consumer first | pending |
| new-workstation | New/old checkout and config discovery; preserve AI-Credentials boundary and recovery identity | Consumer first | pending |
| openProfiler | Native/WSL new-first/legacy-fallback manifest selection; no duplicate profiles; docs after cutover | Consumer first | pending |
| Install-Wave-Terminal | New/old checkout discovery and root aliases; preserve generated artifacts and caches | Consumer first | pending |
| pyBench | Config/lib/state mount compatibility and checkout CI slug update | Consumer first, then immediate slug sweep | pending |
| cloudBench | Config mount compatibility and checkout CI slug update | Consumer first, then immediate slug sweep | pending |
| openRepoTools | New-first/legacy lane-handoff environment reads; canonical/legacy repo aliases after cutover | Consumer first, then immediate slug sweep | pending |
| flutterBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| frappeBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| goBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| phpBench | Checkout repository field only; preserve checker commit | Immediate slug sweep | pending |
| Opensoft-Tenant / AI-Credentials | Owner-led provider/path compatibility review without exposing inventories or payloads | Before fresh roots | pending |
| openWorkBenchesCli | Update current extraction-source links after cutover; do not consolidate the family | Immediate slug sweep | pending |
| GitHub repository/settings | Controlled admin rename; description/topics/ruleset display; verify org rules and environments | Gated cutover | pending |
| Release/QA runners | Dual labels, environment aliases, config fallback; pause only at approved cutover window | Runtime compatibility | pending |
| openWorkBenches App/Service/assembly | No implementation dependency detected; document product boundary only | not-required |

## Cutover evidence required

- Target-name availability and no new hosted-Action references.
- Quiet release/QA window and explicit admin approval.
- Old/new Git, raw bootstrap, release-asset, issue, and bench workflow verification.
- Org rulesets, repo tag ruleset, environments, variables, and Actions permissions verified without exposing secrets.
- Current direct-reference sweep complete; old strings remain only in the approved compatibility/history allowlist.
