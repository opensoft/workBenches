# Pi multi-account profiles

workBenches isolates Pi Coding Agent state by canonical AI identity. The same
name and alias used by `pclaude`, `pcodex`, `pgemini`, `pgrok`, and `pglm` is
accepted by `ppi`.

```bash
ppi list
ppi login team001
ppi status team001
ppi team001
```

`ppi team001` resolves to `team-001` and sets:

```text
PI_CODING_AGENT_DIR=~/.pi-profiles/profiles/team-001/agent
```

Pi stores that profile's settings, sessions, and `auth.json` beneath the
isolated directory. The standard `~/.pi/agent` home remains untouched.

## Authentication

Run `ppi login PROFILE`, enter `/login` inside Pi, choose a provider, and
authenticate with the email printed by the launcher. A single canonical Pi
profile can hold several Pi provider records when they belong to the same
identity.

Pi OAuth credentials are not interchangeable with Claude Code or Codex CLI
credentials. Setup never copies them automatically. This matters especially
for subscription products: support and billing in a third-party harness may
differ from the first-party CLI.

Claude-backed profiles deliberately use the pinned
`@ramarivera/pi-claude-cli@0.3.1` proxy extension. `ppi` exports the matching
profile's `CLAUDE_CONFIG_DIR`; the extension then spawns `claude -p` and uses
that Claude Code profile's Pro/Max subscription. It does not copy the Claude
OAuth token into Pi. These profiles default to
`pi-claude-cli/claude-fable-5`.

Profile setup also records the working npm executable in Pi's `npmCommand`
setting so package installation does not accidentally use a broken or shadowed
npm shim.

`ppi status PROFILE` prints the profile, expected email, and configured Pi
provider names without exposing secrets. Remove only one Pi provider with:

```bash
ppi logout team001 openai-codex
```

## Setup and containers

`scripts/setup-ai-profiles.sh --apply-existing` derives
`~/.config/workbenches/pi-profiles.json` from the five provider manifests and
runs the idempotent Pi setup. Existing launcher fallback profiles are included
so a still-usable local profile is not silently dropped while its registry
metadata is being reconciled. Wave/devBench containers mount
`~/.pi-profiles` and install the same `ppi` launcher.

Use WSL/Linux Pi as the canonical runtime for workBenches and devBench work.
Native Windows Pi keeps a separate home unless a Windows-specific profile
launcher is deliberately installed.

## Encrypted escrow

After a Pi-specific login is verified, explicitly back it up to the owning
private registry:

```bash
scripts/pi-credential-escrow backup \
  --repo /path/to/Tenant-Credentials \
  --profile team-001 \
  --identity-file ~/.config/workbenches/tenant-recovery.agekey
```

The command validates Pi's auth shape, encrypts to
`ai/secrets/pi/PROFILE.auth.sops.yaml`, decrypts it again, and compares a
canonical JSON hash without printing credentials. Use `check` or `restore`
with the same arguments. Restore preserves an existing local credential unless
`--force` is supplied.
