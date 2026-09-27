# Wave Terminal settings defaults

`scripts/configure-wave-settings.sh` is an explicit workstation helper. It adds
the following defaults only when their keys are absent:

- `app:disablectrlshiftdisplay: true`
- `term:copyonselect: true`

Run it from WSL with:

```bash
scripts/configure-wave-settings.sh
```

Under WSL the helper resolves the Windows user profile and targets
`.config/waveterm/settings.json`, which is the configuration consumed by the
Windows-native Wave application. Use `--waveterm-config PATH` or
`WAVETERM_CONFIG_DIR` to target another directory.

The helper preserves existing values and unrelated keys, validates that the
file contains a JSON object, writes atomically, and keeps the existing file
mode. It refuses malformed JSON rather than replacing it.

This helper is not run by general workBenches setup or bench startup, does not
restart Wave, and is not proof that an application-level clipboard regression
has been repaired.
