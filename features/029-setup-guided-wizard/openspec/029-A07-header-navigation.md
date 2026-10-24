# 029-A07 — Separate product header and navigation

- Governing change: `openspec/changes/setup-guided-wizard/`.
- Decision authority: Brett Heap, 2026-10-24 chat: use the v1.6-style product/OS row, add lines above and below the navigation bar, highlight its selected item, and reload the existing v1.7 preview.
- Classification: bounded visual refinement; supersedes A03's adjacent brand and OS-in-divider placement.
- Layout: logo, blank row, `openBenches v1.7` left and detected OS right, full-width rule, navigation, full-width rule. Selected navigation uses a bold light background in full and compact forms; existing labels, readiness marks, counts and keys remain.
- Responsive budget: the two additional header rows reduce the 80×24 Software Engineering About window from four to two rows; all eight bench rows, the focused item, navigation and footer remain visible. A full logo needs 43 columns now that the brand has its own row.
- Scope: renderer, existing layout expectations, current UI documentation and governing layout specifications. No installers, credentials, release identifiers or apply behavior change.
- Verification: 46 wizard behavior tests and 23 layout tests pass in the declared workstation test image, including both locale matrices and size/height bounds. OpenSpec strict validation passes. The reloaded native preview was visually checked in the original workspace-14 pane.
