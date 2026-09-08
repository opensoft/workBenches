# speckit-overlay-shape: 1
# Source this file from zsh to enable Speckit worktree helpers.
#
# Example:
#   source .specify/shell/ct.zsh
#
# The helpers are shape-aware: in an openRepoShape three-leg project ct/cta/
# ctc/ctg/cts start in the project root (the only place .specify/ exists) with
# SPECIFY_FEATURE and SPECIFY_FEATURE_DIRECTORY exported, while the feature's
# files live in worktrees/<NNN-feature>/<spec>/ and .../<code>/.

_speckit_ct_dir="${${(%):-%x}:A:h}"
source "$_speckit_ct_dir/worktrees.sh"
unset _speckit_ct_dir
