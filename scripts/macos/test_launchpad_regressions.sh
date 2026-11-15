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
