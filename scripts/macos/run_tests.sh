#!/bin/zsh
# run_tests.sh - Dry-run validation for macOS scripts

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/../.."

command_exists() { command -v "$1" >/dev/null 2>&1; }

log_step() {
  printf '===> %s\n' "$1"
}

log_warn() {
  printf '===> WARN: %s\n' "$1"
}

log_ok() {
  printf '===> OK: %s\n' "$1"
}

log_step "Starting macOS script dry-run checks"

scripts=(
  "${SCRIPT_DIR}/colors.sh"
  "${SCRIPT_DIR}/conv-dot-to-png.sh"
  "${SCRIPT_DIR}/dock_setup.sh"
  "${SCRIPT_DIR}/gen_dock_apps.sh"
  "${SCRIPT_DIR}/git_setup.sh"
  "${SCRIPT_DIR}/jenv_setup.sh"
  "${SCRIPT_DIR}/setup_env.sh"
  "${SCRIPT_DIR}/vscode_setup.sh"
)

ok_count=0
fail_count=0
shellcheck_fail=0
missing_count=0

for script in "${scripts[@]}"; do
  if [ ! -f "$script" ]; then
    log_warn "Missing script: $script"
    ((missing_count++))
    continue
  fi
  if zsh -n "$script"; then
    log_ok "Syntax OK: $(basename "$script")"
  else
    log_warn "Syntax FAILED: $(basename "$script")"
    ((fail_count++))
  fi
done

if command_exists shellcheck; then
  for script in "${scripts[@]}"; do
    # Only lint bash/sh scripts
    if [ -f "$script" ] && grep -qE '^#! */bin/(bash|sh)' "$script"; then
      if shellcheck -x "$script"; then
        log_ok "ShellCheck OK: $(basename "$script")"
      else
        log_warn "ShellCheck FAILED: $(basename "$script")"
        ((shellcheck_fail++))
      fi
    fi
  done
else
  log_warn "ShellCheck not found; skipping lint"
fi

# Config file sanity checks
config_files=(
  "${REPO_ROOT}/config/dock_apps.txt"
  "${REPO_ROOT}/config/vscode.txt"
)

config_ok=0
config_missing=0

for cfg in "${config_files[@]}"; do
  if [ -f "$cfg" ]; then
    log_ok "Config found: $(basename "$cfg")"
    ((config_ok++))
  else
    log_warn "Config missing: $cfg"
    ((config_missing++))
  fi
done

log_step "Summary"
log_ok "Scripts OK: $(( ${#scripts[@]} - fail_count - missing_count ))"
log_warn "Scripts failed: $fail_count"
log_warn "Scripts missing: $missing_count"
log_ok "Configs OK: $config_ok"
log_warn "Configs missing: $config_missing"
log_ok "ShellCheck OK: $(( ${#scripts[@]} - shellcheck_fail ))"
log_warn "ShellCheck failed: $shellcheck_fail"
log_step "macOS dry-run checks complete"
if ((fail_count > 0 || shellcheck_fail > 0)); then
  exit 1
fi
