#!/bin/zsh

source "${0:A:h}/branding.sh"
test_script_dir="${0:A:h}"
test_repo_root="${test_script_dir:h:h}"
source <(sed '/^source /d; /^ebk_print_banner /d; /^main "\$@"$/d' "$test_script_dir/launchpad.sh")
test_root="$(mktemp -d)"
first_run=""
second_run=""
cleanup() {
  local run
  for run in "$first_run" "$second_run"; do
    if [[ -n "$run" && "$run" == "$test_repo_root/.run/launchpad/"* && -d "$run" ]]; then
      rm -f "$run/vscode_setup.log" "$run/intellij_setup.log" "$run/pycharm_setup.log" "$run/summary.json"
      rmdir "$run"
    fi
  done
  rm -f "$test_root/first.out" "$test_root/second.out" "$test_root/block" "$test_root/stream.out" "$test_root/stream.log"
  rmdir "$test_root"
}
trap cleanup EXIT

RUN_PARENT="$test_root"
date() { print -r -- "20260101-000000"; }
initialize_run_directory || exit 1
reserved_first="$RUN_ROOT"
initialize_run_directory || exit 1
reserved_second="$RUN_ROOT"
[[ "$reserved_first" != "$reserved_second" && -d "$reserved_first" && -d "$reserved_second" ]] || exit 1
rmdir "$reserved_first" "$reserved_second"
unfunction date
printf 'block' > "$test_root/block"
RUN_PARENT="$test_root/block"
initialize_run_directory >/dev/null
[[ "$?" != 0 && -z "$RUN_ROOT" ]] || exit 1

# A child prompt without a newline must remain visible while its process is running.
zsh -c 'printf "partial-prompt"; sleep 1; printf "\nfinished\n"' |
  capture_task_output "$test_root/stream.log" > "$test_root/stream.out" &
stream_pid=$!
sleep 0.2
grep -q partial-prompt "$test_root/stream.out"
prompt_rc=$?
wait "$stream_pid"
[[ "$?" == 0 && "$prompt_rc" == 0 ]] || exit 1
grep -qx finished "$test_root/stream.log" || exit 1

zsh "$test_script_dir/launchpad.sh" --profile ide-only --dry-run --yes > "$test_root/first.out" &
first_pid=$!
zsh "$test_script_dir/launchpad.sh" --profile ide-only --dry-run --yes > "$test_root/second.out" &
second_pid=$!
wait "$first_pid"
first_rc=$?
wait "$second_pid"
second_rc=$?
first_run="$(sed -n 's/^Logs: //p' "$test_root/first.out")"
second_run="$(sed -n 's/^Logs: //p' "$test_root/second.out")"
[[ "$first_rc" == 0 && "$second_rc" == 0 && -n "$first_run" && "$first_run" != "$second_run" ]] || exit 1
for output in "$test_root/first.out" "$test_root/second.out"; do
  run="$(sed -n 's/^Logs: //p' "$output")"
  [[ "$run" == "$test_repo_root/.run/launchpad/"* && -d "$run" ]] || exit 1
  grep -q "  Logs:    $run" "$output" || exit 1
  for id in vscode_setup intellij_setup pycharm_setup; do
    duration="$(awk -v id="$id" '$1 == id && $2 == "planned" {print $4}' "$output")"
    [[ "$duration" =~ '^[0-9]+\.[0-9]{5}$' ]] || exit 1
    [[ "$(grep -c '^Duration seconds:' "$run/$id.log")" == 1 ]] || exit 1
    grep -qx "Duration seconds: $duration" "$run/$id.log" || exit 1
  done
done
log_ok "Launchpad unique-directory and concurrent dry-run checks passed."
