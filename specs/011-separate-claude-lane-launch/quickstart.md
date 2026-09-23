# Quickstart

After installation, run `pclaude <profile>` for a profile-only session and `lclaude <profile>` for a lane-aware session. `lclaude --lane <lane> <profile>` names a lane explicitly. Existing `pclaude --lane <lane> <profile>` remains supported during migration.

Validate with the focused Claude profile lane tests inside a bench container, then verify `command -v pclaude` and `command -v lclaude` in a rebuilt image. Source merge alone does not update running containers.
