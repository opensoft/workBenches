## Context

The canonical Layer 0 image installs AI tools system-wide as root so every
Layer 2 and Layer 3 bench inherits the same reproducible baseline. The legacy
devBench installer and account adapter mirror part of that surface. New tools
have different distribution mechanisms, native post-install requirements, and
occasionally conflicting command names, so the refresh must keep installation
ownership and command resolution explicit.

## Goals / Non-Goals

**Goals:**

- Install and verify the expanded CLI set during image construction.
- Keep system-wide packages root-owned and leave user credentials outside image
  layers.
- Expose unambiguous command names and profile-family mappings.
- Preserve existing tools while correcting the Herdr checksum, NotebookLM MCP
  launcher ownership, and Claude profile defaults.

**Non-Goals:**

- Do not authenticate any provider during an image build.
- Do not recreate or restart running bench containers.
- Do not make preview or best-effort installers mandatory when their upstream
  distribution is not stable enough for a hard build gate.
- Do not let Cursor's generic `agent` command replace another installed tool.

## Decisions

- Keep the canonical tools in the shared Layer 0 image. Installing them in each
  bench would multiply drift and build time.
- Use npm's explicit `allow-scripts` list only for packages whose published
  installation requires native post-install work. This retains npm's default
  script blocking for unrelated dependencies.
- Treat the command-presence list as the hard image contract. Preview tools
  such as DeepSeek Harness and native tools whose installer can be unavailable
  remain best effort and are reported distinctly at build completion.
- Install Cursor only as `cursor-agent`; never claim the ambiguous `agent`
  binary because Grok already uses that name.
- Let the dedicated NotebookLM MCP package own its shared launcher while
  retaining the NotebookLM and `nlm` entry points from their respective
  packages.
- Initialize new Claude profiles with the Fable 5.1 model identifier, while
  retaining any model already present in an existing profile settings file.
- Skip creation of the native Claude compatibility link when the launcher is
  running inside a container. Host installation health remains a host concern.

## Risks / Trade-offs

- [Floating upstream packages can change between builds] -> A no-cache image
  build and command smoke test gate each merge; checksum-gated installers stay
  pinned where the project already has that contract.
- [Native installers can change behavior] -> Copy only the expected binary to
  the system path, verify it explicitly, and keep non-critical native tools
  best effort.
- [More CLIs increase image size and build duration] -> Centralize them in the
  shared base so the cost is paid once per image family refresh.
- [Provider command names or profile folders can drift] -> Keep mappings in the
  adapter and document the exact launcher/profile-family contract.

## Migration Plan

1. Run syntax and focused launcher/profile tests.
2. Build the shared image without cache and verify every required command.
3. Merge the source change without touching running containers.
4. Activate rebuilt images only through the separately authorized managed
   workBench recreation workflow.
5. Roll back by rebuilding from the prior merge commit; existing credentials
   remain external to the image and require no migration.

## Open Questions

None.
