# Skills Context Index

Available skill contexts that agents can load for specialized tasks.

## How Agents Use Skills

1. Identify task type from user request
2. Load relevant skill context: `Read ~/.config/opencode/context/skills/<skill>.md`
3. Apply skill guidance to complete the task

## Available Skills

| Skill | Trigger | Context File |
|-------|---------|--------------|
| doc-coauthoring | Writing docs, proposals, specs | `skills/doc-coauthoring.md` |
| docx | Working with .docx files | `skills/docx.md` |
| internal-comms | Status reports, updates, newsletters | `skills/internal-comms.md` |
| mcp-builder | Building MCP servers | `skills/mcp-builder.md` |
| pdf | PDF manipulation, forms | `skills/pdf.md` |
| pptx | Presentation creation/editing | `skills/pptx.md` |
| skill-creator | Creating new skills | `skills/skill-creator.md` |

## Skill Loading Pattern

```
IF task matches skill trigger:
  1. Read /home/brett/.config/opencode/context/skills/<skill>.md
  2. Apply guidance from skill context
  3. Complete task following skill workflow
```
