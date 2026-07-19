#!/bin/zsh

# Prepare the Homebrew prefix and shell wiring for Apple Silicon and Intel Macs.

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

info() {
  printf "${BLUE}%s${RESET}\n" "$1"
}

success() {
  printf "${GREEN}%s${RESET}\n" "$1"
}

error() {
  printf "${RED}%s${RESET}\n" "$1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

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
    error "Unsupported macOS architecture: ${ARCHITECTURE}"
    exit 1
    ;;
esac

info "===> Detected architecture: ${ARCHITECTURE}"
info "===> Target Homebrew prefix: ${HOMEBREW_PREFIX}"

if [[ -e "$HOMEBREW_PREFIX" && ! -d "$HOMEBREW_PREFIX" ]]; then
  error "ERROR: ${HOMEBREW_PREFIX} exists but is not a directory."
  exit 1
fi

if [[ "$PREPARE_PREFIX_OWNERSHIP" -eq 1 ]]; then
  if [[ -d "$HOMEBREW_PREFIX" ]]; then
    info "===> ${HOMEBREW_PREFIX} already exists."
  else
    info "===> Creating ${HOMEBREW_PREFIX}..."
    sudo mkdir -p "$HOMEBREW_PREFIX"
  fi

  if [[ ! -d "$HOMEBREW_PREFIX" ]]; then
    error "ERROR: ${HOMEBREW_PREFIX} was not created successfully."
    exit 1
  fi

  info "===> Setting ${HOMEBREW_PREFIX} ownership to $USER:admin..."
  sudo chown -R "$USER":admin "$HOMEBREW_PREFIX"
else
  info "===> Skipping recursive ownership changes for ${HOMEBREW_PREFIX} on Intel Macs."
fi

info '===> Installing Homebrew...'
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

BREW_BIN="${HOMEBREW_PREFIX}/bin/brew"

if [[ ! -x "$BREW_BIN" ]] && command_exists brew; then
  BREW_BIN="$(command -v brew)"
  HOMEBREW_PREFIX="$("$BREW_BIN" --prefix)"
fi

if [[ ! -x "$BREW_BIN" ]]; then
  error "ERROR: Unable to find brew binary under ${HOMEBREW_PREFIX}/bin or PATH."
  exit 1
fi

info "===> Detected Homebrew binary: ${BREW_BIN}"
info "===> Active Homebrew prefix: ${HOMEBREW_PREFIX}"

if [[ "$PREPARE_PREFIX_OWNERSHIP" -eq 1 ]]; then
  info "===> Checking ${HOMEBREW_PREFIX} ownership..."
  ls -ld "$HOMEBREW_PREFIX"

  if [[ "$(stat -f '%Su' "$HOMEBREW_PREFIX")" != "$USER" ]]; then
    error "ERROR: ${HOMEBREW_PREFIX} is not owned by $USER."
    exit 1
  fi

  success "===> Verified ${HOMEBREW_PREFIX} is owned by $USER."
fi

shellenv_line="eval \"\$(${BREW_BIN} shellenv zsh)\""

info '===> Adding Homebrew to ~/.zprofile if needed...'
touch "$HOME/.zprofile"

if ! grep -qxF "$shellenv_line" "$HOME/.zprofile"; then
  printf '\n%s\n' "$shellenv_line" >> "$HOME/.zprofile"
  success '===> Added Homebrew shell setup to ~/.zprofile.'
else
  info '===> Homebrew shell setup already present in ~/.zprofile.'
fi

info '===> Loading Homebrew into this script session...'
eval "$("$BREW_BIN" shellenv zsh)"

info '===> Verifying Homebrew...'
brew --version

success '===> Homebrew setup is complete.'
info 'Open a new terminal, or run this in your current terminal:'
info 'source ~/.zprofile'
