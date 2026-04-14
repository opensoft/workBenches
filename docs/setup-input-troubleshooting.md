# setup.sh Input Troubleshooting Log
**Date: 2026-04-05**

## Problem
After running `./setup.sh`, interactive prompts (especially "Press Enter to continue...") hang or don't respond to keypresses. The issue manifests in both the OpenTUI (TypeScript/Bun) path and the Bash fallback (`interactive-setup.sh`).

---

## Root Causes Found

### 1. `exec > >(tee ...)` breaks stdin for child processes
**File:** `setup.sh` lines 19-20
**Status:** FIXED

The logging setup used process substitution to tee all output:
```bash
exec 3>&1
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
```

**Why it breaks:** Process substitution `>(tee ...)` creates subshells that inherit and interfere with stdin. All child processes (`interactive-setup.sh`, bench setup scripts) lose access to normal stdin. Interactive `read` commands hang because stdin is being consumed by the tee pipeline.

**Fix:** Removed the global `exec` redirect entirely. Logging now writes directly to `$LOG_FILE` using `>> "$LOG_FILE"` and a `log_header` helper. A `run_logged` function is available for commands that need output captured.

**Lesson:** Never use `exec > >(tee ...)` in scripts that spawn interactive children. Use explicit per-command logging instead.

### 2. Enter key sends `\r` in WSL, not empty string
**File:** `interactive-setup.sh` line 859
**Status:** FIXED

The TUI keyboard handler used `read -rsn1` and checked for empty string `''` to detect Enter:
```bash
'') # Enter - confirm and process
    return 1
    ;;
```

**Why it breaks:** In WSL terminals, pressing Enter sends `\r` (carriage return, 0x0D), not `\n` (newline, 0x0A). `read -rsn1` captures the `\r` as a character, so `key` is `\r`, not empty. The case statement doesn't match.

**Fix:** Added `\r` and `\n` to the match:
```bash
''|$'\r'|$'\n') # Enter - confirm and process
    return 1
    ;;
```

**Lesson:** Always handle both `\r` and `\n` for Enter key detection in raw terminal input, especially in WSL.

### 3. OpenTUI keyboard integration is broken
**File:** `scripts/setup-ui/src/components/App.tsx`
**Status:** KNOWN ISSUE — falls back to Bash UI

The OpenTUI-based TUI has multiple keyboard problems:
- Uses incorrect private API (`renderer._keyHandler` instead of `renderer.keyInput`)
- `useKeyboard` hook doesn't fire reliably
- Keyboard events don't trigger SolidJS reactivity for redraws
- `handleConfirm` is async but not awaited from synchronous keyboard callback
- `renderer.stop()` triggers cleanup that can hang

**Attempted fixes that didn't fully work:**
- Adding `renderer.stop()` before installations — triggered OpenTUI cleanup hang
- Adding `process.stdin.pause()` + `removeAllListeners()` + `setRawMode(false)` — better but still unreliable
- Adding `confirmInProgress` guard — prevents double-fire but doesn't fix root issue

**Current state:** The OpenTUI path is unreliable. The script falls back to Bash UI via the `||` clause in `setup.sh`:
```bash
(cd "$setup_ui_dir" && bun run start) || {
    echo "TypeScript UI failed, falling back to Bash UI..."
    "${SCRIPT_DIR}/scripts/interactive-setup.sh"
}
```

**Lesson:** OpenTUI keyboard handling needs a full refactor (see `KEYBOARD_FIX_PLAN.md` in setup-ui). For now, the Bash UI is the reliable path.

### 4. fd 3 redirect was wrong direction
**File:** `interactive-setup.sh` (all `read -p` commands)
**Status:** FIXED (reverted)

Attempted to fix the tee/stdin issue by reading from fd 3:
```bash
read -p "Press Enter to continue..." <&3 2>/dev/null || read -p "Press Enter to continue..."
```

**Why it broke:** `exec 3>&1` in setup.sh saved **stdout** as fd 3, not stdin. Reading from stdout gives "Bad file descriptor". The fallback `read` then ran but was still affected by the tee stdin issue.

**Fix:** Reverted all fd 3 redirects. Fixed the actual root cause (removed exec tee) instead.

**Lesson:** `exec 3>&1` saves stdout, not stdin. To save stdin, use `exec 3<&0`. But the better fix is to not corrupt stdin in the first place.

### 5. sed command doubled variable names
**File:** `interactive-setup.sh` (16 `read -p` commands)
**Status:** FIXED

The sed to add fd 3 fallbacks was too aggressive:
```bash
sed -i 's/read -p \(.*\)/read -p \1 <\&3 2>\/dev\/null || read -p \1/'
```

This turned `read -p "Try again?" retry` into `read -p "Try again?" retry retry` — doubled variable names that broke the read assignments.

**Fix:** `sed -i -E 's/(read -p "[^"]*" )([a-z_]+) \2$/\1\2/'`

**Lesson:** Test sed patterns on a single line before applying globally. Backreferences in replacement strings can duplicate content unexpectedly.

---

## What Works Now
- `setup.sh` logging writes to `logs/setup-YYYYMMDD-HHMMSS.log` without affecting stdin
- Bash TUI Enter key detection handles `\r`, `\n`, and empty string
- All `read -p` commands have correct single variable names
- OpenTUI failure falls back to Bash UI automatically

## What Still Needs Work
- OpenTUI keyboard handling needs refactor (see `KEYBOARD_FIX_PLAN.md`)
- The `run_logged` helper in setup.sh is available but not yet used for Layer 1 builds — add it if build output logging is needed
- Consider adding `set -o pipefail` to setup.sh for better error propagation
