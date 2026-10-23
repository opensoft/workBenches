# Managed CLI harness installation

Branch: `032-managed-cli-harnesses` · Target: 1.7 · Created: 2026-10-23.
Authority: Brett requested planning, documentation and implementation, and selected
workstation plus selected bench containers. Governance:
[proposal](../../openspec/changes/manage-cli-harness-installation/proposal.md).

## Outcomes and acceptance

- **US1/P1**: A user selects any source-qualified terminal harness with the same
  install/update/remove controls as existing CLI entries, reviews and applies it,
  then runs its advertised command. Test every recipe's identity/platform/command
  mapping, actual dispatch, result and error propagation without inference/login.
- **US2/P1**: An update failure leaves the old runnable tool intact; removal keeps
  projects, credentials and foreign executables. Test occupied paths, partial
  downloads, interrupted updates, concurrent requests and modified receipts.
- **US3/P1**: Reviewed tools install on the workstation and selected benches only.
  Test valid running, stopped, absent, foreign and remote-engine targets, image
  reconstruction and host/container user/path differences.
- **US4/P2**: Filters and queued selections remain usable across 77 terminal rows,
  including older/region-specific products with colliding upstream command names.
  Test narrow layouts, hidden queued rows, read-only inventory and cancellation.

## Requirements

- **FR-001**: Audit all 71 currently manual terminal IDs, using current upstream docs/repositories and package metadata. Record install method, actual command, platform/runtime prerequisites and provenance. Unknown/unavailable products remain explicitly blocked with a reason; never silently substitute another product.
- **FR-002**: Expand managed IDs, native/Python plan validation, dependencies, status and apply/removal dispatch consistently from one recipe source. Preserve existing IDs, ordering, filters, GUI/editor rows and credential distinctions.
- **FR-003**: Support audited npm, isolated Python tools, native installers and source/build distributions as needed; resolve current releases and record actual installed identity/version. Downloads/builds are bounded and cancellable, with actionable prerequisite failures.
- **FR-004**: Install under a validated user-owned prefix, use per-component locks and atomic activation after verification, preserve the previous install on failure and expose only declared non-conflicting commands. Never overwrite an unrelated executable or claim that executing an installer proves success.
- **FR-005**: Uninstall only owned receipt-bound payload/launchers, preserving projects, vendor homes, profiles and external installations. Reject traversal, symlink escapes, forged/foreign receipts and changed launchers. Report an external remaining copy accurately.
- **FR-006**: Targets are the workstation and install/update-selected benches in the reviewed plan. Unselected benches are untouched. Validate the local Docker endpoint and exact selected resources; never stop/recreate running sessions for a CLI change or execute as an arbitrary root user.
- **FR-007**: Persist each selected bench's desired CLI IDs without credentials, apply to matching running containers and include them in subsequent personalized image builds. Desired-list changes affect image freshness. Missing/stopped targets have explicit pending outcomes, not a false installed claim.
- **FR-008**: No credentials, keys or account sessions enter recipes, build arguments, images or logs. Installation does not sign in, select a provider model, spend inference quota or enable feature 031's pending credential adapters.
- **FR-009**: Workstation Ready requires the owned launcher to resolve through the native command search; a missing/shadowed launcher directory reports PATH setup needed with explicit startup-file guidance and a nonzero apply result, retaining the verified payload and leaving shell files unchanged. Keep first paint, rendering without discovery, Review/Apply semantics and responsive filtering intact. Failures retain the failed action and don't clear unrelated pending changes; queued hidden entries remain in Review.
- **FR-010**: Validate fixtures, representative real distribution installs and exact-head CI. Distinguish source-audited, fixture-verified, real-smoke-tested and unavailable entries; do not claim all products/platforms were live-tested from one example.

## Success criteria

SC-001: All 71 manual IDs have explicit audited disposition; every enabled recipe
has deterministic dispatch/identity/negative tests. SC-002: failed updates and
removals preserve prior runtimes and all credential/project canaries. SC-003:
selected target persistence/reconstruction and foreign-target denial pass.
SC-004: existing setup/catalog/filter/lifecycle suites pass without widening GUI
or credential authority. Exact source and installed outcomes are recorded.

## Clarification

2026-10-23: install scope → **Workstation and selected bench containers**.
No request to install all tools on Brett's current machine by default; implement
the selectable automatic installation capability for the full terminal inventory.
