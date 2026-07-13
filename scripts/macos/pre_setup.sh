#!/bin/zsh

# Prepare Homebrew's Apple Silicon prefix so the installing user owns it.

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

if [[ "$(uname -m)" != "arm64" ]]; then
  error 'This script is intended for Apple Silicon Macs only.'
  error "Detected architecture: $(uname -m)"
  exit 1
fi

if [[ -d /opt/homebrew ]]; then
  info '===> /opt/homebrew already exists.'
elif [[ -e /opt/homebrew ]]; then
  error 'ERROR: /opt/homebrew exists but is not a directory.'
  exit 1
else
  info '===> Creating /opt/homebrew...'
  sudo mkdir -p /opt/homebrew
fi

if [[ ! -d /opt/homebrew ]]; then
  error 'ERROR: /opt/homebrew was not created successfully.'
  exit 1
fi

info "===> Setting /opt/homebrew ownership to $USER:admin..."
sudo chown -R "$USER":admin /opt/homebrew

info '===> Installing Homebrew...'
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

info '===> Checking /opt/homebrew ownership...'
ls -ld /opt/homebrew

if [[ "$(stat -f '%Su' /opt/homebrew)" != "$USER" ]]; then
  error "ERROR: /opt/homebrew is not owned by $USER."
  exit 1
fi

success "===> Verified /opt/homebrew is owned by $USER."

shellenv_line='eval "$(/opt/homebrew/bin/brew shellenv zsh)"'

info '===> Adding Homebrew to ~/.zprofile if needed...'
touch "$HOME/.zprofile"

if ! grep -qxF "$shellenv_line" "$HOME/.zprofile"; then
  printf '\n%s\n' "$shellenv_line" >> "$HOME/.zprofile"
  success '===> Added Homebrew shell setup to ~/.zprofile.'
else
  info '===> Homebrew shell setup already present in ~/.zprofile.'
fi

info '===> Loading Homebrew into this script session...'
eval "$(/opt/homebrew/bin/brew shellenv zsh)"

info '===> Verifying Homebrew...'
brew --version

success '===> Homebrew setup is complete.'
info 'Open a new terminal, or run this in your current terminal:'
info 'source ~/.zprofile'
