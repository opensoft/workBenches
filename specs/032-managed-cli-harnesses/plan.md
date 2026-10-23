# Plan: managed CLI harnesses

Reuse feature 029's reviewed action queue and separate feature 031's credential
work. The initial audit covers 71 manual CLI rows, including legacy/regional
variants. Verify upstream identities before adding install commands.

Use one typed installer registry and a Python execution engine under Tools/native
callbacks for workstation package operations. Keep package/runtime payloads under
owned per-component version prefixes with stable launchers, receipts, locks and
atomic activation. Native installer scripts run in a staging home; do not edit
the user's shell/account files. Unsupported distributions fail before mutation.

Derive the managed catalog/selection/dependency data from that registry. Preserve
flat ordering and existing manual GUI rows. Installed status verifies owned
payload/provenance rather than assuming any same-named binary is this SKU.

Apply reviewed target lists to exact local bench resources using existing Docker
identity checks. Install into running benches as their configured non-root user.
Persist per-bench desired IDs and include them in isolated Layer 3 build contexts;
fingerprints include the desired list. Rebuilds re-materialize requested tools
without copying host binaries or credentials across OS/home boundaries. Never
restart a live container implicitly; show pending outcomes for unavailable targets.

Testing uses synthetic upstream packages/installers, controlled process runners,
filesystem and Docker boundary fixtures, plus representative real public package
smokes in disposable declared containers. Run existing catalog/filter/setup/image/
lifecycle suites. Do not launch paid agents during install verification.

Governed paths: `config/` (recipes and selection contracts), generated catalog
snapshots, install/removal execution, bench resource validation, Layer 3 identity,
CI and OpenSpec text. Implementation is on this linked worktree. Existing 1.7
publication gates remain; do not advance VERSION, tags or source pins.
