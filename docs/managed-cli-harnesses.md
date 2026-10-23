# Managed CLI harnesses for 1.7

Feature [032](../specs/032-managed-cli-harnesses/spec.md) adds automatic install,
update and removal for 70 formerly manual terminal entries. The six existing
Claude/Codex/Copilot/Antigravity/OpenCode/Pi installers retain their existing paths.
Mentat remains unavailable until the current remote-agent product has a verified
publisher distribution. An unrelated same-name package is not a substitute.
Standalone GUIs, IDEs and extensions retain their existing controls.

## Using the wizard

Choose **Harness → CLI/TUI**, use the four existing filters, then Space to queue
an install/update or D to queue removal. Changes survive filter/category changes.
Review lists each selected CLI and **Targets: Workstation, ...**, wrapping every
name into readable rows at narrow widths. Bench targets
are exactly the benches queued for install/update in this plan; an unrelated
running bench is never selected implicitly. Apply runs the operations.

The workstation receives the CLI and each selected running bench receives its
own installation as its non-root runtime user. Setup never restarts a live bench. With a bench
selected, D can also queue bench removal when the workstation copy is absent.
A stopped or absent target gets a saved desired selection and a **pending**
result, with a nonzero apply result and saved bench intent for retry. The next
personalized image build/start installs its saved tools. Removing a tool also
removes its ID from that bench's future builds. A failure on one target does not
roll back a successful workstation install: retry the pending target operation.
After setup exits, rerun it and select the pending CLI and bench again to retry
live application; the desired bench list also remains available for image rebuilds.

Example from the Tools runtime:

```sh
python3 scripts/setup-harnesses.py install kimi_code --bench pyBench
python3 scripts/setup-harnesses.py update qwen_cli --bench pyBench
python3 scripts/setup-harnesses.py status kimi_code
python3 scripts/setup-harnesses.py uninstall kimi_code --bench pyBench
```

`--local` is for an installer already running inside its intended target, such
as a bench image build. Normal workstation operations use the existing Tools
native callback boundary. Install only the products selected for that machine;
this feature does not install the entire catalog by default.

## Ownership, updates and sign-in

Managed payloads live beneath `~/.local/share/workbenches/harnesses/<id>/versions/`.
`current` points to a verified version, and `~/.local/bin/<command>` points into
that owned prefix. Each component has a lock and a private receipt recording
publisher source, executable hash and installed package version, source commit,
or publisher version output. Status checks these files; it does not log in or
run an agent. An external installation does not count as a managed installation.
A foreign file occupying the public command is preserved and reported, so it
must be relocated using its original installer before creating that launcher.

Updates stage a fresh payload and activate it only after noninteractive
verification of the actual launcher from a separate empty runtime home. Failed/interrupted candidates are removed and the previous version
stays active. If a native callback cannot confirm termination, its unactivated
candidate is retained for inspection rather than deleted beneath a live writer. Removal verifies ownership/receipt/path boundaries and removes only
this feature's launcher and payloads. Missing managed copies are a successful
no-op, so partial removals can be retried against the remaining bench targets. Vendor account directories, profiles,
sessions, repositories and projects remain. Historical successful versions stay
inside the component prefix until managed removal; automatic version pruning is
not part of this change.

Publisher scripts receive a staging HOME and a credential-free install environment.
A sudo guard refuses ordinary privileged installer calls. This is install hygiene,
not an operating-system sandbox for publisher code. npm lifecycle approvals use a
private per-install configuration; the user's npm policy is not rewritten.
Release archives require publisher checksums or GitHub's release-asset SHA-256
metadata and reject links, traversal and special files before extraction.

Installation does **not** establish a paid entitlement or active sign-in. Kimi,
GLM and other profile credential work is separately specified in
[031](../specs/031-kimi-glm-profile-credentials/spec.md); its runtime tasks are not
implemented by these installers. Kimi Code publishes `kimi`; archived Kimi CLI
publishes `kimi-legacy`. International/China Qoder publish `qoder`/`qodercn`.
Cursor CLI publishes `agent`, Every Code `coder`, Tabnine CLI `tabnine-cli`, and
Prime Agent `prime-agent`, preserving distinct products and editor commands.

## Dependencies and bench reconstruction

New npm/Node-based selections require Node 24+ and npm. The wizard uses its existing
Node prerequisite flow. Missing uv, Bun or pnpm are bootstrapped into the candidate's
owned build-tools prefix from their publishers. Source builds also require their
upstream build/system prerequisites; a missing prerequisite fails before activation.
Python packages use isolated uv tools, with Python 3.12 unless the recipe requires
another supported version. Research tools can have large dependency downloads.

