#!/bin/zsh
# test_setup_env_min.sh - Safe verification harness for setup_env_min.sh
# This script does not install anything. It performs the same verification checks as setup_env_min.sh's verify() function.

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."

command_exists() { command -v "$1" >/dev/null 2>&1; }

log_step() { printf '===> %s\n' "$1" }
log_ok() { printf '===> OK: %s\n' "$1" }
log_warn() { printf '===> WARN: %s\n' "$1" }

log_step "Starting macOS minimal setup verification (safe)"

# Verify Homebrew
log_step "Verify Homebrew..."
if command_exists brew; then
  brew --version || log_warn "brew --version failed"
  log_ok "Homebrew present"
else
  log_warn "Homebrew not found in PATH"
fi

# Verify Fonts (JetBrains Mono or Fira Code)
log_step "Verify developer fonts (JetBrains Mono or Fira Code)..."
FONT_OK=0
if fc-list | grep -i "jetbrains mono" >/dev/null 2>&1; then
  log_ok "JetBrains Mono font present"
  FONT_OK=1
elif fc-list | grep -i "fira code" >/dev/null 2>&1; then
  log_ok "Fira Code font present"
  FONT_OK=1
else
  log_warn "Common developer fonts (JetBrains Mono or Fira Code) not found via fc-list"
fi

# Verify jenv
log_step "Verify jenv..."
if command_exists jenv; then
  jenv versions || log_warn "jenv versions failed"
  log_ok "jenv present"
else
  log_warn "jenv not found in PATH"
fi

# Verify pipx
log_step "Verify pipx..."
if command_exists pipx; then
  pipx --version || log_warn "pipx --version failed"
  log_ok "pipx present"
else
  log_warn "pipx not found in PATH"
fi

# Verify Git
log_step "Verify Git..."
if command_exists git; then
  git --version || log_warn "git --version failed"
  log_ok "git present"
else
  log_warn "git not found in PATH"
fi

# Verify Java
log_step "Verify Java..."
if command_exists java; then
  java -version 2>&1 || log_warn "java -version failed"
  log_ok "java present"
else
  log_warn "java not found in PATH"
fi

# Verify Maven
log_step "Verify Maven..."
if command_exists mvn; then
  mvn -version || log_warn "mvn -version failed"
  log_ok "mvn present"
else
  log_warn "mvn not found in PATH"
fi

# Verify VS Code
log_step "Verify VS Code..."
if command_exists code; then
  code --version | head -n 1 || log_warn "code --version failed"
  log_ok "code present"
else
  log_warn "code not found in PATH"
fi

# Verify IntelliJ - manual
log_step "Verify IntelliJ IDEA..."
log_warn "IntelliJ verification is manual. Launch it once to finish first-run setup."

log_step "macOS minimal setup verification complete"
exit 0
