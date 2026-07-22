#!/bin/zsh

source "${0:A:h}/colors.sh"

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
INTELLIJ_PLUGIN_FILE="$(cd "${SCRIPT_DIR}/../../config" && pwd -P)/intellij.txt"
MODE="ultimate"
THEME_HEADER=$'\033[38;5;63m'
THEME_SUCCESS=$'\033[38;5;36m'
THEME_WARN=$'\033[38;5;136m'
THEME_BODY=$'\033[38;5;238m'

print_usage() {
  printf 'Usage: %s [--ultimate|--community]\n' "${SCRIPT_NAME}"
  printf '  --ultimate   Install community and ultimate plugin entries (default).\n'
  printf '  --community  Install only community entries and skip ultimate entries with warnings.\n'
}

print_banner() {
  printf '\n'
  printf "${THEME_HEADER}+------------------------------------------------------------------------------+${RESET}\n"
  printf "${THEME_HEADER}| ${THEME_BODY}%-76s ${THEME_HEADER}|${RESET}\n" "dev-tools"
  printf "${THEME_HEADER}| ${THEME_BODY}%-76s ${THEME_HEADER}|${RESET}\n" "https://github.com/yaravind/dev-tools"
  printf "${THEME_HEADER}+------------------------------------------------------------------------------+${RESET}\n"
  printf '\n'
}

print_mode_options() {
  log_step "Select IntelliJ plugin installation mode"
  log_info "1) --ultimate  (default): install community and ultimate plugin entries"
  log_info "2) --community          : install only community entries and skip ultimate entries"
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
      ''|1|ultimate|--ultimate)
        MODE="ultimate"
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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

log_step() {
  printf "${THEME_HEADER}===> %s${RESET}\n" "$1"
}

log_info() {
  printf "${THEME_BODY}===> %s${RESET}\n" "$1"
}

log_ok() {
  printf "${THEME_SUCCESS}===> %s${RESET}\n" "$1"
}

