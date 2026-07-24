#!/bin/zsh

# Merges config/.zshrc into the live ~/.zshrc by:
#   1. Backing up ~/.zshrc
#   2. Removing lines already covered by the repo config (duplicates)
#   3. Appending a single `source` line pointing to config/.zshrc
#
# Machine-managed blocks (Rancher Desktop, pure prompt, antidote) are
# preserved untouched.

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:A:t}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
ZSHRC_FILE="${HOME}/.zshrc"
REPO_CONFIG="${REPO_ROOT}/config/.zshrc"
SOURCE_LINE="source \"${REPO_CONFIG}\""

command_exists() { command -v "$1" >/dev/null 2>&1; }

print_usage() {
  printf 'Usage: %s [--dry-run]\n' "$SCRIPT_NAME"
}

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --help|-h) print_usage; exit 0 ;;
    *) log_error "Unknown argument: ${arg}"; print_usage; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Lines in ~/.zshrc that are covered by config/.zshrc and can be removed.
# Only exact full-line matches are removed (no substring stripping).
# ---------------------------------------------------------------------------
covered_lines=(
  '# direnv: load environment variables per-directory'
  'eval "$(direnv hook zsh)"'
  "alias rm='trash'"
  "alias cat='bat'"
  '# jenv: initialize shims and shell integration'
  '# jenv setup'
  'eval "$(jenv init -)"'
  'export PATH="$HOME/.jenv/bin:$PATH"'
)

is_covered_line() {
  local line="$1" pattern
  for pattern in "${covered_lines[@]}"; do
    [[ "$line" == "$pattern" ]] && return 0
  done
  return 1
}

validate_repo_config() {
  if [[ ! -f "$REPO_CONFIG" ]]; then
    log_error "Repo config not found: ${REPO_CONFIG}"
    return 1
  fi
  log_info "Repo config: ${REPO_CONFIG}"
}

backup_zshrc() {
  if [[ ! -f "$ZSHRC_FILE" ]]; then
    log_info "~/.zshrc does not exist yet — will create on first write."
    return 0
  fi
  local backup="${ZSHRC_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  if (( DRY_RUN )); then
    log_info "[dry-run] Would back up ~/.zshrc to ${backup}"
    return 0
  fi
  if cp "$ZSHRC_FILE" "$backup"; then
    log_ok "Backed up ~/.zshrc → ${backup}"
  else
    log_error "Failed to back up ~/.zshrc"
    return 1
  fi
}

remove_covered_lines() {
  if [[ ! -f "$ZSHRC_FILE" ]]; then
    log_info "~/.zshrc not found — skipping line removal."
    return 0
  fi

  local removed_count=0
  local line consecutive_blanks=0
  local tmp_file
  tmp_file="$(mktemp)" || { log_error "Failed to create temp file."; return 1; }

  while IFS= read -r line || [[ -n "$line" ]]; do
    if is_covered_line "$line"; then
      (( removed_count++ ))
      if (( DRY_RUN )); then
        log_info "[dry-run] Would remove: ${line}"
      else
        log_info "Removing covered line: ${line}"
      fi
      continue
    fi

    # Collapse consecutive blank lines left by removed content (max 1 blank)
    if [[ -z "$line" ]]; then
      (( consecutive_blanks++ ))
      if (( consecutive_blanks > 1 )); then
        continue
      fi
    else
      consecutive_blanks=0
    fi

    printf '%s\n' "$line" >> "$tmp_file"
  done < "$ZSHRC_FILE"

  if (( DRY_RUN )); then
    rm -f "$tmp_file"
    log_info "[dry-run] Would remove ${removed_count} covered line(s) from ~/.zshrc"
    return 0
  fi

  mv "$tmp_file" "$ZSHRC_FILE" || { log_error "Failed to write filtered ~/.zshrc."; return 1; }

  if (( removed_count > 0 )); then
    log_ok "Removed ${removed_count} covered line(s) from ~/.zshrc"
  else
    log_info "No covered lines found in ~/.zshrc — nothing to remove."
  fi
}

ensure_source_line() {
  if grep -qF "$SOURCE_LINE" "$ZSHRC_FILE" 2>/dev/null; then
    log_info "~/.zshrc already sources the repo config."
    return 0
  fi

  if (( DRY_RUN )); then
    log_info "[dry-run] Would append to ~/.zshrc:"
    log_info "  # dev-tools shared config"
    log_info "  ${SOURCE_LINE}"
    return 0
  fi

  touch "$ZSHRC_FILE"
  {
    printf '\n# dev-tools shared config\n'
    printf '%s\n' "$SOURCE_LINE"
  } >> "$ZSHRC_FILE" || { log_error "Failed to append source line to ~/.zshrc."; return 1; }

  log_ok "Appended source line to ~/.zshrc"
}

show_result() {
  (( DRY_RUN )) && return 0
  log_step "Resulting ~/.zshrc"
  printf '\n'
  cat "$ZSHRC_FILE"
  printf '\n'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log_phase "zshrc setup"
log_info "Merging repo config into ~/.zshrc (source approach)"

validate_repo_config || exit 1
backup_zshrc         || exit 1
remove_covered_lines || exit 1
ensure_source_line   || exit 1
show_result

if (( DRY_RUN )); then
  log_ok "Dry run complete — no changes made."
else
  log_ok "Done. Restart your shell or run: source ~/.zshrc"
fi