Desired bench IDs are private newline lists at
`~/.config/workbenches/harnesses/benches/<image-repository>.list`. They contain no
credentials. Exact local Docker endpoint, checkout, image reference, immutable
container ID and non-root user checks bind each live operation. Remote contexts
and foreign resources are refused before installing on the workstation.

Layer 3 uses a temporary copy of its build context. The canonical runtime and
recipe registry are mirrored into `user-layer/harness-runtime/` by the catalog
compiler, whose check rejects drift. The context receives only the validated ID
list. The desired list participates in image freshness identity, so adding or
removing a CLI invalidates that bench's personalized image. Empty selections add
no downloads; the existing image-layer budget is preserved.

```sh
python3 scripts/setup-tool-catalog.py --write
python3 scripts/setup-tool-catalog.py --check
```

## Qualification and limitations

The registry audit was performed on 2026-10-23. A source-qualified recipe is not
a claim that every product, architecture, platform and authenticated workflow was
executed. Supported platforms are listed per recipe; native Windows uses WSL.
Fixture suites exercise transactions, publisher policy, command identity, archive
safety, target binding, persistence, UI plans and image freshness. Representative
public installs run in disposable declared test containers, without paid agent
calls or real credentials. The acceptance record distinguishes those live checks
from source-only recipes.

Tabnine CLI is a legacy product in maintenance; installing it does not enable its
server-side team entitlement. Plandex Cloud has wound down; the CLI can be installed
for separately configured local/self-hosted service use. Legacy Kimi and research
projects retain their distinct lifecycle labels. A publisher outage or newly
incompatible release can fail an install; failure does not activate an unverified
replacement. Recipes are reviewed code, not executable catalog presentation text.

## Source-qualified recipe inventory

