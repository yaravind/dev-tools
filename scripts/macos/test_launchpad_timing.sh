#!/bin/zsh

source "${0:A:h}/branding.sh"
source <(sed '/^source /d; /^ebk_print_banner /d; /^main "\$@"$/d' "${0:A:h}/launchpad.sh")

RUN_ROOT="$(mktemp -d)"
trap 'rm -f "${RUN_ROOT}/dock_setup.log"; rmdir "$RUN_ROOT"' EXIT
TASK_ORDER=(dock_setup pending)
SELECTED[dock_setup]=1
SELECTED[pending]=1
TASK_LABEL[dock_setup]="Timing test"
TASK_ADMIN[dock_setup]=0
TASK_SOFT_FAIL[dock_setup]=0
mock_mode=""

build_command() {
  [[ "$mock_mode" == "build-failure" ]] && return 1
  cmd=(zsh -c 'sleep "$1"; exit "$2"' timing "$mock_delay" "$mock_exit")
}
authorize_admin_for_task() {
  if [[ "$mock_mode" == "admin-skip" ]]; then
    TASK_STATUS[$1]="skipped"
    return 2
  fi
  [[ "$mock_mode" == "admin-failure" ]] && return 1
  return 0
}
check_task_ready() { [[ "$mock_mode" != "readiness-failure" ]]; }

for mock_mode in success failure dock-skip admin-skip admin-failure readiness-failure build-failure planned; do
  TASK_LOG=()
  TASK_STATUS=()
  TASK_EXIT=()
  TASK_DURATION=()
  rm -f "${RUN_ROOT}/dock_setup.log"
  DRY_RUN=0
  mock_delay=0.02
  mock_exit=0
  expected_state=failed
  expected_rc=1
  case "$mock_mode" in
    success) mock_delay=1.02; expected_state=success; expected_rc=0 ;;
    failure) mock_exit=1 ;;
    dock-skip) mock_exit=75; expected_state=skipped; expected_rc=0 ;;
    admin-skip) expected_state=skipped; expected_rc=0 ;;
    planned) DRY_RUN=1; expected_state=planned; expected_rc=0 ;;
  esac

  run_task dock_setup >/dev/null
  actual_rc=$?
  [[ "$actual_rc" == "$expected_rc" && "${TASK_STATUS[dock_setup]}" == "$expected_state" ]] || exit 1
  duration="${TASK_DURATION[dock_setup]}"
  [[ "$duration" =~ '^[0-9]+\.[0-9]{5}$' ]] || exit 1
  if [[ "$mock_mode" == "success" ]]; then
    (( duration >= 1.02 )) || exit 1
  elif [[ "$mock_mode" == "planned" ]]; then
    (( duration > 0 && duration < 1 )) || exit 1
  fi
  if [[ -f "${RUN_ROOT}/dock_setup.log" ]]; then
    [[ "$(grep -c '^Duration seconds:' "${RUN_ROOT}/dock_setup.log")" == 1 ]] || exit 1
    grep -qx "Duration seconds: $duration" "${RUN_ROOT}/dock_setup.log" || exit 1
  fi
done

RUN_DURATION=1.23456
summary="$(print_summary)"
[[ "$summary" == *"Time (s)"* && "$summary" == *"Overall execution time (s): 1.23456"* ]] || exit 1
print -r -- "$summary" | grep -Eq '^  pending +not-run +- +- +-$' || exit 1
log_ok "Launchpad timing checks passed (precision, outcomes, logs, and not-run tasks)."
