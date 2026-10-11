#!/usr/bin/env bash
set -eo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/scripts/lib" "$test_root/config" "$test_root/devBenches"
cp "$repo_root/scripts/interactive-setup.sh" "$test_root/scripts/"
cp "$repo_root/bootstrap.sh" "$test_root/"
cp "$repo_root/scripts/lib/image-names.sh" "$test_root/scripts/lib/"
printf '%s\n' '{"benches":{"testBench":{"path":"devBenches/testBench","url":"git@github.com:opensoft/testBench.git"}}}' > "$test_root/config/bench-config.json"
source "$test_root/scripts/interactive-setup.sh"

bench_dir="$test_root/devBenches/testBench"
git init -q "$bench_dir"
git -C "$bench_dir" remote add origin https://github.com/opensoft/testBench.git
mkdir "$bench_dir/.devcontainer"

assert_status() {
    local expected="$1" label="$2" actual
    actual="$(check_component_status bench_testBench)"
    if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL: %s: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$label"
}

for remote in \
    https://github.com/opensoft/testBench.git \
    https://github.com/opensoft/testBench \
    git@github.com:opensoft/testBench.git \
    git@github.com:opensoft/testBench \
    ssh://git@github.com/opensoft/testBench.git \
    ssh://git@github.com/opensoft/testBench \
    https://github.com/OpenSoft/TestBench.git/; do
    git -C "$bench_dir" remote set-url origin "$remote"
    assert_status installed "equivalent GitHub remote: $remote"
done

for remote in https://github.com/other/testBench.git https://example.com/opensoft/testBench.git; do
    git -C "$bench_dir" remote set-url origin "$remote"
    assert_status 'not installed' "reject different repository: $remote"
done

git -C "$bench_dir" remote set-url origin https://github.com/opensoft/testBench.git
mv "$bench_dir/.git" "$test_root/bench-git-dir"
printf 'gitdir: %s\n' "$test_root/bench-git-dir" > "$bench_dir/.git"
assert_status installed 'gitfile checkout (submodule layout)'
mv "$bench_dir/.devcontainer" "$test_root/bench-infrastructure"
assert_status 'needs creds' 'checkout without bench infrastructure needs setup'
mv "$test_root/bench-infrastructure" "$bench_dir/.devcontainer"
printf 'gitdir: %s\n' "$test_root/missing-git-dir" > "$bench_dir/.git"
assert_status 'not installed' 'invalid gitfile is not a checkout'
rm "$bench_dir/.git"
git init -q "$test_root"
git -C "$test_root" remote add origin https://github.com/opensoft/testBench.git
assert_status 'not installed' 'placeholder inside parent checkout is not a bench checkout'