| Catalog entry | Command | Distribution | Publisher source |
| --- | --- | --- | --- |
| Gemini CLI | gemini | npm | [Source](https://github.com/google-gemini/gemini-cli) |
| Jules Tools | jules | npm | [Source](https://jules.google/docs/cli/reference) |
| Grok Build | grok | npm | [Source](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/npm/grok/README.md) |
| Muse Code | muse | script | [Source](https://dev.meta.ai/docs/muse-code) |
| Kiro CLI | kiro-cli | script | [Source](https://kiro.dev/docs/cli/) |
| Bob Shell | bob | npm | [Source](https://bob.ibm.com/docs/shell/getting-started/install-and-setup) |
| Devin CLI | devin | script | [Source](https://docs.devin.ai/) |
| pool | pool | script | [Source](https://github.com/poolsideai/pool) |
| Qwen Code | qwen | npm | [Source](https://github.com/QwenLM/qwen-code) |
| Kimi Code | kimi | npm | [Source](https://github.com/MoonshotAI/kimi-code) |
| Kimi CLI (legacy project) | kimi-legacy | python | [Source](https://github.com/MoonshotAI/kimi-cli) |
| ZCode CLI/TUI | zcode | git-node | [Source](https://github.com/zai-org/ZCode) |
| CodeBuddy Code / CLI | codebuddy | npm | [Source](https://www.codebuddy.cn/docs/cli/installation) |
| Trae Agent | trae-cli | git-python | [Source](https://github.com/bytedance/trae-agent) |
| MiMo Code | mimo | npm | [Source](https://github.com/XiaomiMiMo/MiMo-Code) |
| Qoder CN CLI | qodercn | npm | [Source](https://docs.qoder.cn/cli/installation) |
| Mistral Vibe / Vibe Code CLI | vibe | python | [Source](https://github.com/mistralai/mistral-vibe) |
| iFlow CLI | iflow | npm | [Source](https://github.com/iflow-ai/iflow-cli) |
| Neovate Code | neovate | npm | [Source](https://github.com/neovateai/neovate-code) |
| Crush | crush | npm | [Source](https://github.com/charmbracelet/crush) |
| Aider | aider | python | [Source](https://github.com/Aider-AI/aider) |
| Goose | goose | script | [Source](https://github.com/aaif-goose/goose) |
| Cline CLI | cline | npm | [Source](https://github.com/cline/cline) |
| Continue CLI | cn | npm | [Source](https://github.com/continuedev/continue) |
| Kilo Code CLI | kilo | npm | [Source](https://github.com/Kilo-Org/kilocode) |
| Roo Code CLI | roo | script | [Source](https://github.com/RooCodeInc/Roo-Code/blob/main/.github/workflows/cli-release.yml) |
| Plandex | plandex | release | [Source](https://github.com/plandex-ai/plandex) |
| Codebuff | codebuff | npm | [Source](https://github.com/CodebuffAI/codebuff) |
| ForgeCode | forge | release | [Source](https://github.com/antinomyhq/forge) |
| gptme | gptme | python | [Source](https://github.com/gptme/gptme) |
| Letta Code | letta | npm | [Source](https://github.com/letta-ai/letta-code) |
| Nanocoder | nanocoder | npm | [Source](https://github.com/Nano-Collective/nanocoder) |
| Kode CLI | kode | npm | [Source](https://github.com/shareAI-lab/kode) |
| Codewhale | codew | npm | [Source](https://github.com/codewhale-hq/Codewhale/blob/main/docs/INSTALL.md) |
| jcode | jcode | script | [Source](https://github.com/1jehuang/jcode) |
| Reasonix | reasonix | npm | [Source](https://reasonix.io/docs/) |
| OH-MY-PI | omp | script | [Source](https://github.com/can1357/oh-my-pi) |
| Cursor CLI | agent | script | [Source](https://cursor.com/docs/cli/installation) |
| Amp | amp | script | [Source](https://ampcode.com/docs/cli) |
| Droid | droid | script | [Source](https://docs.factory.com/cli/getting-started/quickstart) |
| Auggie | auggie | npm | [Source](https://docs.augmentcode.com/cli/setup-auggie/install-auggie-cli) |
| Junie CLI | junie | script | [Source](https://junie.jetbrains.com/docs/junie-cli.html) |
| Tabnine CLI | tabnine-cli | script | [Source](https://docs.tabnine.com/main/getting-started/tabnine-cli/getting-started/installation) |
| Mentat CLI | Unavailable | unavailable | [Former source; unavailable](https://github.com/AbanteAI/mentat) |
| Ante | ante | script | [Source](https://github.com/AntigmaLabs/ante) |
| TheGitAI | thegitai | npm | [Source](https://thegit.ai/docs/getting-started/installation) |
| Qoder CLI — international | qoder | npm | [Source](https://docs.qoder.com/cli/installation) |
| OpenHands CLI | openhands | python | [Source](https://github.com/OpenHands/software-agent-sdk) |
| SWE-agent | sweagent | git-python | [Source](https://github.com/SWE-agent/SWE-agent) |
| mini-SWE-agent | mini | python | [Source](https://github.com/SWE-agent/mini-swe-agent) |
| AutoCodeRover | acr | git-requirements | [Source](https://github.com/nus-apr/auto-code-rover) |
| Devon | devon-tui | git-python | [Source](https://github.com/entropy-research/Devon) |
| RA.Aid | ra-aid | python | [Source](https://github.com/ai-christianson/RA.Aid) |
| Deep Agents Code | dcode | script | [Source](https://github.com/langchain-ai/deepagents) |
| Pydantic Deep Agents | pydantic-deep | python | [Source](https://github.com/vstorm-co/pydantic-deepagents) |
| Tau | tau | python | [Source](https://github.com/jmccardle/tau) |
| Dexto | dexto | npm | [Source](https://github.com/truffle-ai/dexto) |
| Atomic Agent | atomic-agent | script | [Source](https://github.com/AtomicBot-ai/atomic-agent) |
| BitFun | openbitfun | release | [Source](https://github.com/GCWing/OpenBitFun) |
| Maki | maki | script | [Source](https://github.com/tontinton/maki) |
| VT Code | vtcode | script | [Source](https://github.com/vinhnx/VTCode) |
| hax | hax | release | [Source](https://github.com/OleksandrChekhovskyi/hax) |
| agentty | agentty | script | [Source](https://github.com/agentty-org/agentty) |
| cecli | cecli | python | [Source](https://github.com/dwash96/cecli) |
| Every Code | coder | npm | [Source](https://github.com/just-every/code) |
| open-codex | open-codex | npm | [Source](https://github.com/ymichael/codex) |
| nori-cli | nori | npm | [Source](https://github.com/tilework-tech/nori-cli) |
| Hermes Agent | hermes | script | [Source](https://github.com/NousResearch/hermes-agent) |
| Prime Agent | prime-agent | script | [Source](https://github.com/PrimeIntellect-ai/prime-agent) |
| Open Interpreter | interpreter | script | [Source](https://github.com/openinterpreter/openinterpreter) |
| DeepSeek Harness (dsh) | dsh | npm | [Source](https://github.com/deepseek-ai/deepseek-harness) |
