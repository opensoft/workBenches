## Purpose

Rename the GitHub repository and migrate direct consumers without interrupting publication, dependent CI, or supported releases.

## ADDED Requirements

### Requirement: Controlled slug cutover

The repository SHALL move from `opensoft/workBenches` to `opensoft/openBenches` only after dependent safeguards and an explicit administrative cutover gate are satisfied.

#### Scenario: Name availability and active QA

- **WHEN** cutover is requested
- **THEN** the target name is rechecked, affected scheduled activity is paused, active runs are allowed to finish, and an org owner/repository admin performs the rename with explicit approval.

#### Scenario: Redirect preservation

- **WHEN** the rename completes
- **THEN** old and new Git locations are verified, local remotes are updated without moving checkouts, and `opensoft/workBenches` is never recreated as another repository.

### Requirement: Dependent-reference migration

Direct repository references SHALL be updated in consumer-first order without relying permanently on redirects or rewriting historical records.

#### Scenario: Bench workflows

- **WHEN** the five affected bench workflows are updated
- **THEN** their checkout repository becomes `opensoft/openBenches` while the immutable checker commit remains unchanged and each workflow is validated.

#### Scenario: Alias and pin propagation

- **WHEN** upstream Project, Tools, bench, Wave, or Kit contracts change
- **THEN** component changes land before their code/spec revisions, vendored pins, child gitlinks, assembly pins, and release locks advance through normal tooling.

### Requirement: Publication identity and release continuity

Publication safeguards SHALL accept only the explicitly authorized old and new repository identities during cutover, and release automation SHALL remain compatible with supported source lines.

#### Scenario: Publication during transition

- **WHEN** an active release line publishes during the transition
- **THEN** its exact old/new repository allowlist permits only the intended source repository and does not broaden publication authority.

#### Scenario: Historical or current candidate validation

- **WHEN** automation runs against supported 1.5, 1.6, 1.7, or current source
- **THEN** required legacy entrypoints and old artifact readers remain available and the applicable release tests pass.

#### Scenario: First openBenches release

- **WHEN** the first `openBenches` release is published
- **THEN** its exact tested commit has passed the full applicable release gate and protected QA, and no old release was retagged or edited.
