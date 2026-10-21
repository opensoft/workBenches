#!/usr/bin/env sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PREFIX=${BENCH_ACCESS_PREFIX:-/opt/workbenches/bench-access}
BINDIR=${BENCH_ACCESS_BINDIR:-/usr/local/bin}
SHARE=${BENCH_ACCESS_SHARE:-/usr/local/share/workbenches}
command -v uv >/dev/null
mkdir -p "$PREFIX" "$BINDIR" "$SHARE"
uv venv --python python3 "$PREFIX/venv"
(cd "$ROOT" && uv pip install --python "$PREFIX/venv/bin/python" --require-hashes -r requirements.txt)
printf '#!/usr/bin/env sh\nexec "%s/venv/bin/bench-access" "$@"\n' "$PREFIX" > "$BINDIR/bench-access"
chmod 0755 "$BINDIR/bench-access"
install -m 0644 "$ROOT/capability.json" "$SHARE/system-access.json"
"$BINDIR/bench-access" --help >/dev/null
