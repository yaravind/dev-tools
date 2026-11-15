#!/bin/zsh

source "${0:A:h}/branding.sh"
source <(sed '/^source /d; /^ebk_print_banner /d; /^main "\$@"$/d' "${0:A:h}/launchpad.sh")
TASK_ORDER=(test)
SELECTED=(test 1)
construction_count=0
build_task_command() {
  ((construction_count++))
  cmd=(printf '%s\n' "" "path with spaces" "single'quote" 'double"quote' '$literal' $'line\nbreak')
}
freeze_task_commands || exit 1
expected=("${cmd[@]}")
build_task_command() { return 1; }
for attempt in 1 2 3; do
  build_command test || exit 1
  [[ "${#cmd}" == "${#expected}" ]] || exit 1
  for index in {1..${#cmd}}; do
    [[ "${cmd[$index]}" == "${expected[$index]}" ]] || exit 1
  done
done
[[ "$construction_count" == 1 ]] || exit 1
display="$(command_text test)"
parsed=("${(@Q)${(z)display}}")
[[ "${#parsed}" == "${#expected}" ]] || exit 1
for index in {1..${#parsed}}; do
  [[ "${parsed[$index]}" == "${expected[$index]}" ]] || exit 1
done
log_ok "Launchpad frozen-command and quoting regression checks passed."
