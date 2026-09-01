# Implementation Plan: pyBench SonarQube MCP Routing

**Branch**: `001-pybench-sonarqube-mcp` | **Date**: 2026-07-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-pybench-sonarqube-mcp/spec.md`

## Summary

Give py-bench a private route to the existing SonarQube MCP proxy while keeping
the host profile and proxy boundary unchanged. The implementation adds a second,
external network and a runtime URL to pyBench Compose configuration, then makes
the shared profile launcher conditionally translate that URL into the supported
one-run Codex configuration override. Focused shell tests, rendered Compose
checks, protocol initialization, Codex MCP listing, and restart/recreation checks
provide end-to-end evidence.

## Technical Context

**Language/Version**: GNU Bash 5.2; Docker Compose Specification (Compose v5.3)

**Primary Dependencies**: Codex CLI 0.145 configuration precedence; `jq` 1.7 for
TOML-compatible string quoting; Docker Engine/Compose; Dev Containers CLI;
existing SonarQube MCP proxy

**Storage**: Repository configuration files and existing bind-mounted Codex
profiles; no new persistent data

**Testing**: Standalone Bash launcher test, `bash -n`, `docker compose config`,
repository devcontainer tests, Docker DNS checks, HTTP/MCP protocol probe, and
real `codex mcp list`

**Target Platform**: WSL host managing Linux devcontainers through Docker

**Project Type**: Layered container/tooling monorepo with separately versioned
bench submodules

**Performance Goals**: Add no observable interactive startup delay; complete
launcher argument construction synchronously without network access

**Constraints**: Preserve the host loopback URL; override only SonarQube MCP;
retain py-bench's default network; do not expose proxy ports or credentials;
preserve unrelated checkout changes; survive restart and recreation

**Scale/Scope**: One shared launcher, one focused launcher test, one pyBench
Compose service, two Docker networks, one live bench container, and one existing
shared MCP service pair

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

The repository constitution is an unratified template and contains no
enforceable project-specific principles. The following binding gates come from
the global workflow and approved feature specification:

- **PASS — Governance before implementation**: OpenSpec change
  `fix-pybench-sonarqube-mcp` is complete and valid and hands off to this single
  feature.
- **PASS — Source-of-truth and portability**: Changes target tracked launcher
  and Compose sources and introduce no host-absolute paths.
- **PASS — Security boundary**: No token handling changes, proxy publication, or
  shared-profile mutation are permitted.
- **PASS — Test-first coverage**: Focused launcher and rendered Compose checks
  precede live reconciliation.
- **PASS — Change isolation**: Implementation is developed in this worktree and
  mirrored narrowly into the active checkout only for live validation, without
  discarding unrelated edits.

Post-design re-check: all contracts and validation steps preserve these gates;
no exceptions require complexity justification.

## Project Structure

### Documentation (this feature)

```text
specs/001-pybench-sonarqube-mcp/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── runtime-routing.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
base-image/
└── files/
    └── codex-profile

devcontainer.test/
├── test.sh
└── test-codex-profile.sh

devBenches/
└── pyBench/                         # separate Git submodule
    └── .devcontainer/
        └── docker-compose.yml
```

**Structure Decision**: Extend the existing shared launcher at its Layer 0
source, add its regression test beside the Layer 0 devcontainer suite, and keep
bench-specific network/environment behavior in the pyBench submodule's existing
Compose source. No new runtime service or credential store is introduced.

## Complexity Tracking

No constitution violations or additional architectural layers are required.
