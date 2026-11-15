#!/bin/zsh

source "${0:A:h}/branding.sh"
source <(sed '/^source /d; /^ebk_print_banner /d; /^main "\$@"$/d' "${0:A:h}/launchpad.sh")
SCRIPT_DIR="${0:A:h}"

test_root="$(mktemp -d)"
trap 'rm -f "$test_root/bin/brew" "$test_root/bin/new-tool" "$test_root/block" "$test_root/logs/dock_setup.log"; rmdir "$test_root/logs" "$test_root/bin" "$test_root"' EXIT
mkdir "$test_root/bin"
printf '#!/bin/zsh\nprint -r -- "%s"\n' "$test_root" > "$test_root/bin/brew"
printf '#!/bin/zsh\nexit 0\n' > "$test_root/bin/new-tool"
chmod +x "$test_root/bin/brew" "$test_root/bin/new-tool"
register_tasks
original_path="$PATH"
brew() { "$test_root/bin/brew" "$@"; }
# command -v returns the function name, which resolves to the fake brew.
refresh_install_environment pre_setup || exit 1
command_exists new-tool || exit 1
[[ "$HOMEBREW_PREFIX" == "$test_root" && "$PATH" == *"$original_path"* ]] || exit 1
refresh_install_environment pre_setup || exit 1
matches=("${(@M)path:#$test_root/bin}")
[[ "${#matches}" == 1 ]] || exit 1
brew() { return 1; }
if refresh_install_environment pre_setup; then
  log_error "Expected an environment refresh failure."
  exit 1
fi
refresh_install_environment git_setup || exit 1
log_ok "Launchpad environment regression checks passed."

RUN_ROOT="$test_root/logs"
build_command() { cmd=(zsh -c 'printf "\033[31mchild-output\033[0m\n"; exit "$1"' test "$mock_exit"); }
authorize_admin_for_task() { return 0; }
check_task_ready() { return 0; }
mock_exit=0
run_task dock_setup >/dev/null || exit 1
[[ "${TASK_STATUS[dock_setup]}" == success && "${TASK_CHILD_EXIT[dock_setup]}" == 0 ]] || exit 1
grep -qx 'child-output' "$RUN_ROOT/dock_setup.log" || exit 1
mock_exit=7
run_task dock_setup >/dev/null
[[ "$?" == 7 && "${TASK_EXIT[dock_setup]}" == 7 ]] || exit 1
TASK_CHILD_EXIT=()
printf 'block' > "$test_root/block"
RUN_ROOT="$test_root/block/logs"
run_task dock_setup >/dev/null
[[ "$?" != 0 && "${TASK_STATUS[dock_setup]}" == failed && "${TASK_DURATION[dock_setup]}" != "" ]] || exit 1
RUN_ROOT="$test_root/logs"
original_capture="${functions[capture_task_output]}"
capture_task_output() { cat >/dev/null; return 1; }
mock_exit=0
run_task dock_setup >/dev/null
[[ "$?" == 1 && "${TASK_STATUS[dock_setup]}" == failed && "${TASK_CHILD_EXIT[dock_setup]}" == 0 ]] || exit 1
mock_exit=7
run_task dock_setup >/dev/null
[[ "$?" == 7 && "${TASK_EXIT[dock_setup]}" == 7 ]] || exit 1
functions[capture_task_output]="$original_capture"
printf() {
  [[ "$1" == 'Duration seconds: %s\n' ]] && return 1
  builtin printf "$@"
}
mock_exit=0
run_task dock_setup >/dev/null
[[ "$?" == 1 && "${TASK_STATUS[dock_setup]}" == failed ]] || exit 1
unfunction printf
build_command() { cmd=("$test_root/missing-command"); }
run_task dock_setup >/dev/null
[[ "$?" == 127 && "${TASK_EXIT[dock_setup]}" == 127 ]] || exit 1

signal_summary="$(zsh -c '
  launchpad_dir="$1"
  shift
  source "$launchpad_dir/branding.sh"
  source <(sed "/^source /d; /^ebk_print_banner /d; /^main \"\\\$@\"$/d" "$launchpad_dir/launchpad.sh")
  PROFILE=ide-only
  prompt_optional_tasks() { return 0; }
  prompt_task_values() { return 0; }
  print_plan() { return 0; }
  initialize_run_directory() { return 0; }
  confirm_plan() { return 0; }
  run_selected_tasks() {
    CURRENT_TASK=vscode_setup
    CURRENT_TASK_STARTED="$SECONDS"
    kill -TERM $$
  }
  main
' signal "$SCRIPT_DIR")"
[[ "$?" == 143 && "$signal_summary" == *"Launchpad summary"* && "$signal_summary" == *"failed"* ]] || exit 1
[[ "$(print -r -- "$signal_summary" | grep -c 'PHASE Launchpad summary')" == 1 ]] || exit 1
log_ok "Launchpad infrastructure regression checks passed."

