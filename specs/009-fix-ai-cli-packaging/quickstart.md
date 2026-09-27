# Quickstart: Validate the refreshed AI CLI images

From the linked worktree in WSL:

```bash
scripts/update-and-rebuild.sh --all --cascade --no-cache --user brett
```

After the cascade, validate each personalized image with the default image user:

```bash
docker run --rm --entrypoint /bin/sh <bench>-bench:brett -lc \
  'id; command -v grok; grok --version; command -v mcode; mcode --version'
```

Do not treat a successful image build as live-container activation. Existing running benches remain on their current image until a separately authorized managed recreation.
