# Fleet execution evidence

2026-10-21: inventory found 280 active repositories including 12 personal
repositories with no active workflow definitions. 238 checked-in active workflow
definitions were fetched; stale workflow records whose files no longer exist are
recorded separately. The runner-only patch planner produces 201 changed
definitions, 316 selectors and 80 repositories. Those are planned changes, not
completed migrations. Generated default-setup CodeQL jobs need separate treatment.

Selected-repository `Eagle Linux` groups were provisioned in InkRouter (7
repositories), MedxSoft (4), codeXfactory (1), ledgerXfactory (1), and opensoft
(67). Public-repository allowance is enabled only where selected targets include
public repositories. Existing specialist runner groups and midNet groups were
preserved. Host-local group snapshots and configuration retain exact selections.

General-worker image build succeeded with Python 3.12, Node 22, GitHub CLI,
Docker CLI/buildx, sudo, shell tools and Bubblewrap. A disposable rootless engine
proved UID 1001 operation, sudo, the rootless user mapping, a Docker action's
workspace roundtrip, localhost connectivity to a service container, public HTTPS,
private-address denial, Bubblewrap and apt update. Result marker:
`EAGLE_GENERAL_COMPATIBILITY_PASS`. Both probe containers and their anonymous
volumes were removed and absence verified. No bench or host service was restarted.

Ten focused tests pass for public-only DNS connections, queue selection, busy
registration protection, and byte-preserving direct/matrix/conditional routing.
Actionlint passes for the first changed workflow. Strict OpenSpec validation and
git diff checks pass. The first actual routed GitHub jobs are workBenches
DevBenches Helper Safety push run 39653972082 and PR run 39654023739; their
completion and cleanup must be recorded before this becomes fleet acceptance.

Remaining: qualify Ubuntu 22, cloud and other tool profiles; preserve KVM/swap
requirements through qualified execution rather than deleting tests; resolve
native Windows/macOS capacity; land pinned providers before coherent consumer
pin advancement; preserve shape-copy and CI integrity gates; perform and verify
each repository's actual migration. Broad fleet completion is not claimed.
