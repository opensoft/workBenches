#!/usr/bin/env bash
# Real npm in an isolated home/prefix, no provider auth or network required.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
guard="$repo/user-layer/claude-npm-guard"
scratch="$(mktemp -d)"
registry_pid=""
trap '[[ -z "$registry_pid" ]] || kill "$registry_pid"; rm -rf "$scratch"' EXIT
export HOME="$scratch/home" NPM_CONFIG_USERCONFIG="$scratch/home/.npmrc"
export NPM_CONFIG_PREFIX="$scratch/prefix" NPM_CONFIG_CACHE="$scratch/cache"
export NPM_CONFIG_GLOBALCONFIG="$scratch/global.npmrc"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
mkdir -p "$HOME" "$scratch/fixture"
cd "$HOME"
checks=0
ok() { checks=$((checks + 1)); }
fail() { echo "FAIL: $*" >&2; exit 1; }
[[ "$(npm --version)" == 12.* ]] || fail 'this regression requires npm 12'
printf '%s\n' '# preserved comment' 'fund=false' \
    'allow-scripts[]=existing-approved' 'include[]=dev' > "$NPM_CONFIG_USERCONFIG"
printf '%s\n' 'allow-scripts[]=inherited-approved' > "$NPM_CONFIG_GLOBALCONFIG"
bash "$guard" --configure
grep -Fxq 'allow-scripts[]=existing-approved' "$NPM_CONFIG_USERCONFIG"; ok
grep -Fxq 'allow-scripts[]=@anthropic-ai/claude-code' "$NPM_CONFIG_USERCONFIG"; ok
grep -Fxq 'include[]=dev' "$NPM_CONFIG_USERCONFIG"; ok
grep -Fxq 'include[]=optional' "$NPM_CONFIG_USERCONFIG"; ok
grep -Fxq '# preserved comment' "$NPM_CONFIG_USERCONFIG"; ok
grep -Fxq 'fund=false' "$NPM_CONFIG_USERCONFIG"; ok
before="$(sha256sum "$NPM_CONFIG_USERCONFIG")"
bash "$guard" --configure
[[ "$before" == "$(sha256sum "$NPM_CONFIG_USERCONFIG")" ]]; ok
bash "$guard" --configure & first=$!
bash "$guard" --configure & second=$!
wait "$first"; wait "$second"
[[ "$before" == "$(sha256sum "$NPM_CONFIG_USERCONFIG")" ]]; ok
[[ "$(stat -c %a "$NPM_CONFIG_USERCONFIG")" == 600 ]]; ok
mv "$NPM_CONFIG_USERCONFIG" "$scratch/preserved.npmrc"
bash "$guard" --configure
grep -Fxq 'allow-scripts[]=inherited-approved' "$NPM_CONFIG_USERCONFIG"; ok
mv "$scratch/preserved.npmrc" "$NPM_CONFIG_USERCONFIG"
if NPM_CONFIG_IGNORE_SCRIPTS=true bash "$guard" --configure >"$scratch/refusal" 2>&1; then
    fail 'ignore-scripts override accepted'
fi
grep -q 'ignore-scripts=true' "$scratch/refusal"; ok
if [[ "$(npm --version)" == 12.* ]]; then
    if NPM_CONFIG_ALLOW_SCRIPTS=other bash "$guard" --configure >"$scratch/refusal" 2>&1; then
        fail 'ineffective script approval accepted'
    fi
    grep -q 'effective allow-scripts' "$scratch/refusal"; ok
fi
# The userconfig symlink remains a symlink; only its owned target is changed.
mv "$NPM_CONFIG_USERCONFIG" "$scratch/linked.npmrc"
ln -s "$scratch/linked.npmrc" "$NPM_CONFIG_USERCONFIG"
bash "$guard" --configure
[[ -L "$NPM_CONFIG_USERCONFIG" ]]; ok

# Stub package emulates the upstream npm layout and soft-success postinstall.
node - "$scratch/fixture" <<'NODE'
const fs = require('node:fs'), path = require('node:path');
const dir = process.argv[2];
fs.mkdirSync(path.join(dir, 'bin'));
fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({
  name: '@anthropic-ai/claude-code', version: '1.2.3',
  bin: {claude: 'bin/claude.exe'}, scripts: {postinstall: 'node install.cjs'}
}));
fs.writeFileSync(path.join(dir, 'bin/claude.exe'),
  '#!/usr/bin/env node\nprocess.exit(1);\n', {mode: 0o755});
fs.writeFileSync(path.join(dir, 'install.cjs'),
  "const fs=require('node:fs'); if(!process.env.TEST_MISSING_PAYLOAD) " +
  "fs.writeFileSync(__dirname+'/bin/claude.exe', " +
  "'#!/usr/bin/env node\\nconsole.log(\"1.2.3 (Claude Code)\");\\n', {mode:0o755});\n");
