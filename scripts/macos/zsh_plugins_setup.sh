#!/bin/zsh

source "${0:A:h}/colors.sh"

INFO="${CYAN}"
SUCCESS="${GREEN}"
WARN="${YELLOW}"
ERROR="${RED}"
SECTION="${BMAGENTA}"

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:A:t}"
CONFIG_FILE="${SCRIPT_DIR}/../../config/zsh_plugins.txt"
PLUGIN_LIST_FILE="${HOME}/.zsh_plugins.txt"
PLUGIN_BUNDLE_FILE="${HOME}/.zsh_plugins.zsh"
ZSHRC_FILE="${HOME}/.zshrc"
SOURCE_LINE='source "$HOME/.zsh_plugins.zsh"'
ANTIDOTE_SOURCE_FILE=""

command_exists() { command -v "$1" >/dev/null 2>&1; }

print_usage() {
  echo -e "${INFO}Usage: ${SCRIPT_NAME}${RESET}"
}

log_step() {
  echo -e "${SECTION}===> $1${RESET}"
}

log_info() {
  echo -e "${INFO}===> $1${RESET}"
}

log_ok() {
  echo -e "${SUCCESS}===> $1${RESET}"
}

log_warn() {
  echo -e "${WARN}===> WARN: $1${RESET}"
}

log_error() {
  echo -e "${ERROR}ERROR: $1${RESET}" >&2
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
    log_error "antidote is not installed."
    log_error "Run scripts/macos/setup_env.sh first (or install with: brew install antidote)."
    return 1
  fi

  # Homebrew installs antidote as a sourceable zsh script, not always as a PATH binary.
  if ! source "$ANTIDOTE_SOURCE_FILE"; then
    log_error "Failed to source antidote from ${ANTIDOTE_SOURCE_FILE}."
    return 1
  fi

  if ! typeset -f antidote >/dev/null 2>&1; then
    log_error "antidote function is unavailable after sourcing ${ANTIDOTE_SOURCE_FILE}."
    return 1
  fi

  log_info "Using antidote source: ${ANTIDOTE_SOURCE_FILE}"
}

ensure_config_file() {
  if [[ -f "$CONFIG_FILE" ]]; then
    return 0
  fi

  log_error "Config file not found: ${CONFIG_FILE}"
  return 1
}

validate_config_entries() {
  local line
  local plugin_count=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    plugin_count=$((plugin_count + 1))
  done < "$CONFIG_FILE"

  if (( plugin_count == 0 )); then
    log_error "No plugin entries found in ${CONFIG_FILE}."
    return 1
  fi

  log_info "Plugins configured: ${plugin_count}"
}

build_antidote_bundle() {
  log_step "Generating plugin files from ${CONFIG_FILE}"

  cp "$CONFIG_FILE" "$PLUGIN_LIST_FILE" || return 1
  if ! antidote bundle < "$PLUGIN_LIST_FILE" > "$PLUGIN_BUNDLE_FILE"; then
    log_error "antidote failed to build ${PLUGIN_BUNDLE_FILE}."
    return 1
  fi

  if [[ ! -s "$PLUGIN_BUNDLE_FILE" ]]; then
    log_error "Generated plugin bundle is empty: ${PLUGIN_BUNDLE_FILE}"
    return 1
  fi

  log_ok "Generated ${PLUGIN_BUNDLE_FILE}"
}

ensure_source_line_in_zshrc() {
  touch "$ZSHRC_FILE"

  if grep -qxF "$SOURCE_LINE" "$ZSHRC_FILE" 2>/dev/null; then
    log_info "~/.zshrc already sources ${PLUGIN_BUNDLE_FILE}."
    return 0
  fi

  {
    printf '\n# antidote: generated plugin bundle\n'
    printf '%s\n' "$SOURCE_LINE"
  } >> "$ZSHRC_FILE" || return 1

  log_ok "Updated ~/.zshrc to source ${PLUGIN_BUNDLE_FILE}"
}

for arg in "$@"; do
  case "$arg" in
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

log_step "Starting zsh plugin setup"
ensure_antidote || exit 1
ensure_config_file || exit 1
validate_config_entries || exit 1
build_antidote_bundle || exit 1
ensure_source_line_in_zshrc || exit 1

log_ok "Zsh plugin setup complete. Restart your shell or run: source ~/.zshrc"
