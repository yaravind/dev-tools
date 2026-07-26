#!/bin/zsh

# Prepare the Homebrew prefix and shell wiring for Apple Silicon and Intel Macs.

set -e

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

SCRIPT_START_SECONDS=$SECONDS
ARCHITECTURE=""
HOMEBREW_PREFIX=""
BREW_BIN=""
SCRIPT_STATUS="SUCCESS"
WARN_COUNT=0
CHECK_COUNT=0
CHANGE_COUNT=0
SKIP_COUNT=0

print_structured_report() {
  local exit_code="$1"
  local status_icon
  local status_color
  local elapsed_seconds=$((SECONDS - SCRIPT_START_SECONDS))

  if [[ "$exit_code" -eq 0 ]]; then
    SCRIPT_STATUS="SUCCESS"
    status_icon="✔"
    status_color="$EBK_OK_COLOR"
  else
    SCRIPT_STATUS="FAILED"
    status_icon="✖"
    status_color="$EBK_ERROR_COLOR"
  fi

  printf '\n%sFinal Status Report%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
  printf '  %-24s %s\n' "Script" "pre_setup.sh (macOS)"
  printf '  %-24s %s\n' "Architecture" "${ARCHITECTURE:-unknown}"
  printf '  %-24s %s\n' "Homebrew prefix" "${HOMEBREW_PREFIX:-unknown}"
  if [[ -n "$BREW_BIN" ]]; then
    printf '  %-24s %s\n' "Homebrew binary" "$BREW_BIN"
  fi
  printf "  %-24s ${status_color}%s %s${EBK_RESET}\n" "Status" "$status_icon" "$SCRIPT_STATUS"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
  printf '  %-24s %d\n' "Checks passed" "$CHECK_COUNT"
  printf '  %-24s %d\n' "Changes applied" "$CHANGE_COUNT"
  printf '  %-24s %d\n' "Skipped actions" "$SKIP_COUNT"
  printf '  %-24s %d\n' "Warnings" "$WARN_COUNT"
  printf '  %-24s %s\n' "Duration" "$(printf '%02dh:%02dm:%02ds' $((elapsed_seconds/3600)) $(((elapsed_seconds%3600)/60)) $((elapsed_seconds%60)))"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
}

on_exit() {
  local exit_code="$1"
  print_structured_report "$exit_code"
}

on_error() {
  local exit_code="$1"
  local source_line="${funcfiletrace[1]:-unknown line}"

  ebk_log_error "Unexpected failure in pre_setup.sh near ${source_line}."
  ebk_log_error "The command exited with status ${exit_code} before it could print its own error."
  return "$exit_code"
}

trap 'on_exit $?' EXIT
trap 'on_error $?' ERR

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ebk_log_phase "DISCOVER Detect architecture and target Homebrew prefix"
ARCHITECTURE="$(uname -m)"

case "$ARCHITECTURE" in
  arm64)
    HOMEBREW_PREFIX="/opt/homebrew"
    PREPARE_PREFIX_OWNERSHIP=1
    ;;
  x86_64)
    HOMEBREW_PREFIX="/usr/local"
    PREPARE_PREFIX_OWNERSHIP=0
    ;;
  *)
    ebk_log_error "Unsupported macOS architecture: ${ARCHITECTURE}"
    exit 1
    ;;
esac

((CHECK_COUNT += 1))
ebk_log_info "Detected architecture: ${ARCHITECTURE}"
ebk_log_info "Target Homebrew prefix: ${HOMEBREW_PREFIX}"

if [[ -e "$HOMEBREW_PREFIX" && ! -d "$HOMEBREW_PREFIX" ]]; then
  ebk_log_error "${HOMEBREW_PREFIX} exists but is not a directory."
  exit 1
fi

