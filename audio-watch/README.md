# Windows audio-session watcher

`AudioSessionWatch.ps1` records metadata about active Windows playback sessions. It does **not** record audio.

The JSON Lines log includes timestamp, output endpoint ID, process ID/name/path/command line, Windows audio-session state, instantaneous peak level, foreground window, and periodic remote network endpoints for processes with active audio sessions.

By default, logs are stored under `%LOCALAPPDATA%\CodexAudioWatch`.

Run interactively:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AudioSessionWatch.ps1
```

Stop an interactive run with Ctrl+C. For a hidden run, stop the PID recorded in `%LOCALAPPDATA%\CodexAudioWatch\watcher.pid`.
