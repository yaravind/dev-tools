#!/bin/zsh

# setup_env_min.sh - Minimal macOS setup for Spark/Scala/Java development
#
# Installs and verifies (via Homebrew):
#   1) Git
#   2) JDK (Microsoft OpenJDK 17)
#   3) Maven (installed without pulling a JDK dependency)
#   4) Visual Studio Code
#   5) IntelliJ IDEA Community
#
# Usage:
#   chmod +x scripts/macos/setup_env_min.sh
#   ./scripts/macos/setup_env_min.sh

# Import colors codes for text
source "${0:A:h}/colors.sh"

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

log_step() {
  printf '===> %s\n' "$1" | sed "s/^/${MAGENTA}/;s/$/${RESET}/"
}

log_info() {
  printf '===> %s\n' "$1" | sed "s/^/${CYAN}/;s/$/${RESET}/"
}

log_ok() {
  printf '===> %s\n' "$1" | sed "s/^/${GREEN}/;s/$/${RESET}/"
}

log_warn() {
  printf '===> %s\n' "$1" | sed "s/^/${YELLOW}/;s/$/${RESET}/"
}

log_error() {
  printf 'ERROR: %s\n' "$1" | sed "s/^/${RED}/;s/$/${RESET}/" >&2
}

# Function to install Homebrew if not installed
install_homebrew() {
  if ! command_exists brew; then
    log_warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
}

brew_install_formula() {
  local formula="$1"

  if brew list --formula --versions "$formula" >/dev/null 2>&1; then
    log_warn "$formula already installed. Skipping."
    return 0
  fi

  log_info "Installing formula: $formula"
  brew install "$formula"
}

brew_install_cask() {
  local cask="$1"

  if brew list --cask --versions "$cask" >/dev/null 2>&1; then
    log_warn "$cask already installed. Skipping."
    return 0
  fi

  log_info "Installing cask: $cask"
  brew install --cask "$cask"
}

install_maven_no_java_dep() {
  if command_exists mvn; then
    log_warn "mvn already available. Skipping Maven install."
    return 0
  fi

  # Mirrors the approach used in setup_env.sh
  log_info "Installing maven (without pulling Java as a dependency)"
  brew install --ignore-dependencies maven
}

verify() {
  log_step "Start verification"

  log_info "Verify Git..."
  if command_exists git; then
    git --version
  else
    log_warn "git not found in PATH. Restart your terminal."
  fi

  log_info "Verify Java..."
  if command_exists java; then
    java -version
  else
    log_warn "java not found in PATH. Restart your terminal."
  fi

  log_info "Verify Maven..."
  if command_exists mvn; then
    mvn -version
  else
    log_warn "mvn not found in PATH. Restart your terminal."
  fi

  log_info "Verify VS Code..."
  if command_exists code; then
    code --version | head -n 1
  else
    log_warn "code not found in PATH. In VS Code: Cmd+Shift+P → 'Shell Command: Install \'code\' command in PATH'"
  fi

  log_info "Verify IntelliJ IDEA..."
  log_warn "IntelliJ verification is manual. Launch it once to finish first-run setup."
}

main() {
  log_step "Starting minimal macOS developer environment setup..."

  log_info "Creating ~/.hushlogin to disable login banner."
  touch ~/.hushlogin

  install_homebrew

  log_info "Updating Homebrew..."
  brew update

  log_step "Installing required tools..."

  # CLI tools
  brew_install_formula git

  # JDK
  brew_install_cask microsoft-openjdk@17

  # Maven
  install_maven_no_java_dep

  # Editors
  brew_install_cask visual-studio-code
  brew_install_cask intellij-idea-ce

  log_info "Cleaning up Homebrew..."
  brew cleanup

  verify

  log_ok "Awesome, all set!"
}

main "$@"