ebk_log_phase "PREPARE Ensure Homebrew prefix is ready"
if [[ "$PREPARE_PREFIX_OWNERSHIP" -eq 1 ]]; then
  if [[ -d "$HOMEBREW_PREFIX" ]]; then
    ebk_log_info "${HOMEBREW_PREFIX} already exists."
    ((SKIP_COUNT += 1))
  else
    ebk_log_info "Creating ${HOMEBREW_PREFIX}..."
    sudo mkdir -p "$HOMEBREW_PREFIX"
    ((CHANGE_COUNT += 1))
  fi

  if [[ ! -d "$HOMEBREW_PREFIX" ]]; then
    ebk_log_error "${HOMEBREW_PREFIX} was not created successfully."
    exit 1
  fi

  if [[ "$(stat -f '%Su' "$HOMEBREW_PREFIX")" == "$USER" ]]; then
    ebk_log_info "${HOMEBREW_PREFIX} is already owned by ${USER}; skipping ownership change."
    ((SKIP_COUNT += 1))
  else
    ebk_log_info "Setting ${HOMEBREW_PREFIX} ownership to ${USER}:admin..."
    sudo chown -R "$USER":admin "$HOMEBREW_PREFIX"
    ((CHANGE_COUNT += 1))
  fi
else
  ebk_log_info "Skipping recursive ownership changes for ${HOMEBREW_PREFIX} on Intel Macs."
  ((SKIP_COUNT += 1))
fi

BREW_BIN="${HOMEBREW_PREFIX}/bin/brew"

if [[ ! -x "$BREW_BIN" ]] && command_exists brew; then
  BREW_BIN="$(command -v brew)"
  HOMEBREW_PREFIX="$("$BREW_BIN" --prefix)"
fi

ebk_log_phase "INSTALL Install or refresh Homebrew"
if [[ -x "$BREW_BIN" ]]; then
  ebk_log_info "Homebrew already installed at ${BREW_BIN}; skipping installer."
  ((SKIP_COUNT += 1))
else
  ebk_log_info 'Installing Homebrew...'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ((CHANGE_COUNT += 1))
fi

BREW_BIN="${HOMEBREW_PREFIX}/bin/brew"

if [[ ! -x "$BREW_BIN" ]] && command_exists brew; then
  BREW_BIN="$(command -v brew)"
  HOMEBREW_PREFIX="$("$BREW_BIN" --prefix)"
fi

if [[ ! -x "$BREW_BIN" ]]; then
  ebk_log_error "Unable to find brew binary under ${HOMEBREW_PREFIX}/bin or PATH."
  exit 1
fi

((CHECK_COUNT += 1))
ebk_log_info "Detected Homebrew binary: ${BREW_BIN}"
ebk_log_info "Active Homebrew prefix: ${HOMEBREW_PREFIX}"

if [[ "$PREPARE_PREFIX_OWNERSHIP" -eq 1 ]]; then
  ebk_log_phase "VERIFY Validate Homebrew ownership"
  ebk_log_info "Checking ${HOMEBREW_PREFIX} ownership..."
  ebk_log_info "Prefix details: $(ls -ld "$HOMEBREW_PREFIX")"

  if [[ "$(stat -f '%Su' "$HOMEBREW_PREFIX")" != "$USER" ]]; then
    ebk_log_error "${HOMEBREW_PREFIX} is not owned by $USER."
    exit 1
  fi

  ((CHECK_COUNT += 1))
  ebk_log_ok "Verified ${HOMEBREW_PREFIX} is owned by $USER."
fi

shellenv_line="eval \"\$(${BREW_BIN} shellenv zsh)\""

ebk_log_phase "CONFIGURE Wire Homebrew into zsh profile"
ebk_log_info 'Adding Homebrew to ~/.zprofile if needed...'
touch "$HOME/.zprofile"

if ! grep -qxF "$shellenv_line" "$HOME/.zprofile"; then
  printf '\n%s\n' "$shellenv_line" >> "$HOME/.zprofile"
  ((CHANGE_COUNT += 1))
  ebk_log_ok 'Added Homebrew shell setup to ~/.zprofile.'
else
  ((SKIP_COUNT += 1))
  ebk_log_info 'Homebrew shell setup already present in ~/.zprofile.'
fi

ebk_log_info 'Loading Homebrew into this script session...'
eval "$("$BREW_BIN" shellenv zsh)"

ebk_log_phase "VERIFY Confirm Homebrew availability"
brew_version="$(brew --version | head -n 1)"
((CHECK_COUNT += 1))
ebk_log_ok "Verified Homebrew: ${brew_version}"

ebk_log_ok 'Homebrew setup is complete.'
ebk_log_info 'Open a new terminal, or run this in your current terminal:'
ebk_log_info 'source ~/.zprofile'
