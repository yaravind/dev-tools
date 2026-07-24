#!/bin/zsh

# setup_env_min_rollback.sh - Rollback for Minimal macOS setup
#
# Uninstalls and cleans up:
#   1) Git
#   2) JDK (Microsoft OpenJDK 17)
#   3) Maven
#   4) Visual Studio Code
#   5) IntelliJ IDEA Community
#   6) ~/.hushlogin
#
# Usage:
#   chmod +x scripts/macos/setup_env_min_rollback.sh
#   ./scripts/macos/setup_env_min_rollback.sh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

print_normalized_output() {
  local line
  while IFS= read -r line; do
    if [[ "$line" == Warning:* ]]; then
      log_warn "${line#Warning: }"
    else
      printf '%s\n' "$line"
    fi
  done
}

run_brew_with_normalized_warnings() {
  local output
  output="$("$@" 2>&1)"
  local command_status=$?
  if [[ -n "$output" ]]; then
    print_normalized_output <<< "$output"
  fi
  return "$command_status"
}

brew_uninstall_formula() {
  local formula="$1"

  if ! brew list --formula --versions "$formula" >/dev/null 2>&1; then
    log_warn "$formula not installed. Skipping."
    return 0
  fi

  log_info "Uninstalling formula: $formula"
  run_brew_with_normalized_warnings brew uninstall "$formula"
}

brew_uninstall_cask() {
  local cask="$1"

  if ! brew list --cask --versions "$cask" >/dev/null 2>&1; then
    log_warn "$cask not installed. Skipping."
    return 0
  fi

  log_info "Uninstalling cask: $cask"
  run_brew_with_normalized_warnings brew uninstall --cask "$cask"
}

main() {
  log_step "Starting rollback of minimal macOS developer environment..."

  if [[ -f ~/.hushlogin ]]; then
    log_info "Removing ~/.hushlogin..."
    rm ~/.hushlogin
  else
    log_warn "~/.hushlogin not found. Skipping."
  fi

  log_step "Uninstalling applications..."

  # CLI tools
  brew_uninstall_formula git

  # JDK
  brew_uninstall_cask microsoft-openjdk@17

  # Maven
  brew_uninstall_formula maven

  # Editors
  brew_uninstall_cask visual-studio-code
  brew_uninstall_cask intellij-idea-ce

  log_info "Cleaning up Homebrew..."
  run_brew_with_normalized_warnings brew cleanup

  log_ok "Rollback complete!"
}

main "$@"
