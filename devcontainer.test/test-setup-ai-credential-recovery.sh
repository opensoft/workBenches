#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
fixture="$test_root/workBenches"
mkdir -p "$fixture/scripts/lib" "$fixture/credential-container" "$test_root/bin" "$test_root/home/.config/workbenches"
cp "$repo_root/scripts/setup-ai-profiles.sh" "$fixture/scripts/"
cp "$repo_root/scripts/lib/openbenches-compat.sh" "$fixture/scripts/lib/"
cp "$repo_root/scripts/"{setup-credential-recovery.py,setup_prompts.py,profile_credentials.py,openbenches_compat.py} "$fixture/scripts/"
cp "$repo_root/credential-container/credential_recovery.py" "$fixture/credential-container/"
export TEST_PYTHON="$(command -v python3)"
cat > "$fixture/scripts/setup-claude-profiles.sh" <<'EOF'
#!/usr/bin/env bash
echo profiles >> "$TEST_LOG"
EOF
cat > "$fixture/scripts/backup-ai-profile-credentials-to-kv.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == restore && "$2" == --manifest && "$4" == --azure-login ]]
echo recovery >> "$TEST_LOG"
exit "${TEST_RECOVERY_EXIT:-0}"
EOF
cat > "$test_root/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == */setup-credential-recovery.py ]]; then exec "$TEST_PYTHON" "$@"; fi
exit 0
EOF
cat > "$test_root/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == context ]]; then echo unix:///var/run/docker.sock; fi
EOF
chmod +x "$fixture/scripts/"*.sh "$test_root/bin/"*
config_dir="$test_root/home/.config/workbenches"
printf '{"profiles":[]}' > "$config_dir/claude-profiles.json"
printf '{}' > "$config_dir/ai-credential-keyvault.json"
export HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" PATH="$test_root/bin:$PATH"
export TEST_LOG="$test_root/actions"
unset AI_CREDENTIAL_KV_MANIFEST WORKBENCHES_SKIP_CREDENTIAL_RECOVERY TEST_RECOVERY_EXIT

: > "$TEST_LOG"
output="$(bash "$fixture/scripts/setup-ai-profiles.sh" --apply-existing)"
[[ "$(cat "$TEST_LOG")" == $'profiles\nrecovery' ]]
echo 'PASS: recovery follows profile creation'

: > "$TEST_LOG"
output="$(TEST_RECOVERY_EXIT=1 bash "$fixture/scripts/setup-ai-profiles.sh" --apply-existing)"
[[ "$output" == *'provider sign-in remains available'* ]]
echo 'PASS: failed recovery retains provider sign-in and lets setup continue'

cancel_status=0
TEST_RECOVERY_EXIT=130 bash "$fixture/scripts/setup-ai-profiles.sh" --apply-existing >/dev/null || cancel_status=$?
[[ "$cancel_status" == 130 ]]
echo 'PASS: cancelled recovery stops profile setup'

: > "$TEST_LOG"
WORKBENCHES_SKIP_CREDENTIAL_RECOVERY=1 bash "$fixture/scripts/setup-ai-profiles.sh" --apply-existing >/dev/null
[[ "$(cat "$TEST_LOG")" == profiles ]]
echo 'PASS: explicit recovery skip is honored'

rm "$config_dir/ai-credential-keyvault.json"
: > "$TEST_LOG"
bash "$fixture/scripts/setup-ai-profiles.sh" --apply-existing >/dev/null
[[ "$(cat "$TEST_LOG")" == profiles ]]
echo 'PASS: no vault mapping means no recovery or Azure installation'
