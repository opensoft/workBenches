# Analysis and requirement coverage

The implementation follows the clarified workstation + selected bench scope.
No release tags, source pins or provider credential privileges are added.

| Requirement | Implementation and evidence |
| --- | --- |
| FR-001 | Registry covers exactly 71 additional terminal IDs; 70 typed recipes and explicit Mentat unavailable/source-needed disposition. Catalog/registry tests reject drift and non-terminal promotion. |
| FR-002 | Compiler derives managed keys, detection, About and Node dependencies; native and Python plan readers agree for every enabled ID/action. GUI/IDE/extension rows stay manual. |
| FR-003 | npm, isolated Python, publisher scripts, Git Python/requirements/Node builds and digest-checked releases. Native platform/architecture are read through the host boundary. Source fixtures produce runnable launchers; nine real public distributions pass. |
| FR-004 | Per-ID locks, private staging, actual-launcher verification from an empty runtime home, receipts and atomic activation with rollback. Native/local cancellation terminates child process groups; an unconfirmed native cancellation retains the unactivated candidate rather than deleting under a live writer. |
| FR-005 | Receipt/source/entry/launcher hashes and owned directory boundaries gate status/removal. External launchers and account/project files survive. Removal is idempotent for partial-target retries. |
| FR-006 | Review wraps all exact target names. Local socket/context and ordinary bench resource validation precede workstation mutation; live Docker exec uses immutable ID and non-root user. Operation-bound cancellation checks process identity. |
| FR-007 | Private LF-only ID lists with locks and atomic writes; selected IDs affect personalized image fingerprints and isolated build contexts. Stopped/missing/failed targets report pending, retain rebuild intent and return nonzero. Live Docker and fresh-image-container smokes pass. |
| FR-008 | Recipes/selection/image contexts contain no provider keys or sessions. Staging environment strips credential variables. Installation never signs in, runs paid prompts or enables feature 031 adapters. |
| FR-009 | Existing first-paint/async, filter/queue, layout and lifecycle tests pass. Review rendering remains fork-free. Failed actions return nonzero and do not clear in-memory selections; setup retains its existing exit behavior, so a later invocation requires selecting the desired retry again. Durable bench intent is independently saved. |
| FR-010 | Fixture/native-boundary/public-package/Docker results are distinguished in acceptance.md. All 41 local suites pass after updating two fixture dependency copies; strict OpenSpec validation passes. |

The sole upstream-source gap is Mentat's current remote-agent product identity,
which is exposed as unavailable under FR-001 rather than guessed from an unrelated
package. The user has been asked for its official URL. The other 61 enabled
recipes are source-audited, not claimed as fully live-qualified on every platform.
Full production bench image and authenticated workflow qualification remain part
of normal 1.7 acceptance; source audit and fixture success do not imply those runs.
