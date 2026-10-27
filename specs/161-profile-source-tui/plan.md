# Implementation plan

Reuse feature 160 cloud import validation/storage and the existing profile_tui panes. Add a shared profile_sources module and an explicit native picker host action. Keep provider credentials separate from metadata. Bind GitHub reads to the account helper, fetch one immutable commit and its grant file, and never clone arbitrary remote content or execute it.

Use a temporary isolated source copy for development/verification so tests cannot rotate workstation installation logs. Apply the reviewed source changes back to the existing 1.6.2 worktree. Do not alter machine build state or bench pins. Preserve cloud connector implementation and record its provenance as PR #230; no merge or release publication is implied.

T001 implements native selection and bounded sources, T002 transactional review/import and TUI integration, T003 scoped credential recovery and regression coverage, T004 release wiring, documentation and validation. Remote publishing and company broker remain out of scope. The only executable checklist is tasks.md.
