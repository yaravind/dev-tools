#!/bin/zsh

source "${0:A:h}/colors.sh"

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
PYCHARM_PLUGIN_FILE="$(cd "${SCRIPT_DIR}/../../config" && pwd -P)/pycharm.txt"
MODE="professional"

print_usage() {
  printf 'Usage: %s [--professional|--community]\n' "${SCRIPT_NAME}"
  printf '  --professional   Install community and professional plugin entries (default).\n'
  printf '  --community      Install only community entries and skip professional entries with warnings.\n'
}

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

print_mode_options() {
  log_step "Select PyCharm plugin installation mode"
  log_info "1) --professional (default): install community and professional plugin entries"
  log_info "2) --community            : install only community entries and skip professional entries"
}

trim() {
  local value="$1"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

prompt_for_mode() {
  if [[ ! -t 0 ]]; then
    log_warn "No interactive terminal detected; using mode: --${MODE}"
    return 0
  fi

  local choice
  while true; do
    printf 'Enter mode [1/2] (default: --%s): ' "${MODE}"
    IFS= read -r choice
    choice="$(trim "$choice")"

    case "$choice" in
      ''|1|professional|--professional)
        MODE="professional"
        return 0
        ;;
      2|community|--community)
        MODE="community"
        return 0
        ;;
      *)
        log_warn "Invalid selection '${choice}'. Enter 1 or 2."
        ;;
    esac
  done
}

resolve_pycharm_cli() {
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

  local pycharm_cmd
  for pycharm_cmd in charm pycharm; do
    if ! command_exists "$pycharm_cmd"; then
      continue
    fi

    local pycharm_path
    pycharm_path="$(command -v "$pycharm_cmd")"
    if [[ -f "$pycharm_path" ]] && grep -Eq '^[[:space:]]*open[[:space:]]+-na[[:space:]]+' "$pycharm_path"; then
      local app_name
      app_name="$(sed -n 's/.*open -na "\([^"]*\)".*/\1/p' "$pycharm_path" | head -n 1)"
      if [[ -n "$app_name" ]]; then
        for candidate in "/Applications/${app_name}/Contents/MacOS/pycharm" "${HOME}/Applications/${app_name}/Contents/MacOS/pycharm"; do
          if [[ -x "$candidate" ]]; then
            PYCHARM_CLI=("$candidate")
            return 0
          fi
        done
      fi

      log_error "The '${pycharm_cmd}' launcher points to macOS 'open -na', which does not reliably report installPlugins success."
      log_error "Use PyCharm's native binary or install PyCharm in /Applications so this script can resolve it."
      return 1
    fi

    PYCHARM_CLI=("$pycharm_path")
    return 0
  done

  return 1
}

is_pycharm_running() {
  pgrep -f "PyCharm" >/dev/null 2>&1
}

install_plugin() {
  local plugin_id="$1"
  local raw_output
  local install_exit_code

  raw_output="$("${PYCHARM_CLI[@]}" installPlugins "$plugin_id" 2>&1)"
  install_exit_code=$?

  # Filter out PyCharm/JVM internal noise; display only actionable lines.
  # Suppressed: timestamp-prefixed WARN logs, Java stack trace frames,
  # exception class lines, JVM deprecation warnings, and blank lines.
  local filtered_output
  filtered_output="$(printf '%s\n' "$raw_output" | grep -Ev \
    '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}|^[[:space:]]+at |^(java|kotlin)\.|^Caused by:|^WARNING:|^[[:space:]]*$')"
  if [[ -n "$filtered_output" ]]; then
    printf '%s\n' "$filtered_output"
  fi

  if [[ "$raw_output" == *"already installed"* ]]; then
    return 2
  fi

  # Plugin ID not found in marketplace repository
  if [[ "$raw_output" == *"unknown plugins"* ]]; then
    return 3
  fi

  if [[ $install_exit_code -eq 0 ]]; then
    return 0
  fi

  return 1
}

for arg in "$@"; do
  case "$arg" in
    --professional)
      MODE="professional"
      ;;
    --community)
      MODE="community"
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      log_error "Unknown argument: ${arg}"
      print_usage
      exit 1
      ;;
  esac
done

print_mode_options
prompt_for_mode
log_info "Selected mode: --${MODE}"

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
edition_skip_count=0
seen_plugins=$'\n'

while IFS= read -r plugin_id || [[ -n "$plugin_id" ]]; do
  plugin_id="$(trim "$plugin_id")"

  if [[ -z "$plugin_id" || "$plugin_id" == \#* ]]; then
    continue
  fi

  plugin_edition="community"
  if [[ "$plugin_id" == community:* ]]; then
    plugin_edition="community"
    plugin_id="${plugin_id#community:}"
    plugin_id="$(trim "$plugin_id")"
  elif [[ "$plugin_id" == professional:* ]]; then
    plugin_edition="professional"
    plugin_id="${plugin_id#professional:}"
    plugin_id="$(trim "$plugin_id")"
  fi

  if [[ "$plugin_edition" == "professional" && "$MODE" == "community" ]]; then
    log_warn "Skipping professional-only plugin \"${plugin_id}\" in --community mode."
    ((edition_skip_count++))
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
unknown_count=0

total_plugins="${#plugins_to_install[@]}"
plugin_index=0

for plugin_id in "${plugins_to_install[@]}"; do
  ((plugin_index++))
  log_step "Installing plugin [${plugin_index}/${total_plugins}]: ${plugin_id}"
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
    3)
      log_warn "Plugin \"${plugin_id}\" not found in Marketplace (unknown plugin ID). Check the ID or remove from config."
      ((unknown_count++))
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
log_warn "Skipped by edition mode: ${edition_skip_count}"
log_warn "Duplicates ignored: ${duplicate_count}"
log_warn "Invalid ignored: ${invalid_count}"
if (( unknown_count > 0 )); then
  log_warn "Unknown plugin IDs (not in Marketplace): ${unknown_count}"
else
  log_ok "Unknown plugin IDs: ${unknown_count}"
fi
if (( fail_count > 0 )); then
  log_error "Failed: ${fail_count}"
else
  log_ok "Failed: ${fail_count}"
fi

if (( fail_count > 0 || invalid_count > 0 || unknown_count > 0 )); then
  log_error "PyCharm setup completed with issues."
  exit 1
fi

log_ok "PyCharm setup completed successfully."
