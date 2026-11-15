#!/bin/zsh

source "${0:A:h}/branding.sh"
test_script_dir="${0:A:h}"
source <(sed '/^source /d; /^ebk_print_banner /d; /^main "\$@"$/d' "$test_script_dir/launchpad.sh")
RUN_ROOT="$(mktemp -d)"
trap 'rm -f "$RUN_ROOT/pre_setup.log" "$RUN_ROOT/new_tool.log" "$RUN_ROOT/prereq.log" "$RUN_ROOT/summary.json" "$RUN_ROOT/bin/brew" "$RUN_ROOT/bin/new-tool" "$RUN_ROOT/child-started"; rmdir "$RUN_ROOT/bin" "$RUN_ROOT"' EXIT
mkdir "$RUN_ROOT/bin"
printf '#!/bin/zsh\nprint -r -- "%s"\n' "$RUN_ROOT" > "$RUN_ROOT/bin/brew"
printf '#!/bin/zsh\nprint ready\n' > "$RUN_ROOT/bin/new-tool"
chmod +x "$RUN_ROOT/bin/brew" "$RUN_ROOT/bin/new-tool"
brew() { "$RUN_ROOT/bin/brew" "$@"; }
TASK_ORDER=(pre_setup new_tool)
TASK_LABEL=(pre_setup Preparation new_tool "New tool")
SELECTED=(pre_setup 1 new_tool 1)
TASK_DEPS=(new_tool pre_setup)
authorize_admin_for_task() { return 0; }
check_task_ready() {
  if [[ "$1" == new_tool ]]; then require_command new-tool "New tool"; else return 0; fi
}
build_command() {
  if [[ "$1" == pre_setup ]]; then cmd=(zsh -c 'exit 0'); else cmd=(new-tool); fi
}
run_selected_tasks >/dev/null || exit 1
[[ "${TASK_STATUS[new_tool]}" == success ]] || exit 1
grep -qx ready "$RUN_ROOT/new_tool.log" || exit 1

TASK_ORDER=(prereq dependent chained independent)
TASK_LABEL=(prereq Prerequisite dependent Dependent chained Chained independent Independent)
TASK_DEPS=(dependent prereq chained dependent)
SELECTED=(prereq 1 dependent 1 chained 1 independent 1)
TASK_STATUS=()
TASK_CHILD_EXIT=()
TASK_DURATION=()
TASK_EXIT=()
TASK_LOG=()
task_is_critical() { [[ "$1" == prereq ]]; }
check_task_ready() { return 0; }
build_command() { cmd=(zsh -c 'exit 7'); }
run_selected_tasks >/dev/null
[[ "$?" == 7 && "${TASK_STATUS[dependent]}" == blocked && "${TASK_STATUS[chained]}" == blocked && -z "${TASK_STATUS[independent]:-}" ]] || exit 1
RUN_DURATION=1.23456
write_run_summary || exit 1
perl -MJSON::PP -e '
  local $/; my $s=decode_json(<>);
  die "Critical failure summary mismatch" unless
    join(",",map {$_->{status}} @{$s->{tasks}}) eq "failed,blocked,blocked,not-run";
  for my $r (@{$s->{tasks}}[1..3]) {
    die "Unexecuted task was timed or started" if defined $r->{duration_seconds} || defined $r->{child_exit_code};
  }
' "$RUN_ROOT/summary.json" || exit 1
TASK_STATUS=()
check_task_dependencies dependent >/dev/null
[[ "$?" == 1 && "${TASK_BLOCK_REASON[dependent]}" == "Prerequisite prereq is not-run." ]] || exit 1
EBK_RESULT_FILE="$RUN_ROOT/missing/result.json"
ebk_write_task_result success 0 >/dev/null
[[ "$?" == 1 ]] || exit 1
rm -f "$RUN_ROOT/summary.json"
mkdir "$RUN_ROOT/summary.json"
write_run_summary >/dev/null
[[ "$?" == 1 ]] || exit 1
rmdir "$RUN_ROOT/summary.json"
log_ok "Launchpad environment handoff and whole-run failure checks passed."
