# Quickstart: Apply Wave settings defaults

Preview the documented behavior and then run explicitly:

```bash
scripts/configure-wave-settings.sh
```

To target a non-default or test directory:

```bash
scripts/configure-wave-settings.sh --waveterm-config /path/to/waveterm
```

Validate without touching real user settings:

```bash
bash devcontainer.test/test-configure-wave-settings.sh
```

The helper does not restart Wave and does not prove that an application-level
clipboard regression is resolved.
