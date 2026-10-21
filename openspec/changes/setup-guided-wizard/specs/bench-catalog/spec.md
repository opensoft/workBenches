# Spec Delta: bench-catalog

## Purpose

Defines the bench catalog in `config/bench-config.json` as a data contract: its
categories and per-bench presentation fields, completeness against the release
lock, accuracy of bench descriptions, name-safe lookups by shell consumers, and
preservation of the metadata by catalog maintenance scripts.

## ADDED Requirements

### Requirement: Bench categories
`config/bench-config.json` SHALL define a top-level `categories` object mapping the ids `software-engineering`, `science`, `system-administration` and `electrical-engineering` to a `label`, a numeric `order` and a one-line `summary`, and every bench's `category` SHALL name a defined id.

#### Scenario: Catalog categories are valid
- **WHEN** the catalog test loads `config/bench-config.json`
- **THEN** it finds the four category ids, each with a non-empty `label`, an integer `order` and a non-empty `summary`
- **AND** every bench's `category` is one of those ids

#### Scenario: Electrical Engineering awaits benches
- **WHEN** the catalog test groups benches by category
- **THEN** `electrical-engineering` has no benches and `software-engineering`, `science` and `system-administration` each have at least one

### Requirement: Bench presentation fields
Every catalogued bench SHALL have a `category`, a `tagline` of at most 35 characters, a non-empty `description`, and non-empty `usedFor` and `contains` lists of single-line strings, and none of these values SHALL contain control characters.

#### Scenario: Complete presentation fields
- **WHEN** the catalog test checks every bench
- **THEN** each has the five fields with the required types and limits

#### Scenario: Over-long tagline
- **WHEN** a bench's `tagline` is 36 characters long
- **THEN** the catalog test fails and names that bench

### Requirement: Complete catalog
The catalog SHALL contain an entry, with matching `path` and `url`, for every bench repository recorded in `config/release-lock.json`, including goBench (`devBenches/goBench`), rustBench (`devBenches/rustBench`) and 365Bench (`sysBenches/365Bench`). Each entry SHALL be offered by the setup TUI, accepted in selection files, and listed as a TUI option in `config/credential-requirements.json`.

#### Scenario: Lock and catalog agree
- **WHEN** the catalog test compares catalog paths and URLs with the repositories in `config/release-lock.json`
- **THEN** every locked bench repository has a catalog entry with the same path and URL

#### Scenario: New bench in a selection file
- **WHEN** a private selection file requests `bench_365Bench` with action `install`
- **THEN** `setup_selection.py` accepts it and its `benches` command prints `sysBenches/365Bench`

#### Scenario: Credential requirements follow the catalog
- **WHEN** the credential plan test loads `config/credential-requirements.json`
- **THEN** goBench, rustBench and 365Bench are TUI options rather than submodule-only entries

### Requirement: Accurate bench descriptions
Catalog text SHALL describe only what a bench's image provides. simBench SHALL be described as molecular simulation and protein structure work with OpenMM and ESM on CPU PyTorch, and its `tagline`, `description` and `contains` SHALL NOT claim bundled AlphaFold or ESMFold models or weights.

#### Scenario: simBench text
- **WHEN** the catalog test reads simBench's `tagline`, `description` and `contains`
- **THEN** they mention OpenMM and ESM and do not mention AlphaFold or ESMFold

### Requirement: Name-safe catalog lookups
Every shell consumer of the catalog SHALL look a bench up by passing its name to jq as an argument (`--arg`) and indexing `.benches[$name]`, never by interpolating the name into a jq path, so that bench names beginning with a digit resolve correctly.

#### Scenario: Digit-leading bench resolves everywhere
- **WHEN** a fixture catalog contains `365Bench` at `sysBenches/365Bench` and each consumer looks it up (`interactive-setup.sh` status and apply paths, `scripts/setup-workbenches.sh`, `scripts/update-project.sh`, `scripts/launchBench`)
- **THEN** each resolves `sysBenches/365Bench` and its description and URL from the catalog

#### Scenario: No interpolated lookups remain
- **WHEN** the static check scans the repository's shell scripts
- **THEN** no jq filter builds a `.benches.` or `.infrastructure.` path from a shell variable

### Requirement: Unresolved bench paths fail closed
When a selected bench's catalog path cannot be resolved to a directory under `devBenches/`, `sysBenches/` or `bioBenches/`, setup SHALL report that bench as failed and SHALL NOT run git, a clone or a setup script for it, and SHALL never use the workBenches root as a bench directory.

#### Scenario: Lookup failure does not touch the root
- **WHEN** a selected bench's path lookup returns nothing during apply
- **THEN** that bench is reported as failed
- **AND** no git fetch, pull or clone runs in the workBenches root and the root `setup.sh` is not run for it

### Requirement: Maintenance scripts preserve metadata
`scripts/update-bench-config.sh` and `scripts/new-bench.sh` SHALL keep the top-level `categories` and every existing per-bench field when they rewrite the catalog, and a bench they add SHALL receive a `category` derived from its path.

#### Scenario: Regeneration keeps presentation fields
- **WHEN** `update-bench-config.sh` regenerates a catalog whose benches have `category`, `tagline`, `usedFor`, `contains` and `ai_keywords`
- **THEN** the rewritten catalog still has `categories` and every one of those fields unchanged

#### Scenario: New bench gets a category
- **WHEN** `new-bench.sh` adds a bench under `devBenches/`
- **THEN** the new entry has `category` `software-engineering`
