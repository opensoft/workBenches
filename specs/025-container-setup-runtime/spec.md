# Container setup runtime

Brett requested on 2026-10-15 that Python 3, jq, Git, and curl live in a
managed Tools container rather than being installed as host prerequisites.
Requirements must report Docker, Tools, and optional Vault as Up, Down, or
Missing. Tools starts automatically once Docker is available. Vault means the
credential-access container, as explicitly confirmed by Brett; account login
and vault unlock remain separate from container readiness.

- Setup must launch and finish a selection/cancellation with all four tools
  absent from the host PATH. No package-manager install of those tools occurs.
- Docker and the workstation shell remain the host bootstrap. Preserve Windows
  WSL guidance and the selected local Docker endpoint.
- Native application detection and explicit installation/removal must refer to
  the workstation, never to the Tools image. Preserve confirmation/cancellation,
  data, ownership and unrelated-container protections.
- Tools is a healthy, managed container with all four working executables.
  Missing means no managed container; Down means stopped, unhealthy, blocked by
  Docker, or inaccessible. A foreign name collision must never be replaced.
- Vault is optional, has no Docker socket or host profile-home mount, and does
  not expose a password vault server. Provider credentials remain transient.
  Existing Azure, Bitwarden, Vaultwarden and 1Password recovery must work.
- Keep the silver header and component-column layout from the current branch.
  Surface the three lifecycle states consistently in the Requirements strip,
  page, bootstrap screen and refresh/configure actions.
- Prove missing-to-up, down-to-up, repeated start, unhealthy/foreign resources,
  host-vs-container application checks, and real TUI cancellation through the
  declared isolated Docker test bench. Remove only test-created resources.

Follow-up requested by Brett, 2026-10-15:

- Give Docker, Tools and Vault one state-dependent action: Missing → Install,
  Down → Start. Up Docker/Tools offer Check; Up Vault offers Connect, or Sign out
  when the Keycloak account session is signed in.
- Enter/Space on a focused service activates that action immediately and never
  applies queued component changes. Connect opens the browser approval page;
  cancel returns to the same TUI and preserves those selections.
- Keep container health separate from Keycloak login and provider authorization.
  This change does not configure Microsoft federation or a credential broker.

- Vault’s current action must also be visible beside its status on the main
  selection screen, with V activating it from any section. Narrow-screen
  wrapping must preserve the action; connection notices must be visible there.

Follow-up: immediate TUI startup, requested 2026-10-15.

- Paint the interactive TUI without Docker, jq, Git or Python probes. Show yellow
  blinking Loading… states until individual read-only checks finish.
- Run checks/automatic Tools startup in an owned background job. Publish private
  atomic status records; never source/evaluate generated status data.
- Keep P/navigation/Q responsive, including a stalled daemon. Q must stop owned
  pending probes and clean status files, without stopping installed services.
- Preserve selected components and focus as the catalog/statuses arrive. Disable
  unknown-item actions and Apply until required checks are ready.
- Batch tool presence/credential-presence checks under one native callback
  session. Native installation/removal verification must use fresh data.