NODE
archive="$(cd "$scratch/fixture" && npm pack --silent)"
archive="$scratch/fixture/$archive"
node - "$archive" "$scratch/port" <<'NODE' &
const fs = require('node:fs'), http = require('node:http');
const archive = fs.readFileSync(process.argv[2]);
const server = http.createServer((req, res) => {
  if (req.url.endsWith('.tgz')) {
    res.setHeader('Content-Type', 'application/octet-stream');
    return res.end(archive);
  }
  const base = 'http://127.0.0.1:' + server.address().port;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({
    name: '@anthropic-ai/claude-code', 'dist-tags': {latest: '1.2.3'},
    versions: {'1.2.3': {
      name: '@anthropic-ai/claude-code', version: '1.2.3',
      bin: {claude: 'bin/claude.exe'}, scripts: {postinstall: 'node install.cjs'},
      dist: {tarball: base + '/@anthropic-ai/claude-code/-/claude-code-1.2.3.tgz'}
    }}
  }));
});
server.listen(0, '127.0.0.1', () => fs.writeFileSync(process.argv[3], String(server.address().port)));
NODE
registry_pid=$!
for attempt in {1..50}; do [[ ! -f "$scratch/port" ]] || break; sleep 0.1; done
[[ -f "$scratch/port" ]] || fail 'fixture registry failed to start'
export NPM_CONFIG_REGISTRY="http://127.0.0.1:$(cat "$scratch/port")"
# Reproduce exit-zero/default-blocked postinstall in an unconfigured home.
NPM_CONFIG_USERCONFIG="$scratch/unconfigured.npmrc" \
NPM_CONFIG_GLOBALCONFIG="$scratch/unconfigured-global.npmrc" \
    npm install -g @anthropic-ai/claude-code@1.2.3 --no-audit >"$scratch/blocked.log" 2>&1
grep -q 'install scripts blocked' "$scratch/blocked.log"; ok
if "$NPM_CONFIG_PREFIX/bin/claude" --version; then fail 'fixture not broken'; fi; ok
bash "$guard" --repair | grep -q 'verified npm 1.2.3'; ok
[[ "$("$NPM_CONFIG_PREFIX/bin/claude" --version)" == '1.2.3 (Claude Code)' ]]; ok
# Prove plain npm now runs postinstall using the persisted selective policy.
npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1
npm install -g @anthropic-ai/claude-code@1.2.3 --no-audit >/dev/null 2>&1
[[ "$("$NPM_CONFIG_PREFIX/bin/claude" --version)" == '1.2.3 (Claude Code)' ]]; ok
printf '%s\n' '#!/bin/sh' 'exit 1' > "$NPM_CONFIG_PREFIX/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
if TEST_MISSING_PAYLOAD=1 bash "$guard" --repair >"$scratch/refusal" 2>&1; then
    fail 'soft-success postinstall with no payload accepted'
fi
grep -q 'native payload missing or wrong version' "$scratch/refusal"; ok
# Timeout a hook without waiting 30 seconds; other timeout calls remain real.
mkdir -p "$scratch/mock"
export REAL_TIMEOUT="$(command -v timeout)"
printf '%s\n' '#!/bin/bash' \
    '[[ "$*" != *"30s node "* ]] || exit 124' \
    'exec "$REAL_TIMEOUT" "$@"' > "$scratch/mock/timeout"
chmod +x "$scratch/mock/timeout"
if PATH="$scratch/mock:$PATH" bash "$guard" --repair >"$scratch/refusal" 2>&1; then
    fail 'timed-out postinstall accepted'
fi
grep -q 'installed Claude postinstall failed' "$scratch/refusal"; ok
npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1
mkdir -p "$scratch/native"
printf '%s\n' '#!/bin/sh' 'echo "2.3.4 (Claude Code)"' > "$scratch/native/claude"
chmod +x "$scratch/native/claude"
before="$(sha256sum "$scratch/native/claude")"
PATH="$scratch/native:$PATH" bash "$guard" --repair | grep -q 'installation unchanged'; ok
[[ "$before" == "$(sha256sum "$scratch/native/claude")" ]]; ok

grep -Fq 'COPY --chmod=0755 claude-npm-guard /usr/local/bin/claude-npm-guard' "$repo/user-layer/Dockerfile"; ok
grep -Fq '&& claude-npm-guard --configure' "$repo/user-layer/Dockerfile"; ok
grep -Fq 'docker exec --user "$container_user" "$container" "$shell_path" -lc' "$repo/scripts/wave-container-shell.sh"; ok
grep -Fq -- '--include=optional --allow-scripts=@anthropic-ai/claude-code --strict-allow-scripts' "$repo/base-image/install-ai-clis.sh"; ok
echo "Claude npm guard: $checks checks passed"
