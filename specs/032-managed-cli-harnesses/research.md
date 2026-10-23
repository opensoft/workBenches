# Source audit and implementation decisions

Audit date: 2026-10-23. The canonical 71-entry audit and public source URLs are
in [the installer registry](../../config/harness-installers.json) and the
[user guide inventory](../../docs/managed-cli-harnesses.md). Downloaded upstream
READMEs/metadata were audit inputs, not vendored executable code.

- npm package identity and exported commands were checked against package
  metadata and primary publisher documentation. Observed versions are audit
  evidence, not frozen install pins; each new install resolves the current release.
- Kimi Code uses `@moonshot-ai/kimi-code` (observed 2.3.1). Archived `kimi-cli`
  is a distinct Python distribution and receives a distinct public launcher.
- Regional Qoder distributions and operator labels stay distinct. Nori uses
  `nori-ai-cli`, not the missing/unrelated literal `nori-cli` package.
- ZCode's repository contains a real CLI entry. Build that package; do not
  substitute its desktop app. Devon needs both its Python backend and npm TUI.
  AutoCodeRover has a source/requirements entry point rather than an `acr`
  package console script. SWE-agent uses its source distribution, not an old stub.
- Current Deep Agents Code uses the documented dcode installer, not the deprecated
  deployment package named deepagents-cli. Current Open Interpreter uses its
  publisher installer rather than assuming the older Python client is equivalent.
- Forge's website installer returned 404; its official release provides a musl
  binary and GitHub asset digest. Plandex's script targets system directories;
  use its CLI release archive instead. `plandex version` is the unauthenticated
  verification command; `--version` enters its authentication flow.
- Prime's upstream installer can stop daemons and retire an old npm client.
  Its documented/code-defined defer-stop and preserve-bridge options are set for
  this separate owned installation. Kiro's force option bypasses migration of an
  unrelated existing Q client. Publisher scripts see staging HOME, not account HOME.
- Native script launchers are verified from an empty runtime home, not their
  staging HOME. Junie's updater shim is HOME-bound, so the recipe selects the
  bundle's actual platform CLI entry and supplies its project-directory variable.
- Tabnine's published installer and current maintenance guidance are retained;
  the launcher is named tabnine-cli to avoid its newer editor/plugin command.
- Mentat's current remote-agent product has no verified installer identity.
  Former AbanteAI source is unavailable; npm's same-name package is unrelated.
  Do not turn this into a guessed installation. The catalog retains an explicit
  unavailable reason while an official product URL is requested from the user.

Installation capability and account/profile support remain separate. Feature 031
is docs-only and is not silently enabled by adding a harness recipe.
