#!/bin/zsh

source "${0:A:h}/colors.sh"

SCRIPT_DIR="${0:A:h}"
PYCHARM_PLUGIN_FILE="$(cd "${SCRIPT_DIR}/../../config" && pwd -P)/pycharm.txt"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

log_step() {
  printf "${MAGENTA}===> %s${RESET}\n" "$1"
}

log_info() {
  printf "${CYAN}===> %s${RESET}\n" "$1"
}

log_ok() {
  printf "${GREEN}===> %s${RESET}\n" "$1"
}

log_warn() {
  printf "${YELLOW}===> WARN: %s${RESET}\n" "$1"
}

log_error() {
  printf "${RED}ERROR: %s${RESET}\n" "$1" >&2
}

trim() {
  local value="$1"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

resolve_pycharm_cli() {
  if command_exists charm; then
    PYCHARM_CLI=(charm)
    return 0
  fi

  if command_exists pycharm; then
    PYCHARM_CLI=(pycharm)
    return 0
  fi

  local candidate
  local candidates=(
    "/Applications/PyCharm.app/Contents/MacOS/pycharm"
    "/Applications/PyCharm CE.app/Contents/MacOS/pycharm"
    "${HOME}/Applications/PyCharm.app/Contents/MacOS/pycharm"
    "${HOME}/Applications/PyCharm CE.app/Contents/MacOS/pycharm"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      PYCHARM_CLI=("$candidate")
      return 0
    fi
  done

  return 1
}

is_pycharm_running() {
  pgrep -f "PyCharm" >/dev/null 2>&1
}

install_plugin() {
  local plugin_id="$1"
  local install_output

  log_info "Installing PyCharm plugin: ${plugin_id}"
  install_output="$("${PYCHARM_CLI[@]}" installPlugins "$plugin_id" 2>&1)"
  local status=$?
  if [[ -n "$install_output" ]]; then
    printf '%s\n' "$install_output"
  fi

  if [[ "$install_output" == *"already installed"* ]]; then
    return 2
  fi

  if [[ $status -eq 0 ]]; then
    return 0
  fi

  return 1
}

if [[ ! -f "$PYCHARM_PLUGIN_FILE" ]]; then
  log_error "${PYCHARM_PLUGIN_FILE} not found. Please create it with PyCharm plugin IDs."
  exit 1
fi

if ! resolve_pycharm_cli; then
  log_error "PyCharm CLI not found. Add 'charm' to PATH (Tools > Create Command-line Launcher) or install PyCharm in /Applications."
  exit 1
fi

if is_pycharm_running; then
  log_error "PyCharm appears to be running. Quit PyCharm, then re-run this script."
  exit 1
fi

log_step "Reading PyCharm plugin IDs from ${PYCHARM_PLUGIN_FILE}"

plugins_to_install=()
duplicate_count=0
invalid_count=0
seen_plugins=$'\n'

while IFS= read -r plugin_id || [[ -n "$plugin_id" ]]; do
  plugin_id="$(trim "$plugin_id")"

  if [[ -z "$plugin_id" || "$plugin_id" == \#* ]]; then
    continue
  fi

  if ! printf '%s\n' "$plugin_id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9 ._-]*$'; then
    log_warn "Ignoring invalid plugin ID \"${plugin_id}\"."
    ((invalid_count++))
    continue
  fi

  if [[ "$seen_plugins" == *$'\n'"$plugin_id"$'\n'* ]]; then
    log_warn "Duplicate plugin ID \"${plugin_id}\" in config. Ignoring duplicate entry."
    ((duplicate_count++))
    continue
  fi

  seen_plugins+="${plugin_id}"$'\n'
  plugins_to_install+=("$plugin_id")
done < "$PYCHARM_PLUGIN_FILE"

if (( ${#plugins_to_install[@]} == 0 )); then
  log_error "No valid plugin IDs found in ${PYCHARM_PLUGIN_FILE}."
  exit 1
fi

log_step "Using PyCharm launcher: ${PYCHARM_CLI[1]}"
log_info "Total plugin IDs queued: ${#plugins_to_install[@]}"

install_count=0
skip_count=0
fail_count=0

for plugin_id in "${plugins_to_install[@]}"; do
  install_plugin "$plugin_id"
  install_status=$?

  case "$install_status" in
    0)
      log_ok "Installed \"${plugin_id}\"."
      ((install_count++))
      ;;
    2)
      log_warn "Plugin \"${plugin_id}\" is already installed. Skipping."
      ((skip_count++))
      ;;
    *)
      log_error "Failed to install \"${plugin_id}\"."
      ((fail_count++))
      ;;
  esac
done

log_step "PyCharm plugin setup complete."
log_ok "Installed: ${install_count}"
log_warn "Skipped (already installed): ${skip_count}"
log_warn "Duplicates ignored: ${duplicate_count}"
log_warn "Invalid ignored: ${invalid_count}"
if (( fail_count > 0 )); then
  log_error "Failed: ${fail_count}"
else
  log_ok "Failed: ${fail_count}"
fi

if (( fail_count > 0 || invalid_count > 0 )); then
  log_error "PyCharm setup completed with issues."
  exit 1
fi

log_ok "All done."
