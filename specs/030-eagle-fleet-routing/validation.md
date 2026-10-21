# Fleet execution evidence

2026-10-21: inventory found 280 active repositories including 12 personal
repositories with no active workflow definitions. 238 checked-in active workflow
workflow records were inventoried, of which 223 source files exist; 15 stale
records whose files no longer exist are recorded separately. The runner-only patch planner produces 201 changed
definitions, 316 selectors and 80 repositories. Those are planned changes, not
completed migrations. Generated default-setup CodeQL jobs need separate treatment.

Selected-repository `Eagle Linux` groups were provisioned in InkRouter (7
repositories), MedxSoft (4), codeXfactory (1), ledgerXfactory (1), and opensoft
(67 initially; 91 after adding 24 repositories with active default-setup CodeQL).
There are now 104 selected repositories across the five groups. Public-repository allowance is enabled only where selected targets include
public repositories. Existing specialist runner groups and midNet groups were
preserved. Host-local group snapshots and configuration retain exact selections.

General-worker image build succeeded with Python 3.12, Node 22, GitHub CLI,
Docker CLI/buildx, sudo, shell tools and Bubblewrap. A disposable rootless engine
proved UID 1001 operation, sudo, the rootless user mapping, a Docker action's
workspace roundtrip, localhost connectivity to a service container, public HTTPS,
private-address denial, Bubblewrap and apt update. Result marker:
`EAGLE_GENERAL_COMPATIBILITY_PASS`. Both probe containers and their anonymous
volumes were removed and absence verified. No bench or host service was restarted.

Twenty focused tests pass for public-only DNS connections, queue selection, busy
registration protection, and byte-preserving direct/matrix/conditional routing.
Actionlint passes for the first changed workflow. Strict OpenSpec validation and
git diff checks pass. The first actual routed GitHub jobs are workBenches
DevBenches Helper Safety push run 39653972082 completed successfully on
`eagle-fleet-ca9d95d84cd5` (job 119409242455, 2026-10-21 18:56:49–18:57:13 UTC).
Cleanup verified its registration, outer containers and private volumes absent
at 18:57:45 UTC. Superseded PR runs 39654023739 and 39655330244 were cancelled;
current-head run 39657321571 remains the landing check.

The next actual job, flutterBench run 39656625395, exposed a missing Docker
Compose plugin in the general image. Its checker was left unchanged. The plugin
was added from the same pinned Docker CLI source, the image rebuilt, and worker
preflight now requires Compose. The failed job was requeued for verification.
A transient zombie error during cleanup of an unassigned subsequent backend
settled to exited; retry verified cleanup at 19:06:18 UTC, without a daemon or
bench restart. Future rootless backends use an outer init and TINI_SUBREAPER.

Routing PRs: workBenches #208, flutterBench #7, goBench #6, phpBench #5,
frappeBench #4. All four bench PRs have clean Codex reviews for their exact
heads; their real CI remains a landing gate. WorkBenches review findings about
predicate preservation, selector scope, complete label matching and pagination
were fixed with regression tests. The subprocess audit finding was addressed by
an explicit executable allowlist, argv-only execution with shell=False, and a
narrow documented audit annotation; unrelated rules remain enabled.

CodeQL inventory: 82 repositories have default setup configured, 29 with supported
languages and 53 currently without a supported language. Routing default setup
requires a separate settings request; group access alone changes no scan route.
The first workBenches request was unsuccessful with settings unchanged; a bounded
reconciled retry is waiting for an eligible online runner. Broad CodeQL migration
is not yet accepted.

Subsequent execution: goBench #6 and phpBench #5 passed their real validation jobs,
received clean Codex reviews for their exact heads, and merged normally as
40cf11cf7eced47aa5e7d2602bb9f19c9a0c7185 and
c5bd941ca198aa8b0694a9b0bd4f6e88cb3220f3. Their default branches now route to Eagle.
WorkBenches current-head run 39657321571 passed on Eagle. Its CodeQL default setup
now reads `runner_type: labeled`, `runner_label: eagle-linux-ubuntu24`, with original
languages, query suite, threat model and schedule preserved. Another repository's
request was rejected while no eligible runner was registered; its settings were
left unchanged. Remaining CodeQL routing needs an eligible-runner window.

A later review correctly identified that forced runner deletion is not a busy-job
barrier. Retirement now observes the exact detached listener exec before
unregistering; STOP does not force removal of an idle registered listener. A
root-owned job-started hook blocks workload code until the Windows controller
has persisted its deadline. An isolated lifecycle probe verified exec creation,
start, running/exited state and cleanup with result `EAGLE_EXEC_LIFECYCLE_PASS`.
The new mode ran phpBench main run 39661180501 successfully; Windows state recorded
`job_assigned: true`, a persisted deadline and `hook_acknowledged: true`. A
supplemental process listing hit a rootless cgroup limitation and was removed in
favor of the authoritative exact exec status. That exec read stopped with exit
code 0; cleanup verified at 19:44:01 UTC. The existing job was preserved during
the observer errors. Gateway provisioning/runtime checks now reject image drift,
and workflow-run discovery paginates all active run pages.

Ubuntu 22 image built successfully against a pinned Ubuntu 22.04 base with the
official runner binaries; its listener version check passed. Nested execution
qualification and workflow activation remain pending for that profile.

Remaining: qualify Ubuntu 22, cloud and other tool profiles; preserve KVM/swap
requirements through qualified execution rather than deleting tests; resolve
native Windows/macOS capacity; land pinned providers before coherent consumer
pin advancement; preserve shape-copy and CI integrity gates; perform and verify
each repository's actual migration. Broad fleet completion is not claimed.
