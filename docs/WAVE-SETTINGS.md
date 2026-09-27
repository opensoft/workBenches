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

When WSL is detected, failure to resolve the Windows profile is fatal; the
helper does not silently write a Linux-home file that Windows Wave will ignore.

On native Linux, the default directory is `$XDG_CONFIG_HOME/waveterm` when
`XDG_CONFIG_HOME` is set, otherwise `$HOME/.config/waveterm`. In every
environment an explicit `--waveterm-config PATH` or `WAVETERM_CONFIG_DIR`
override takes precedence.

The helper preserves existing values and unrelated keys, validates that the
file contains a JSON object, writes atomically, and keeps the existing file
mode. It refuses malformed or empty JSON rather than replacing it. It also
refuses a symlinked `settings.json` so an atomic replacement cannot silently
break a dotfile-managed link; update that link's target directly instead.
If the settings file changes after validation, the helper aborts instead of
overwriting the newer contents; rerun it against the updated file.

This helper is not run by general workBenches setup or bench startup, does not
restart Wave, and is not proof that an application-level clipboard regression
has been repaired.