log_warn() {
  printf "${THEME_WARN}===> WARN: %s${RESET}\n" "$1"
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

resolve_idea_cli() {
  local candidate
  local candidates=(
    "/Applications/IntelliJ IDEA.app/Contents/MacOS/idea"
    "/Applications/IntelliJ IDEA CE.app/Contents/MacOS/idea"
    "${HOME}/Applications/IntelliJ IDEA.app/Contents/MacOS/idea"
    "${HOME}/Applications/IntelliJ IDEA CE.app/Contents/MacOS/idea"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      IDEA_CLI=("$candidate")
      return 0
    fi
  done

  if command_exists idea; then
    local idea_cmd
    idea_cmd="$(command -v idea)"

    if [[ -f "$idea_cmd" ]] && grep -Eq '^[[:space:]]*open[[:space:]]+-na[[:space:]]+' "$idea_cmd"; then
      local app_name
      app_name="$(sed -n 's/.*open -na "\([^"]*\)".*/\1/p' "$idea_cmd" | head -n 1)"
      if [[ -n "$app_name" ]]; then
        for candidate in "/Applications/${app_name}/Contents/MacOS/idea" "${HOME}/Applications/${app_name}/Contents/MacOS/idea"; do
          if [[ -x "$candidate" ]]; then
            IDEA_CLI=("$candidate")
            return 0
          fi
        done
      fi

      log_error "The 'idea' launcher points to macOS 'open -na', which does not reliably report installPlugins success."
      log_error "Use IntelliJ's native binary or install IntelliJ in /Applications so this script can resolve it."
      return 1
    fi

    IDEA_CLI=("$idea_cmd")
    return 0
  fi

  return 1
}

is_intellij_running() {
  pgrep -f "IntelliJ IDEA" >/dev/null 2>&1
}

last_missing_dependencies=()
typeset -A last_dependency_parent
last_raw_output=""

install_plugin() {
  local plugin_id="$1"
  local raw_output
  local install_exit_code

  last_missing_dependencies=()
  last_dependency_parent=()
  raw_output="$("${IDEA_CLI[@]}" installPlugins "$plugin_id" 2>&1)"
  install_exit_code=$?
  last_raw_output="$raw_output"

  local filtered_output
  filtered_output="$(printf '%s\n' "$raw_output" | grep -Ev \
    '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}|^[[:space:]]*plugin repositories: \[null\]$|^[[:space:]]+at |^(java|kotlin)\.|^Caused by:|^WARNING:|^[[:space:]]*$')"
  if [[ -n "$filtered_output" ]]; then
    printf '%s\n' "$filtered_output"
  fi

  while IFS='|' read -r dep_id dep_parent; do
    dep_id="$(trim "$dep_id")"
    dep_parent="$(trim "$dep_parent")"
    if [[ -n "$dep_id" ]]; then
      last_missing_dependencies+=("$dep_id")
      if [[ -n "$dep_parent" ]]; then
        last_dependency_parent[$dep_id]="$dep_parent"
      fi
    fi
  done < <(printf '%s\n' "$raw_output" | sed -n "s/.*(\([^)]*\)).*dependency on '\([^']*\)'.*/\2|\1/p" | sort -u)

  while IFS= read -r dep_id; do
    dep_id="$(trim "$dep_id")"
    if [[ -n "$dep_id" && -z "${last_dependency_parent[$dep_id]:-}" ]]; then
      last_missing_dependencies+=("$dep_id")
    fi
  done < <(printf '%s\n' "$raw_output" | sed -n "s/.*dependency on '\([^']*\)'.*/\1/p" | sort -u)

  if [[ "$raw_output" == *"already installed"* ]]; then
    return 2
  fi

  if [[ "$raw_output" == *"unknown plugins"* ]]; then
    return 3
  fi

  if [[ $install_exit_code -eq 0 ]]; then
    return 0
  fi

  return 1
}

print_structured_report() {
  local status_label="$1"
  local script_label="IntelliJ Plugin Setup (macOS)"
  local total_attempted="$2"
  local net_new_count="$3"

  local status_icon
  local status_color
  if [[ "$status_label" == "SUCCESS" ]]; then
    status_icon="✔"
    status_color="${THEME_SUCCESS}"
  else
    status_icon="⚠"
    status_color="${THEME_WARN}"
  fi

  printf "\n${THEME_HEADER}Final Status Report${RESET}\n"
  printf "${THEME_HEADER}──────────────────────────────────────────────────────────────────────────────${RESET}\n"
  printf '  %-24s %s\n' "Script" "$script_label"
  printf '  %-24s %s\n' "Mode" "--${MODE}"
  printf '  %-24s %s\n' "Config" "$INTELLIJ_PLUGIN_FILE"
  printf '  %-24s %s\n' "Launcher" "${IDEA_CLI[1]}"
  printf "  %-24s ${status_color}%s %s${RESET}\n" "Status" "$status_icon" "$status_label"
  printf "${THEME_HEADER}──────────────────────────────────────────────────────────────────────────────${RESET}\n"
  printf '  %-24s %s\n' "Requested" "$initial_requested_count"
  printf '  %-24s %s\n' "Attempted" "$total_attempted"
  printf '  %-24s %s\n' "Installed (net new)" "$install_count"
  printf '  %-24s %s\n' "Already installed" "$skip_count"
  printf '  %-24s %s\n' "Auto dependencies queued" "$auto_dependency_count"
  printf '  %-24s %s\n' "Unknown IDs" "$unknown_count"
  printf '  %-24s %s\n' "Failed installs" "$fail_count"
  printf '  %-24s %s\n' "Edition skips" "$edition_skip_count"
  printf '  %-24s %s\n' "Duplicates ignored" "$duplicate_count"
  printf '  %-24s %s\n' "Invalid entries ignored" "$invalid_count"
  printf "${THEME_HEADER}──────────────────────────────────────────────────────────────────────────────${RESET}\n"

  printf "${THEME_HEADER}Net New Plugins Installed${RESET}\n"
  if (( net_new_count == 0 )); then
    printf '  %s\n' "No net-new plugins were installed in this run."
  else
    local p
    for p in "${net_new_plugins[@]}"; do
      printf "  ${THEME_SUCCESS}• %s${RESET}\n" "$p"
    done
  fi

  printf "\n${THEME_HEADER}Next Steps${RESET}\n"
  if (( ${#dependency_order[@]} == 0 )); then
    printf '  %s\n' "No missing dependencies were detected."
  else
    printf "${THEME_HEADER}Suggested dependency entries to add to config/intellij.txt${RESET}\n"
    printf '| %-40s | %-34s | %-40s |\n' "Plugin ID" "Required By" "Suggested Entry"
    printf '|-%-40s-|-%-34s-|-%-40s-|\n' "----------------------------------------" "----------------------------------" "----------------------------------------"
    local dep_id parent_id suggestion
    for dep_id in "${dependency_order[@]}"; do
      parent_id="${dependency_parent[$dep_id]}"
      suggestion="community:${dep_id}"
      printf '| %-40s | %-34s | %-40s |\n' "$dep_id" "$parent_id" "$suggestion"
    done
    printf '  %s\n' "Review and add the suggested entries if you want deterministic future installs."
  fi
}

for arg in "$@"; do
  case "$arg" in
    --ultimate)
      MODE="ultimate"
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

print_banner
print_mode_options
prompt_for_mode
log_info "Selected mode: --${MODE}"

if [[ ! -f "$INTELLIJ_PLUGIN_FILE" ]]; then
  log_error "${INTELLIJ_PLUGIN_FILE} not found. Please create it with IntelliJ plugin IDs."
  exit 1
fi

if ! resolve_idea_cli; then
  log_error "IntelliJ CLI not found. Add 'idea' to PATH (Tools > Create Command-line Launcher) or install IntelliJ IDEA in /Applications."
  exit 1
fi

if is_intellij_running; then
  log_error "IntelliJ IDEA appears to be running. Quit IntelliJ IDEA, then re-run this script."
  exit 1
fi

log_step "Reading IntelliJ plugin IDs from ${INTELLIJ_PLUGIN_FILE}"

plugins_to_install=()
net_new_plugins=()
typeset -A dependency_parent
dependency_order=()
duplicate_count=0
invalid_count=0
edition_skip_count=0
auto_dependency_count=0
seen_plugins=$'\n'

while IFS= read -r plugin_id || [[ -n "$plugin_id" ]]; do
  plugin_id="$(trim "$plugin_id")"

  if [[ -z "$plugin_id" || "$plugin_id" == \#* ]]; then
    continue
  fi

  plugin_edition="community"
  if [[ "$plugin_id" == community:* ]]; then
    plugin_id="${plugin_id#community:}"
    plugin_id="$(trim "$plugin_id")"
  elif [[ "$plugin_id" == ultimate:* ]]; then
    plugin_edition="ultimate"
    plugin_id="${plugin_id#ultimate:}"
    plugin_id="$(trim "$plugin_id")"
  fi

  if [[ "$plugin_edition" == "ultimate" && "$MODE" == "community" ]]; then
    log_warn "Skipping ultimate-only plugin \"${plugin_id}\" in --community mode."
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
done < "$INTELLIJ_PLUGIN_FILE"

if (( ${#plugins_to_install[@]} == 0 )); then
  log_error "No valid plugin IDs found in ${INTELLIJ_PLUGIN_FILE}."
  exit 1
fi

initial_requested_count="${#plugins_to_install[@]}"

log_step "Using IntelliJ launcher: ${IDEA_CLI[1]}"
log_info "Total plugin IDs queued: ${#plugins_to_install[@]}"

install_count=0
skip_count=0
fail_count=0
unknown_count=0

plugin_index=1
while (( plugin_index <= ${#plugins_to_install[@]} )); do
  plugin_id="${plugins_to_install[$plugin_index]}"
  log_step "Installing plugin [${plugin_index}/${#plugins_to_install[@]}]: ${plugin_id}"
  install_plugin "$plugin_id"
  install_status=$?

  if (( ${#last_missing_dependencies[@]} > 0 )); then
    for dep_id in "${last_missing_dependencies[@]}"; do
      if [[ -z "$dep_id" ]]; then
        continue
      fi

      local required_by="${last_dependency_parent[$dep_id]:-$plugin_id}"
      if [[ -z "${dependency_parent[$dep_id]:-}" ]]; then
        dependency_parent[$dep_id]="$required_by"
        dependency_order+=("$dep_id")
      fi

      if [[ "$seen_plugins" != *$'\n'"$dep_id"$'\n'* ]]; then
        seen_plugins+="${dep_id}"$'\n'
        plugins_to_install+=("$dep_id")
        ((auto_dependency_count++))
        log_info "Queued missing dependency plugin: ${dep_id} (required by ${required_by})"
      fi
    done
  fi

  case "$install_status" in
    0)
      log_ok "Installed \"${plugin_id}\"."
      ((install_count++))
      net_new_plugins+=("$plugin_id")
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

  ((plugin_index++))
done

overall_status="SUCCESS"
if (( fail_count > 0 || invalid_count > 0 || unknown_count > 0 )); then
  overall_status="COMPLETED WITH ISSUES"
fi

attempted_total=$((plugin_index - 1))
print_structured_report "$overall_status" "$attempted_total" "${#net_new_plugins[@]}"

if [[ "$overall_status" != "SUCCESS" ]]; then
  exit 1
fi

log_ok "IntelliJ setup completed successfully."
