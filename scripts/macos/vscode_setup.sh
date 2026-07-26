#!/bin/bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/branding_bash.sh"
ebk_print_banner "$(basename "${BASH_SOURCE[0]}")"
BLUE="$EBK_INFO_COLOR"
NC="$EBK_RESET"

VSCODE_EXT_FILE="$(cd "${SCRIPT_DIR}/../../config" && pwd -P)/vscode.txt"
VSCODE_SETTINGS_FILE="$(cd "${SCRIPT_DIR}/../../config" && pwd -P)/vscode_settings.json"
VSCODE_USER_SETTINGS_FILE="${HOME}/Library/Application Support/Code/User/settings.json"
SCRIPT_START_SECONDS=$SECONDS

LOG_HEADER="$EBK_PHASE_COLOR"
LOG_SUCCESS="$EBK_OK_COLOR"
LOG_WARN="$EBK_WARN_COLOR"

log_phase() {
  ebk_log_phase "$1"
  [[ -n "${2:-}" ]] && ebk_log_info "$2"
}

format_duration() {
  local total_seconds="$1"
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  if ((hours > 0)); then
    printf '%dh %dm %ds' "$hours" "$minutes" "$seconds"
  elif ((minutes > 0)); then
    printf '%dm %ds' "$minutes" "$seconds"
  else
    printf '%ds' "$seconds"
  fi
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

trim() {
  local value="$1"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

run_cmd() {
  printf '%s$' "$BLUE"
  printf ' %q' "$@"
  printf '%s\n' "$NC"
  "$@"
}

is_installed() {
  local wanted
  local installed
  wanted="$(lowercase "$1")"

  while IFS= read -r installed; do
    if [[ "$(lowercase "$installed")" == "$wanted" ]]; then
      return 0
    fi
  done < <(code --list-extensions)

  return 1
}

apply_managed_settings() {
  local managed_settings_file="$1"
  local user_settings_file="$2"
  local user_settings_dir

  if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 not found. Cannot merge VSCode settings."
    return 1
  fi

  if [[ ! -f "$managed_settings_file" ]]; then
    log_error "${managed_settings_file} not found. Please create it with VSCode settings."
    return 1
  fi

  user_settings_dir="$(dirname "$user_settings_file")"
  if [[ ! -d "$user_settings_dir" ]]; then
    if ! run_cmd mkdir -p "$user_settings_dir"; then
      log_error "Failed to create VSCode settings directory \"${user_settings_dir}\"."
      return 1
    fi
  fi

  if [[ ! -f "$user_settings_file" ]]; then
    printf '%s$ printf %s > %q%s\n' "$BLUE" '"{}\\n"' "$user_settings_file" "$NC"
    if ! printf '{}\n' > "$user_settings_file"; then
      log_error "Failed to initialize VSCode settings file \"${user_settings_file}\"."
      return 1
    fi
  fi

  if ! EBK_INFO_COLOR="$EBK_INFO_COLOR" EBK_RESET="$EBK_RESET" run_cmd python3 - "$managed_settings_file" "$user_settings_file" <<'PY'; then
import json
import os
import sys

managed_path = sys.argv[1]
user_path = sys.argv[2]
info_color = os.environ.get("EBK_INFO_COLOR", "")
reset_color = os.environ.get("EBK_RESET", "")

def strip_jsonc_comments(content: str) -> str:
    result = []
    in_string = False
    in_line_comment = False
    in_block_comment = False
    escaped = False
    i = 0
    while i < len(content):
        ch = content[i]
        nxt = content[i + 1] if i + 1 < len(content) else ""

        if in_line_comment:
            if ch in "\r\n":
                in_line_comment = False
                result.append(ch)
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue

        if in_string:
            result.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue

        if ch == '"':
            in_string = True
            result.append(ch)
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue

        result.append(ch)
        i += 1

    return "".join(result)

def strip_trailing_commas(content: str) -> str:
    result = []
    in_string = False
    escaped = False
    i = 0
    while i < len(content):
        ch = content[i]
        if in_string:
            result.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue

        if ch == '"':
            in_string = True
            result.append(ch)
            i += 1
            continue

        if ch == ",":
            j = i + 1
            while j < len(content) and content[j] in " \t\r\n":
                j += 1
            if j < len(content) and content[j] in "}]":
                i += 1
                continue

        result.append(ch)
        i += 1

    return "".join(result)

def load_jsonc_object(path: str):
    with open(path, encoding="utf-8") as raw_file:
        raw_content = raw_file.read()
    sanitized = strip_jsonc_comments(raw_content)
    sanitized = strip_trailing_commas(sanitized)
    parsed = json.loads(sanitized)
    if not isinstance(parsed, dict):
        raise SystemExit(f"ERROR: {path} must contain a JSON object.")
    return parsed

managed = load_jsonc_object(managed_path)

for key in sorted(managed):
    value = json.dumps(managed[key], ensure_ascii=True)
    print(f"{info_color}ℹ INFO  {reset_color}Managed setting: {key} = {value}{reset_color}")

existing = load_jsonc_object(user_path)

merged = existing.copy()
merged.update(managed)

with open(user_path, "w", encoding="utf-8") as user_file:
    json.dump(merged, user_file, indent=2)
    user_file.write("\n")
PY
    log_error "Failed to merge VSCode settings. Ensure both settings files contain valid JSON objects."
    return 1
  fi

  return 0
}

print_structured_report() {
  local status_label="$1"
  local status_icon
  local status_color

  if [[ "$status_label" == "SUCCESS" ]]; then
    status_icon="✔"
    status_color="$LOG_SUCCESS"
  else
    status_icon="⚠"
    status_color="$LOG_WARN"
  fi

  printf '\n%sFinal Status Report%s\n' "$LOG_HEADER" "$NC"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$LOG_HEADER" "$NC"
  printf '  %-24s %s\n' "Script" "VSCode Setup (macOS)"
  printf '  %-24s %s\n' "Config" "$VSCODE_EXT_FILE"
  printf '  %-24s %s\n' "Settings file" "$VSCODE_SETTINGS_FILE"
  printf "  %-24s ${status_color}%s %s${NC}\n" "Status" "$status_icon" "$status_label"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$LOG_HEADER" "$NC"
  printf '  %-24s %d\n' "Requested" "$initial_requested_count"
  printf '  %-24s %d\n' "Attempted" "$initial_requested_count"
  printf '  %-24s %d\n' "Installed (net new)" "$install_count"
  printf '  %-24s %d\n' "Already installed" "$skip_count"
  printf '  %-24s %d\n' "Duplicates ignored" "$duplicate_count"
  printf '  %-24s %d\n' "Invalid entries ignored" "$invalid_count"
  printf '  %-24s %d\n' "Failed installs" "$fail_count"
  printf '  %-24s %d\n' "Settings merge failures" "$settings_fail_count"
  printf '  %-24s %s\n' "Duration" "$(format_duration $((SECONDS - SCRIPT_START_SECONDS)))"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$LOG_HEADER" "$NC"

  printf '%sNet New Extensions Installed%s\n' "$LOG_HEADER" "$NC"
  if (( ${#net_new_extensions[@]} == 0 )); then
    printf '  %s\n' "No net-new extensions were installed in this run."
  else
    local ext
    for ext in "${net_new_extensions[@]}"; do
      printf '  %s• %s%s\n' "$LOG_SUCCESS" "$ext" "$NC"
    done
  fi

  printf '\n%sNext Steps%s\n' "$LOG_HEADER" "$NC"
  if (( fail_count > 0 || settings_fail_count > 0 || invalid_count > 0 )); then
    printf '  %s\n' "Review failed installs/setting merges and fix invalid IDs in config/vscode.txt."
  else
    printf '  %s\n' "No follow-up action required."
  fi
}

if ! command -v code >/dev/null 2>&1; then
  log_error "VSCode CLI \"code\" not found. Please install it first."
  exit 1
fi

if [[ ! -f "$VSCODE_EXT_FILE" ]]; then
  log_error "${VSCODE_EXT_FILE} not found. Please create it with extension IDs."
  exit 1
fi

if [[ ! -f "$VSCODE_SETTINGS_FILE" ]]; then
  log_error "${VSCODE_SETTINGS_FILE} not found. Please create it with VSCode settings."
  exit 1
fi

log_phase "DISCOVER" "Scanning local VSCode state and extension config"
installed_count="$(code --list-extensions | wc -l | tr -d '[:space:]')"
log_info "Installed VSCode extensions detected: ${installed_count}"
log_info "Reading extensions from ${VSCODE_EXT_FILE}"

exts_to_install=()
duplicate_count=0
invalid_count=0
seen_exts=$'\n'

while IFS= read -r ext || [[ -n "$ext" ]]; do
  ext="$(trim "$ext")"

  if [[ -z "$ext" || "$ext" == \#* ]]; then
    continue
  fi

  if [[ ! "$ext" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*\.[A-Za-z0-9][A-Za-z0-9_.-]*(@[A-Za-z0-9_.-]+)?$ ]]; then
    log_warn "Ignoring invalid extension ID \"${ext}\"."
    ((invalid_count++))
    continue
  fi

  ext="$(lowercase "$ext")"
  if [[ "$seen_exts" == *$'\n'"$ext"$'\n'* ]]; then
    log_warn "Duplicate extension \"${ext}\" in config. Ignoring duplicate entry."
    ((duplicate_count++))
    continue
  fi

  seen_exts+="$ext"$'\n'
  exts_to_install+=("$ext")
done < "$VSCODE_EXT_FILE"

initial_requested_count="${#exts_to_install[@]}"
log_info "Total extension IDs queued: ${initial_requested_count}"

install_count=0
skip_count=0
fail_count=0
settings_fail_count=0
net_new_extensions=()

log_phase "INSTALL" "Installing queued VSCode extensions"
for ext in "${exts_to_install[@]}"; do
  if is_installed "$ext"; then
    ((skip_count++))
    continue
  fi

  log_step "Installing extension: ${ext}"
  if run_cmd code --install-extension "$ext"; then
    if is_installed "$ext"; then
      log_ok "Installed \"${ext}\"."
      ((install_count++))
      net_new_extensions+=("$ext")
    else
      log_error "Command completed but \"${ext}\" was not found in the installed extension list."
      ((fail_count++))
    fi
  else
    log_error "Failed to install \"${ext}\"."
    ((fail_count++))
  fi
  sleep 0.2
done

log_phase "VERIFY" "Applying managed VSCode settings"
log_step "Applying settings from ${VSCODE_SETTINGS_FILE}"
if apply_managed_settings "$VSCODE_SETTINGS_FILE" "$VSCODE_USER_SETTINGS_FILE"; then
  log_ok "Managed VSCode settings applied to \"${VSCODE_USER_SETTINGS_FILE}\"."
else
  ((settings_fail_count++))
fi

overall_status="SUCCESS"
if ((fail_count > 0 || invalid_count > 0 || settings_fail_count > 0)); then
  overall_status="COMPLETED WITH ISSUES"
fi

log_phase "SUMMARY" "Compiling final run report"
print_structured_report "$overall_status"

if ((fail_count > 0 || invalid_count > 0 || settings_fail_count > 0)); then
  exit 1
fi

log_ok "VSCode setup completed successfully."
