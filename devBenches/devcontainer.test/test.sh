#!/bin/bash
# Layer 1a Test Script
# Tests dev-bench-base Layer 3 image for developer tools

set -uo pipefail

echo "=========================================="
echo "Testing Layer 1a: DevBench Base"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_count=0
pass_count=0
fail_count=0

# Test function
test_tool() {
    local name="$1"
    local command="$2"
    test_count=$((test_count + 1))
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name"
        pass_count=$((pass_count + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $name"
        fail_count=$((fail_count + 1))
        return 0
    fi
}

# Test function with output
test_tool_output() {
    local name="$1"
    local command="$2"
    test_count=$((test_count + 1))
    
    if output=$(eval "$command" 2>&1); then
        echo -e "${GREEN}✓${NC} $name: $output"
        pass_count=$((pass_count + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $name"
        fail_count=$((fail_count + 1))
        return 0
    fi
}

echo "=== Python Development ==="
test_tool_output "Python" "python3 --version"
test_tool_output "pip" "pip --version"
test_tool "black" "command -v black"
test_tool "flake8" "command -v flake8"
test_tool "isort" "command -v isort"
test_tool "pylint" "command -v pylint"
test_tool "pytest" "command -v pytest"
test_tool "ipython" "command -v ipython"

echo ""
echo "=== Node.js Development ==="
test_tool_output "Node.js" "node --version"
test_tool_output "npm" "npm --version"
test_tool_output "yarn" "yarn --version"
test_tool "/usr/local/bin in PATH" "echo \$PATH | grep -q '/usr/local/bin'"

echo ""
echo "=== Python Package Managers ==="
test_tool_output "uv" "uv --version"

echo ""
echo "=== Spec-Driven Development Tools ==="
test_tool "specify" "command -v specify"
test_tool "openspec" "command -v openspec"
test_tool "speckit-worktree-enable" "command -v speckit-worktree-enable"
test_tool "Speckit worktree bootstrap" "bash -lc 'tmpdir=\$(mktemp -d); repo=\"\$tmpdir/repo\"; trap \"rm -rf \\\"\$tmpdir\\\"\" EXIT; git init -q \"\$repo\"; mkdir -p \"\$repo/.specify/templates\"; cd \"\$repo\"; speckit-worktree-enable >/dev/null; test -f .specify/extensions.yml; grep -q \"speckit.git.feature\" .specify/extensions.yml; grep -q \"^- git\" .specify/extensions.yml; grep -q \"checkout_mode: worktree\" .specify/extensions/git/git-config.yml; grep -q \"worktree_root: ../repo-worktrees\" .specify/extensions/git/git-config.yml; speckit-worktree-enable --base-branch develop --worktree-root ../custom-worktrees >/dev/null; grep -q \"base_branch: develop\" .specify/extensions/git/git-config.yml; grep -q \"worktree_root: ../custom-worktrees\" .specify/extensions/git/git-config.yml; test -x .specify/extensions/git/scripts/bash/create-new-feature.sh; test -x .specify/shell/select-worktree.sh; test -f .claude/skills/speckit-specify/SKILL.md; test -f .claude/skills/speckit-git-feature/SKILL.md'"
test_tool "setup-openspeckit installs Speckit worktree system" "bash -lc 'tmpdir=\$(mktemp -d); repo=\"\$tmpdir/repo\"; feature_json=\"\$tmpdir/feature.json\"; trap \"rm -rf \\\"\$tmpdir\\\"\" EXIT; git init -q -b main \"\$repo\"; git -C \"\$repo\" -c user.name=Test -c user.email=test@example.com commit --allow-empty -m initial >/dev/null; AGENT_PROTOCOL_ROOT=\"\$tmpdir/agents\" setup-openspeckit --repo \"\$repo\" --no-skill-links --no-global-agent-pointers --no-repo-agent-pointers --preserve-readmes >/dev/null; test -f \"\$tmpdir/agents/AGENTS.md\"; test -f \"\$tmpdir/agents/protocols/openspec-speckit-workflow.md\"; test -f \"\$tmpdir/agents/protocols/project-agent-bootstrap.md\"; cd \"\$repo\"; test -f .specify/extensions/.registry; test -f .specify/workflows/workflow-registry.json; specify extension list | grep -q \"Git Branching Workflow\"; specify workflow list | grep -q \"Full SDD Cycle\"; grep -q \"checkout_mode: worktree\" .specify/extensions/git/git-config.yml; grep -q \"worktree_root: ../repo-worktrees\" .specify/extensions/git/git-config.yml; .specify/extensions/git/scripts/bash/create-new-feature.sh --json --short-name smoke \"Smoke feature\" > \"\$feature_json\"; grep -q \"\\\"CHECKOUT_MODE\\\":\\\"worktree\\\"\" \"\$feature_json\"; test -d \"\$tmpdir/repo-worktrees/001-smoke\"; test \"\$(bash .specify/shell/select-worktree.sh --path)\" = \"\$tmpdir/repo-worktrees/001-smoke\"'"

echo ""
echo "=== AI CLI Tools ==="
test_tool "claude" "command -v claude"
test_tool "codex" "command -v codex"
test_tool "agy" "command -v agy"
test_tool_output "opencode" "opencode --version"

echo ""
echo "=== Code Quality Tools ==="
test_tool_output "SonarScanner CLI" "sonar-scanner --version | grep 'SonarScanner CLI'"
test_tool_output "SonarQube CLI" "sonar --version"
test_tool_output "Graphite CLI" "gt --version"
test_tool "Sonar env helper" "command -v sonar-env"
test_tool "Sonar env helper configures keychain" "sonar-env --check | grep -q 'SONARQUBE_CLI_KEYCHAIN_FILE=.*sonarqube-cli/keychain.json'"
test_tool "Sonar env helper loads token aliases" "bash -lc 'tmpdir=\$(mktemp -d); trap \"rm -rf \\\"\$tmpdir\\\"\" EXIT; printf \"SONARQUBE_TOKEN=test-token\nSONARQUBE_ORG=test-org\n\" > \"\$tmpdir/sonar.env\"; SONARQUBE_ENV_FILE=\"\$tmpdir/sonar.env\" sonar-env -- sh -c \"test \\\"\$SONAR_TOKEN\\\" = test-token && test \\\"\$SONAR_ORGANIZATION\\\" = test-org && test \\\"\$SONARQUBE_CLI_TOKEN\\\" = test-token && test \\\"\$SONARQUBE_CLI_ORG\\\" = test-org\"'"
test_tool "Sonar env available in login bash" "bash -lc 'test -n \"\$SONARQUBE_CLI_KEYCHAIN_FILE\" && test -n \"\$SONAR_HOST_URL\" && test \"\$SONARQUBE_CLI_SERVER\" = \"\$SONAR_HOST_URL\"'"
test_tool "Sonar env available in interactive zsh" "zsh -ic 'test -n \"\$SONARQUBE_CLI_KEYCHAIN_FILE\" && test -n \"\$SONAR_HOST_URL\" && test \"\$SONARQUBE_CLI_SERVER\" = \"\$SONAR_HOST_URL\"'"
test_tool "Sonar env wraps commands" "sonar-env -- sh -c 'test -n \"\$SONARQUBE_CLI_KEYCHAIN_FILE\" && test -n \"\$SONAR_HOST_URL\" && test \"\$SONARQUBE_CLI_SERVER\" = \"\$SONAR_HOST_URL\"'"

echo ""
echo "=== OpenCode Configuration ==="
test_tool "OpenCode config exists" "test -f ~/.config/opencode/opencode.json"
test_tool "oh-my-opencode plugin configured" "grep -q 'oh-my-opencode' ~/.config/opencode/opencode.json"
test_tool "opencode-openai-codex-auth plugin configured" "grep -q 'opencode-openai-codex-auth' ~/.config/opencode/opencode.json"

echo ""
echo "=== Shell Environment ==="
test_tool_output "zsh" "zsh --version"
test_tool "oh-my-zsh" "test -d ~/.oh-my-zsh"
test_tool "zsh-autosuggestions" "test -d ~/.oh-my-zsh/plugins/zsh-autosuggestions"
test_tool "zsh-syntax-highlighting" "test -d ~/.oh-my-zsh/plugins/zsh-syntax-highlighting"
test_tool "ct helper file" "test -f /usr/local/share/ct/ct-functions.zsh"
test_tool "Speckit dashboard dependency-aware blocked markers" "bash -lc 'tmpdir=\$(mktemp -d); repo=\"\$tmpdir/repo\"; trap \"rm -rf \\\"\$tmpdir\\\"\" EXIT; git init -q \"\$repo\"; mkdir -p \"\$repo/specs/master\" \"\$repo/.claude\"; { printf \"%s\n\" \"# Tasks\" \"\" \"## Phase 1: Setup\" \"\" \"- [x] T001 Build prerequisite service\" \"- [ ] T002 Add operator_identity field wiring\" \"- [ ] T003 Add provider-rejected blocked display depends on T001\" \"- [ ] T004 Add final integration depends on T005\" \"- [ ] T005 Build upstream adapter\" \"- [ ] T006 BLOCKED: waiting on product decision\" \"\" \"## Phase 2: User Story 1 - Main Flow (Priority: P1)\" \"\" \"- [ ] T007 Add operator-facing docs\"; } > \"\$repo/specs/master/tasks.md\"; SPECKIT_DASHBOARD_CWD=\"\$repo\" SPECKIT_DASHBOARD_FILE=\"\$tmpdir/dash.md\" SPECKIT_DASHBOARD_FORCE=1 SPECKIT_DASHBOARD_SYNC_REASON=timer bash /usr/local/share/ct/claude/speckit-dashboard-sync.sh; grep -q \"○  T002 Add operator_identity\" \"\$tmpdir/dash.md\" && grep -q \"○  T003 Add provider-rejected blocked display depends on T0\" \"\$tmpdir/dash.md\" && grep -q \"🔴 T004 Add final integration depends on T005\" \"\$tmpdir/dash.md\" && grep -q \"○  T005 Build upstream adapter\" \"\$tmpdir/dash.md\" && grep -q \"🔴 T006 BLOCKED:\" \"\$tmpdir/dash.md\" && grep -q \"○  T007 Add operator-facing docs\" \"\$tmpdir/dash.md\" && grep -q \"○  Pull Request             PR -- rev 0 fix 0\" \"\$tmpdir/dash.md\" && grep -q \"PROMPTS                     none yet\" \"\$tmpdir/dash.md\"'"
test_tool "ct helpers in interactive zsh" "zsh -ic 'for fn in ct ctp ctlist cta ctc ctg cts; do whence -w \"\$fn\" | grep -q \"function\" || exit 1; done'"
test_tool "ctlist outside Speckit repo errors cleanly" "bash -lc 'tmpdir=\$(mktemp -d); outfile=\$(mktemp); cd \"\$tmpdir\"; if zsh -ic \"ctlist\" >\"\$outfile\" 2>&1; then rm -rf \"\$tmpdir\" \"\$outfile\"; exit 1; fi; grep -Eq \"ct: not inside a Git repository|ct: \\.specify/ not found in repo root\" \"\$outfile\"; status=\$?; rm -rf \"\$tmpdir\" \"\$outfile\"; exit \$status'"
test_tool "ct launchers apply permissive CLI defaults" "/test/test-ct-launchers.sh"

echo ""
echo "=== PATH Configuration ==="
test_tool "~/.local/bin in PATH" "echo \$PATH | grep -q '.local/bin'"
test_tool "~/.bun/bin in PATH" "echo \$PATH | grep -q '.bun/bin'"

echo ""
echo "=== Git Configuration ==="
test_tool "git credential helper" "git config --global credential.helper | grep -q 'gh'"

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo -e "Total: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✓ All Layer 1a tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
