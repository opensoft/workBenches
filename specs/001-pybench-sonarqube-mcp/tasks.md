# Tasks: pyBench SonarQube MCP Routing

**Input**: Design documents from `specs/001-pybench-sonarqube-mcp/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/runtime-routing.md`, `quickstart.md`

**Tests**: Launcher and devcontainer tests are required by FR-011 and FR-012 and
must be written and observed failing before implementation.

**Organization**: Tasks are grouped by user story so each security and lifecycle
outcome remains independently verifiable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it changes a different file or performs an
  independent read-only check
- **[Story]**: Maps the task to the corresponding prioritized user story
- Every task includes an exact repository or feature-artifact path

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the separately versioned bench source in the generated
feature worktree without altering the active user checkout.

- [x] T001 Initialize and inspect the `devBenches/pyBench` submodule and record its clean baseline in `devBenches/pyBench/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish failing regression coverage before source changes.

**⚠️ CRITICAL**: No user story implementation begins until both focused tests
exist and fail for the missing behavior.

- [x] T002 [P] Add override-present, override-absent, quoting, and argument-preservation tests in `devcontainer.test/test-codex-profile.sh`
- [x] T003 [P] Add rendered environment, dual-network, external-network, and no-port regression checks in `devBenches/pyBench/tests/test-devcontainer-config.sh`
- [x] T004 Run both focused scripts and confirm their new assertions fail before implementation, retaining only non-secret evidence in `specs/001-pybench-sonarqube-mcp/quickstart.md`

**Checkpoint**: Regression tests demonstrate the current launcher and Compose
configuration do not satisfy the feature contract.

---

## Phase 3: User Story 1 - Use SonarQube MCP Inside py-bench (Priority: P1) 🎯 MVP

**Goal**: py-bench resolves the private proxy and Codex launched through the
profile launcher uses that private MCP URL.

**Independent Test**: Run the focused tests, resolve the proxy from py-bench,
receive HTTP 200 for MCP initialization, and list the private URL through
`codex-profile`.

### Tests for User Story 1

- [x] T005 [US1] Re-run `devcontainer.test/test-codex-profile.sh` and `devBenches/pyBench/tests/test-devcontainer-config.sh` after implementation and require both to pass

### Implementation for User Story 1

- [x] T006 [P] [US1] Translate `CODEX_SONARQUBE_MCP_URL` into one TOML-quoted Codex URL override in `base-image/files/codex-profile`
- [x] T007 [P] [US1] Supply the runtime URL and attach both networks in `devBenches/pyBench/.devcontainer/docker-compose.yml`
- [x] T008 [US1] Reconcile the live launcher/container and validate DNS, MCP initialization HTTP 200, and Codex MCP listing using `specs/001-pybench-sonarqube-mcp/quickstart.md`

**Checkpoint**: The container-side Codex workflow is functional without editing
the shared profile.

---

## Phase 4: User Story 2 - Preserve Host and Proxy Security Boundaries (Priority: P2)

**Goal**: The host route, unrelated MCP configuration, credentials, and private
proxy exposure remain unchanged.

**Independent Test**: Assert only the host loopback URL in the shared profile,
inspect proxy port bindings and network membership, and verify launcher tests
contain no credential handling.

### Tests for User Story 2

- [x] T009 [P] [US2] Add static assertions for one SonarQube-only override and no proxy port publication to `devcontainer.test/test-codex-profile.sh` and `devBenches/pyBench/tests/test-devcontainer-config.sh`

### Implementation for User Story 2

- [x] T010 [US2] Verify the unchanged host-profile URL, absence of public proxy bindings, and absence of token output using `specs/001-pybench-sonarqube-mcp/quickstart.md`

**Checkpoint**: Container reachability is proven without weakening host or proxy
security boundaries.

---

## Phase 5: User Story 3 - Retain the Fix Through Container Lifecycle (Priority: P3)

**Goal**: The same behavior survives restart and recreation from tracked source.

**Independent Test**: Repeat network, protocol, launcher, and host-profile checks
after restart and again after supported recreation.

### Implementation for User Story 3

- [x] T011 [US3] Rebuild the affected layered images in dependency order through `base-image/build.sh`, `devBenches/base-image/build.sh`, and `devBenches/pyBench/scripts/build-layer.sh`
- [x] T012 [US3] Restart py-bench and repeat the validation contract from `specs/001-pybench-sonarqube-mcp/contracts/runtime-routing.md`
- [x] T013 [US3] Recreate py-bench through supported Dev Containers/Wave tooling and repeat the validation contract from `specs/001-pybench-sonarqube-mcp/contracts/runtime-routing.md`

**Checkpoint**: Restart and recreation require no manual in-container repair.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Complete repository-level verification and governance handoff.

- [x] T014 [P] Run shell syntax, focused launcher, pyBench Compose, and relevant devcontainer repository tests listed in `specs/001-pybench-sonarqube-mcp/quickstart.md`
- [x] T015 Update validation evidence and final rebuild/recreation guidance in `specs/001-pybench-sonarqube-mcp/quickstart.md`
- [x] T016 Mark the OpenSpec-to-Speckit handoff complete in `openspec/changes/fix-pybench-sonarqube-mcp/tasks.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on submodule initialization and blocks all
  implementation.
- **User Story 1 (Phase 3)**: Depends on failing focused tests.
- **User Story 2 (Phase 4)**: Can validate static security invariants after the
  source edits; it does not require lifecycle work.
- **User Story 3 (Phase 5)**: Depends on User Story 1 implementation and User
  Story 2 security checks because it rebuilds and recreates live state.
- **Polish (Phase 6)**: Depends on all three stories.

### User Story Dependencies

- **User Story 1 (P1)**: Starts after Foundational and delivers the functional
  MVP.
- **User Story 2 (P2)**: Uses the same source diff but is independently accepted
  through host-profile and proxy-boundary checks.
- **User Story 3 (P3)**: Depends on the implemented route because it verifies
  lifecycle durability rather than adding a separate route.

### Within Each User Story

- Focused tests are written and observed failing before source edits.
- Launcher and Compose source edits can proceed independently.
- Static and protocol checks precede image rebuild/recreation.
- Restart validation precedes full recreation validation.

### Parallel Opportunities

- T002 and T003 affect separate repositories/files.
- T006 and T007 affect separate repositories/files.
- T009's launcher and Compose assertions can be prepared independently.
- T014 static/focused tests can be grouped where they do not contend for the
  live container.

---

## Parallel Example: User Story 1

```text
Task: "Translate the runtime URL in base-image/files/codex-profile"
Task: "Add the runtime URL and dual networks in devBenches/pyBench/.devcontainer/docker-compose.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Initialize the submodule and establish failing focused tests.
2. Implement the conditional launcher override and pyBench runtime configuration.
3. Reconcile live state and prove DNS, MCP initialization, and Codex listing.
4. Stop and validate the host profile and proxy boundary before lifecycle work.

### Incremental Delivery

1. Deliver private container routing without shared-profile mutation.
2. Prove security invariants independently.
3. Rebuild and validate restart/recreation durability.
4. Run the broader repository tests and close the governance handoff.

### Parallel Team Strategy

The launcher and pyBench Compose/test changes are file-independent and may be
developed in parallel after T001, but live Docker validation remains serialized.

## Notes

- `[P]` tasks change different files or perform independent read-only checks.
- `[USn]` labels map directly to the feature's prioritized user stories.
- Do not print secrets while capturing validation evidence.
- Do not modify the shared host profile.
