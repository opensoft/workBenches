#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/scripts" "$test_root/config"
cp "$repo_root/scripts/update-bench-config.sh" "$test_root/scripts/"
cat > "$test_root/config/bench-config.json" <<'JSON'
{"categories":{"science":{"label":"Science","order":2,"summary":"Fixture"}},"custom":"preserve top-level", "infrastructure":{"keep":{"value":true}},"benches":{"fixtureBench":{"path":"devBenches/fixtureBench","url":"https://example.com/fixture.git","description":"Original copy","category":"software-engineering","tagline":"Original tagline","usedFor":["Testing"],"contains":["Tools"],"ai_keywords":["fixture"],"project_scripts":[{"name":"custom"}],"future_field":{"keep":true}}}}
JSON
cp "$test_root/config/bench-config.json" "$test_root/before.json"
cat > "$test_root/config/release-lock.json" <<'JSON'
{"repositories":[{"path":"devBenches/fixtureBench","url":"https://example.com/fixture.git"},{"path":"sysBenches/365Bench","url":"https://example.com/365.git"},{"path":"bioBenches/scienceBench","url":"https://example.com/science.git"}]}
JSON
for relative in devBenches/fixtureBench sysBenches/365Bench bioBenches/scienceBench devBenches/unlockedBench; do
    git init -q "$test_root/$relative"
    git -C "$test_root/$relative" remote add origin "https://example.com/$(basename "$relative").git"
done
(cd "$test_root"; printf 'y\n' | bash scripts/update-bench-config.sh) > "$test_root/output" 2>&1
python3 - "$test_root" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1]);before=json.loads((root/'before.json').read_text());after=json.loads((root/'config/bench-config.json').read_text())
for field in ('categories','infrastructure','custom'):assert before[field]==after[field],field
assert before['benches']['fixtureBench']==after['benches']['fixtureBench'], 'existing bench fields changed'
assert after['benches']['365Bench']['category']=='system-administration'
assert after['benches']['scienceBench']['category']=='science'
assert after['benches']['365Bench']['path']=='sysBenches/365Bench'
assert 'unlockedBench' not in after['benches']
assert 'unlockedBench' in (root/'output').read_text()
print('PASS: preserve metadata, derive categories, and skip unlocked clones')
PY
