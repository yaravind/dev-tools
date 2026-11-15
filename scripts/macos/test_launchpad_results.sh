#!/bin/zsh

source "${0:A:h}/branding.sh"
test_script_dir="${0:A:h}"
source <(sed '/^source /d; /^ebk_print_banner /d; /^main "\$@"$/d' "$test_script_dir/launchpad.sh")
RUN_ROOT="$(mktemp -d)"
trap 'rm -f "$RUN_ROOT/intellij_setup.log" "$RUN_ROOT/intellij_setup.result.json" "$RUN_ROOT/summary.json"; rmdir "$RUN_ROOT"' EXIT
register_tasks
SELECTED=(intellij_setup 1 pending 1)
TASK_ORDER=(intellij_setup pending)
TASK_LABEL[pending]=Pending
authorize_admin_for_task() { return 0; }
check_task_ready() { return 0; }
build_command() {
  cmd=(zsh -c '
    source "$1/branding.sh"
    if [[ "$2" != absent ]]; then ebk_write_task_result "$2" "$3" || exit 1; fi
    print "Status COMPLETED WITH ISSUES"
    print "Failed installs 0"
    exit "$4"
  ' result "$test_script_dir" "$mock_state" "$mock_failed" "$mock_rc")
}
for mock_state in success issues skipped failed absent; do
  mock_failed=0
  mock_rc=0
  expected=success
  expected_rc=0
  case "$mock_state" in
    issues) mock_rc=1; expected=issues ;;
    skipped) mock_rc=75; expected=skipped ;;
    failed) mock_rc=1; mock_failed=2; expected=failed; expected_rc=1 ;;
    absent) mock_rc=1; expected=failed; expected_rc=1 ;;
  esac
  run_task intellij_setup >/dev/null
  [[ "$?" == "$expected_rc" && "${TASK_STATUS[intellij_setup]}" == "$expected" && "${TASK_CHILD_EXIT[intellij_setup]}" == "$mock_rc" ]] || exit 1
done
EBK_RESULT_FILE="$RUN_ROOT/intellij_setup.result.json"
for invalid in '{"schema_version":2,"status":"success","failed_installs":0}' \
  '{"schema_version":1,"status":"issues","failed_installs":1}' \
  '{"schema_version":"1","status":"success","failed_installs":0}' \
  '{"schema_version":1,"status":"success","failed_installs":"0"}' 'not-json'; do
  print -r -- "$invalid" > "$EBK_RESULT_FILE"
  read_child_result "$EBK_RESULT_FILE" 1 >/dev/null
  [[ "$?" == 1 ]] || exit 1
done
ebk_write_task_result failed 1 || exit 1
read_child_result "$EBK_RESULT_FILE" 0 >/dev/null
[[ "$?" == 1 ]] || exit 1
for child_script in intellij_setup.sh pycharm_setup.sh; do
  for fail_count in 0 2; do
    overall_status="COMPLETED WITH ISSUES"
    source <(sed -n '/^result_state=success$/,/^ebk_write_task_result /p' "$test_script_dir/$child_script")
    read_child_result "$EBK_RESULT_FILE" 1 || exit 1
    expected=issues
    (( fail_count > 0 )) && expected=failed
    [[ "$REPLY" == "$expected" ]] || exit 1
  done
done
RUN_DURATION=1.23456
write_run_summary || exit 1
perl -MJSON::PP -e '
  local $/; my $s=decode_json(<>);
  die "Bad summary" unless $s->{schema_version}==1 && $s->{duration_seconds}==1.23456 &&
    @{$s->{tasks}}==2 && $s->{tasks}[0]{status} eq "failed" &&
    $s->{tasks}[0]{exit_code}==1 && $s->{tasks}[0]{child_exit_code}==1 &&
    $s->{tasks}[0]{duration_seconds}>0 &&
    $s->{tasks}[1]{status} eq "not-run" && !defined($s->{tasks}[1]{duration_seconds});
' "$RUN_ROOT/summary.json" || exit 1
log_ok "Launchpad structured-result and JSON summary checks passed."
