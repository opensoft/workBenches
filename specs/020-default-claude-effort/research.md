# Research

## Decision

Use CLI startup effort rather than rewriting profile settings. Anthropic's current model configuration documentation identifies explicit effort as the supported session override; existing Opus 5.5 user-level effort defaults are insufficient.

## Rationale

The launcher already constructs common Claude flags after routing. This is the smallest shared integration point and preserves print-mode classification.

## Alternatives considered

- Wrapper-only prepend: changes first-argument routing and sends flags to utilities.
- Profile-wide modelSettings migration: unnecessarily rewrites operator preferences.
- Global environment assignment: can override existing environment choices and affect unrelated processes.

## Sources

- [Anthropic model configuration](https://code.claude.com/docs/en/model-config#adjust-effort-level)
- Local native CLI help confirms `--effort` supports xhigh and max.

No unresolved research questions; no research delegation necessary.