task_is_critical setup_env_min || exit 1
SELECTED=()
INCLUDED_BY_DEP=()
select_with_deps setup_env_min || exit 1
[[ "${INCLUDED_BY_DEP[pre_setup]:-}" == 1 ]] || exit 1
select_with_deps pre_setup || exit 1
[[ -z "${INCLUDED_BY_DEP[pre_setup]:-}" ]] || exit 1
TASK_ORDER=(prereq dependant independent)
SELECTED=(prereq 1 dependant 1 independent 1)
TASK_LABEL=(prereq Prerequisite dependant Dependant independent Independent)
TASK_DEPS=(dependant prereq)
run_task() {
  executed+=("$1")
  if [[ "$1" == prereq ]]; then
    TASK_STATUS[$1]="$prereq_state"
    [[ "$prereq_state" == failed ]] && return 7
  else
    TASK_STATUS[$1]=success
  fi
  return 0
}
for prereq_state in success skipped failed issues planned; do
  TASK_STATUS=()
  TASK_EXIT=()
  TASK_BLOCK_REASON=()
  TASK_DURATION=()
  executed=()
  DRY_RUN=0
  [[ "$prereq_state" == planned ]] && DRY_RUN=1
  run_selected_tasks >/dev/null
  rc=$?
  if [[ "$prereq_state" == success || "$prereq_state" == planned ]]; then
    [[ "$rc" == 0 && "${#executed}" == 3 ]] || exit 1
  else
    [[ "$rc" != 0 && "${TASK_STATUS[dependant]}" == blocked && "${executed[*]}" == "prereq independent" ]] || exit 1
    [[ "${TASK_BLOCK_REASON[dependant]}" == "Prerequisite prereq is $prereq_state." && -z "${TASK_DURATION[dependant]:-}" ]] || exit 1
  fi
done
TASK_ORDER=(setup_env_min dependant independent)
SELECTED=(setup_env_min 1 dependant 1 independent 1)
TASK_LABEL[setup_env_min]="Minimal setup"
TASK_DEPS=(dependant setup_env_min)
run_task() { executed+=("$1"); TASK_STATUS[$1]=failed; return 7; }
for CONTINUE_ON_ERROR in 0 1; do
  TASK_STATUS=()
  executed=()
  run_selected_tasks >/dev/null
  [[ "$?" == 7 && "${#executed}" == 1 && "${TASK_STATUS[dependant]}" == blocked ]] || exit 1
done
summary="$(print_summary)"
[[ "$summary" == *"Blocked: 1"* && "$summary" == *"Prerequisite setup_env_min is failed."* ]] || exit 1
log_ok "Launchpad dependency and critical-policy regression checks passed."

if ! printf 'typo\n3\n' | (PROFILE=""; prompt_profile >/dev/null && [[ "$PROFILE" == ide-only ]]); then
  log_error "Invalid profile input did not reprompt."
  exit 1
fi
if ! printf '\n' | (PROFILE=""; prompt_profile >/dev/null && [[ "$PROFILE" == full ]]); then
  log_error "Blank profile input did not retain its default."
  exit 1
fi
PROFILE=""
prompt_profile </dev/null >/dev/null
[[ "$?" == 1 && -z "$PROFILE" ]] || exit 1
DRY_RUN=0
ASSUME_YES=0
printf 'invalid\nyes\n' | (confirm_plan >/dev/null) || exit 1
printf '\n' | (confirm_plan >/dev/null) || exit 1
printf 'no\n' | (confirm_plan >/dev/null)
[[ "$?" == 1 ]] || exit 1
confirm_plan </dev/null >/dev/null
[[ "$?" == 2 ]] || exit 1
read_launchpad_line "Required path: " </dev/null >/dev/null
[[ "$?" == 1 ]] || exit 1
ASSUME_YES=1
confirm_plan </dev/null >/dev/null || exit 1
TASK_ORDER=()
SELECTED=()
INCLUDED_BY_DEP=()
register_tasks
select_profile_tasks full
clone_destination=""
prompt_task_values </dev/null || exit 1
[[ -z "${SELECTED[clone_repos]:-}" ]] || exit 1
clone_destination="$test_root"
select_with_deps clone_repos
prompt_task_values </dev/null || exit 1
[[ "${SELECTED[clone_repos]:-}" == 1 ]] || exit 1
codex_backup_path="$test_root"
prompt_optional_tasks </dev/null || exit 1
[[ "${SELECTED[restore_codex]:-}" == 1 ]] || exit 1
PROFILE=ide-only
prompt_optional_tasks() { return 1; }
main >/dev/null
[[ "$?" == 1 ]] || exit 1
log_ok "Launchpad prompt and EOF regression checks passed."
