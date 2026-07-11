# AI harness account dashboard

This public cloudBench example contains no organization or user account data.

Use the local Multiple AI Harness Account Manager to inspect configured Claude,
ChatGPT/Codex, Grok, Antigravity, and Abacus accounts:

```bash
python3 /workspace/apps/credential-manager/credential_manager.py \
  --source-repo /path/to/private/account-registry
```

See `/workspace/docs/ai-harness-account-management.md` for profile conventions
and provider-specific authentication boundaries.
