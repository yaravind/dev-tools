#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:A:t}"
CONFIG_FILE="${SCRIPT_DIR}/../../config/zsh_plugins.txt"
PLUGIN_LIST_FILE="${HOME}/.zsh_plugins.txt"
PLUGIN_BUNDLE_FILE="${HOME}/.zsh_plugins.zsh"
ZSHRC_FILE="${HOME}/.zshrc"
SOURCE_LINE='source "$HOME/.zsh_plugins.zsh"'
ANTIDOTE_SOURCE_FILE=""
PLUGIN_COUNT=0
SCRIPT_START_SECONDS=$SECONDS

command_exists() { command -v "$1" >/dev/null 2>&1; }

print_usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME}

Sets up zsh plugins using antidote from:
  ${CONFIG_FILE}
EOF
}

trim() {
  local value="$1"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

resolve_antidote_source_file() {
  local candidate

  if command_exists brew; then
    candidate="$(brew --prefix antidote 2>/dev/null)/share/antidote/antidote.zsh"
    if [[ -f "$candidate" ]]; then
      ANTIDOTE_SOURCE_FILE="$candidate"
      return 0
    fi
  fi

  candidate="${HOME}/.antidote/antidote.zsh"
  if [[ -f "$candidate" ]]; then
    ANTIDOTE_SOURCE_FILE="$candidate"
    return 0
  fi

  return 1
}

ensure_antidote() {
  if ! resolve_antidote_source_file; then
    ebk_log_error "antidote is not installed."
    ebk_log_error "Run scripts/macos/setup_env.sh first (or install with: brew install antidote)."
    return 1
  fi

  # Homebrew installs antidote as a sourceable zsh script, not always as a PATH binary.
  if ! source "$ANTIDOTE_SOURCE_FILE"; then
    ebk_log_error "Failed to source antidote from ${ANTIDOTE_SOURCE_FILE}."
    return 1
  fi

  if ! typeset -f antidote >/dev/null 2>&1; then
    ebk_log_error "antidote function is unavailable after sourcing ${ANTIDOTE_SOURCE_FILE}."
    return 1
  fi

  ebk_log_ok "antidote loaded from ${ANTIDOTE_SOURCE_FILE}"
}

ensure_config_file() {
  if [[ -f "$CONFIG_FILE" ]]; then
    return 0
  fi

  ebk_log_error "Config file not found: ${CONFIG_FILE}"
  return 1
}

validate_config_entries() {
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
  done < "$CONFIG_FILE"

  if (( PLUGIN_COUNT == 0 )); then
    ebk_log_error "No plugin entries found in ${CONFIG_FILE}."
    return 1
  fi

  ebk_log_info "Plugins configured: ${PLUGIN_COUNT}"
}

build_antidote_bundle() {
  ebk_log_phase "Generating plugin files"

  if ! cp "$CONFIG_FILE" "$PLUGIN_LIST_FILE"; then
    ebk_log_error "Failed to write ${PLUGIN_LIST_FILE}."
    return 1
  fi

  ebk_log_info "Building ${PLUGIN_BUNDLE_FILE} via antidote bundle"
  if ! antidote bundle < "$PLUGIN_LIST_FILE" > "$PLUGIN_BUNDLE_FILE"; then
    ebk_log_error "antidote failed to build ${PLUGIN_BUNDLE_FILE}."
    return 1
  fi

  if [[ ! -s "$PLUGIN_BUNDLE_FILE" ]]; then
    ebk_log_error "Generated plugin bundle is empty: ${PLUGIN_BUNDLE_FILE}"
    return 1
  fi

  ebk_log_ok "Generated ${PLUGIN_BUNDLE_FILE}"
}

ensure_source_line_in_zshrc() {
  if ! touch "$ZSHRC_FILE"; then
    ebk_log_error "Failed to create or update ${ZSHRC_FILE}."
    return 1
  fi

  if grep -qxF "$SOURCE_LINE" "$ZSHRC_FILE" 2>/dev/null; then
    ebk_log_info "~/.zshrc already sources ${PLUGIN_BUNDLE_FILE}."
    return 0
  fi

  {
    printf '\n# antidote: generated plugin bundle\n'
    printf '%s\n' "$SOURCE_LINE"
  } >> "$ZSHRC_FILE" || {
    ebk_log_error "Failed to update ${ZSHRC_FILE}."
    return 1
  }

  ebk_log_ok "Updated ~/.zshrc to source ${PLUGIN_BUNDLE_FILE}"
}

print_summary() {
  local elapsed_seconds=$((SECONDS - SCRIPT_START_SECONDS))
  ebk_log_phase "Summary"
  ebk_log_ok "Status: completed"
  ebk_log_ok "Plugins configured: ${PLUGIN_COUNT}"
  ebk_log_ok "Plugin list file: ${PLUGIN_LIST_FILE}"
  ebk_log_ok "Plugin bundle file: ${PLUGIN_BUNDLE_FILE}"
  ebk_log_ok "Duration: ${elapsed_seconds}s"
}

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      ebk_log_error "Unknown argument: ${arg}"
      print_usage
      exit 1
      ;;
  esac
done

ebk_log_phase "Starting zsh plugin setup"
ensure_antidote || exit 1
ensure_config_file || exit 1
validate_config_entries || exit 1
build_antidote_bundle || exit 1
ensure_source_line_in_zshrc || exit 1
print_summary

ebk_log_info "Restart your shell or run: source ~/.zshrc"
