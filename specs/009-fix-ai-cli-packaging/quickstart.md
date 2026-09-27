# Quickstart: Validate the refreshed AI CLI images

From the linked worktree in WSL:

```bash
scripts/update-and-rebuild.sh --all --cascade --no-cache --user brett
```

After the cascade, validate Layer 0 and the refreshed Layer 2 `:latest` images as UID/GID 1000:

```bash
docker run --rm --user 1000:1000 workbench-base:latest \
  sh -lc 'id; grok --version; mcode --version; mcode-tools --version'

docker run --rm --user 1000:1000 <bench>-bench:latest \
  sh -lc 'id; grok --version; mcode --version; mcode-tools --version'
```

The cascade does not create a personalized Layer 3 image. When a Layer 3 image
is explicitly required, build it separately from the refreshed Layer 2 base:

```bash
scripts/update-and-rebuild.sh --layer 3 --base <bench>-bench:latest --user brett
```

Do not treat a successful image build as live-container activation. Existing running benches remain on their current image until a separately authorized managed recreation.
