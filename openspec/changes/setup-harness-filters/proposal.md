# Combinable CLI harness filters

## Authority and intent
Brett requested subcategory filters on the large CLI harness screen: Frontier, USA/China, subscription/API access, LLM/image/video/voice/classifier. He clarified Frontier means a curated set of frontier model-maker labs, and native capabilities and model/plugin capabilities must be tracked separately (chat, 2026-10-23). Implement this within feature 029, task T039K, replacing the single F group selector with a combinable filter panel.

## Scope
Separate filter rows: Frontier, Region, Access, Native capabilities, Via models/plugins, and the existing catalog Group. Region/access/capability rows allow multiple selected options. A product matching any selected value within a row passes that row; all active rows must pass (OR within, AND across). Group is single-choice; Frontier is curated lab membership, not access to another vendor's frontier models or a benchmark ranking. Subscription/API can both apply to one harness. Unknown metadata is an explicit option, never inferred as absence.

F opens/closes Filters. Up/Down chooses a row; Tab/Shift+Tab moves among its options; Space toggles/selects; C clears filters; F returns to results. Changes update a match count immediately. Left/Right and Enter retain step/Review meanings. Filtering never modifies selected installation actions. Empty results are explicit and cannot expose actions for an old hidden selection. P/G/refresh preserve all filter values, focus and scroll state. Runtime remains builtins-only and responsive.

Internal catalog schema 2 adds curated lab records and evidence-bearing filter metadata; generated snapshots remain deterministic. Access/native/integrated tags carry provenance and specific scope. Native image input is distinguished from generation in notes; routed capabilities identify the external model/plugin/tool and required setup. Undocumented video/voice/classifier support stays unknown. No new catalog products, installers, plan keys, authentication probes, provider API calls or runtime agent execution.

One implementation feature remains specs/029-setup-guided-wizard. Existing copy/real-host/CI/merge gates stay pending; commit/push authorization for the feature branch persists. No PR, merge or archive is included.

## Accepted follow-up: four columns
Brett requested Type with Frontier/Open/Closed choices, then Region, Access and Native only, with cycling arrow-key controls and Frontier selected by default. T039L replaces the original six-row multi-select presentation; the design and requirements now describe the current interaction. Brett clarified Open/Closed means model weights, not the harness source. Both may apply; unverified products remain Unknown. Capability integration evidence stays in About. All publication/release gates and existing branch push authorization remain unchanged.
