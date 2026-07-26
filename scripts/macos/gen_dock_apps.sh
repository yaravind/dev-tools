#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

SCRIPT_DIR="${0:A:h}"
APPLIST_FILE="${SCRIPT_DIR}/../../config/dock_apps.txt"
START_TIME=$SECONDS

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

format_duration() {
  local total_seconds="$1"
  printf '%02dh:%02dm:%02ds' \
    $((total_seconds / 3600)) \
    $(((total_seconds % 3600) / 60)) \
    $((total_seconds % 60))
}

ebk_log_phase "DISCOVER Capture current Dock app list"

if ! command_exists dockutil; then
  ebk_log_error "dockutil is not installed. Install it first, then rerun this script."
  exit 1
fi

if ! dockutil --list | awk -F '\t' '
  $2 ~ /^file:\/\/\/.*\.app\/$/ {
    app_path = $2
    sub(/^file:\/\//, "", app_path)
    sub(/\/$/, "", app_path)
    gsub(/%20/, " ", app_path)
    print app_path
  }
' > "$APPLIST_FILE"; then
  ebk_log_error "Failed to generate ${APPLIST_FILE} from the current Dock."
  exit 1
fi

APP_COUNT=$(wc -l < "$APPLIST_FILE" | tr -d ' ')
ebk_log_ok "Generated ${APPLIST_FILE}."

ebk_log_phase "SUMMARY"
ebk_log_ok "Status: completed"
ebk_log_ok "Dock apps captured: ${APP_COUNT}"
ebk_log_ok "Output: ${APPLIST_FILE}"
ebk_log_ok "Duration: $(format_duration "$((SECONDS - START_TIME))")"
ebk_log_info "Next step: run scripts/macos/dock_setup.sh"