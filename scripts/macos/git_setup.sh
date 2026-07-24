#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

set -u

fail_count=0
action_performed=0

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

record_failure() {
  log_error "$1"
  fail_count=$((fail_count + 1))
}

trim() {
  local value="$1"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

git_global_value() {
  git config --global --get "$1" 2>/dev/null || true
}

print_indented() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '  %s\n' "$line"
  done
}

print_existing_git_state() {
  local current_name current_email helpers_output gh_status

  current_name="$(git_global_value user.name)"
  current_email="$(git_global_value user.email)"
  helpers_output="$(git config --global --get-all credential.helper 2>/dev/null || true)"

  log_step "Existing Git configuration"
  printf '  %-22s %s\n' "Global user.name:" "${current_name:-not set}"
  printf '  %-22s %s\n' "Global user.email:" "${current_email:-not set}"

  printf '  %-22s ' "Credential helpers:"
  if [[ -z "$helpers_output" ]]; then
    printf 'not set\n'
  else
    printf '\n'
    print_indented <<< "$helpers_output"
  fi

  log_step "Existing GitHub CLI accounts"
  if command_exists gh; then
    gh_status="$(gh auth status 2>&1)"
    if [[ -z "$gh_status" ]]; then
      printf '  gh returned no account status.\n'
    else
      print_indented <<< "$gh_status"
    fi
  else
    printf '  gh is not installed or is not in PATH.\n'
  fi
}

has_existing_git_state() {
  local current_name current_email helpers_output
  current_name="$(git_global_value user.name)"
  current_email="$(git_global_value user.email)"
  helpers_output="$(git config --global --get-all credential.helper 2>/dev/null || true)"

  [[ -n "$current_name" || -n "$current_email" || -n "$helpers_output" ]]
}

read_required_into() {
  local target_var="$1"
  local prompt="$2"
  local value

  while true; do
    printf '%s' "$prompt"
    IFS= read -r value
    value="$(trim "$value")"

    if [[ -n "$value" ]]; then
      typeset -g "$target_var=$value"
      return 0
    fi

    log_warn "Value cannot be empty."
  done
}

read_email_into() {
  local target_var="$1"
  local entered_email

  while true; do
    read_required_into entered_email "Type in your email address used for GitHub: "
    if [[ "$entered_email" == *@*.* ]]; then
      typeset -g "$target_var=$entered_email"
      return 0
    fi

    log_warn "Email address does not look valid: $entered_email"
  done
}

configure_credential_helper() {
  local helpers_output
  helpers_output="$(git config --global --get-all credential.helper 2>/dev/null || true)"

  if [[ "$helpers_output" == "osxkeychain" ]]; then
    log_ok "credential.helper is already set to osxkeychain."
    return 0
  fi

  if git config --global --replace-all credential.helper osxkeychain; then
    log_ok "Set credential.helper to osxkeychain."
    return 0
  fi

  record_failure "Failed to set credential.helper to osxkeychain."
  return 1
}

update_global_git_identity() {
  local full_name email

  log_step "Update global Git identity"
  read_required_into full_name "Type in your first and last name (no accent or special characters - e.g. 'ç'): "
  read_email_into email

  if git config --global user.name "$full_name"; then
    log_ok "Set global user.name to $full_name."
  else
    record_failure "Failed to set global user.name."
  fi

  if git config --global user.email "$email"; then
    log_ok "Set global user.email to $email."
  else
    record_failure "Failed to set global user.email."
  fi

  configure_credential_helper
  action_performed=1
}

add_github_account() {
  log_step "Add GitHub CLI account"

  if ! command_exists gh; then
    record_failure "gh is not installed or is not in PATH. Install GitHub CLI first, then rerun this option."
    return 1
  fi

  log_info "Starting gh auth login. Follow the GitHub CLI prompts to add an account."
  if gh auth login; then
    log_ok "GitHub CLI account setup completed."
    action_performed=1
  else
    record_failure "gh auth login failed or was canceled."
    return 1
  fi
}

print_next_steps() {
  cat <<'EOF'

Next steps:

1. If Git prompts for GitHub credentials, use your GitHub username and a personal access token as the password.
2. To generate a token, go to GitHub > Settings > Developer settings > Personal access tokens.
3. Prefer a fine-grained token when you want to limit repository access or your organization requires it.
4. macOS will store accepted HTTPS credentials through the osxkeychain helper.

EOF
}

prompt_action() {
  local choice

  if has_existing_git_state; then
    log_step "Choose Git setup action"
    printf '  1. Skip changes\n'
    printf '  2. Update global Git identity and credential helper\n'
    printf '  3. Add another GitHub CLI account with gh auth login\n'
    printf '\nSelect an option [1-3] (default: 1): '
    IFS= read -r choice

    case "$(trim "$choice")" in
      ""|1|skip)
        log_ok "Skipped Git setup changes."
        return 0
        ;;
      2|update)
        update_global_git_identity
        ;;
      3|add)
        add_github_account
        ;;
      *)
        log_warn "Unknown selection '$choice'; skipping changes."
        return 0
        ;;
    esac
  else
    log_step "Choose Git setup action"
    printf '  1. Configure global Git identity and credential helper\n'
    printf '  2. Add a GitHub CLI account with gh auth login\n'
    printf '  3. Skip changes\n'
    printf '\nSelect an option [1-3] (default: 1): '
    IFS= read -r choice

    case "$(trim "$choice")" in
      ""|1|configure)
        update_global_git_identity
        ;;
      2|add)
        add_github_account
        ;;
      3|skip)
        log_ok "Skipped Git setup changes."
        return 0
        ;;
      *)
        log_warn "Unknown selection '$choice'; skipping changes."
        return 0
        ;;
    esac
  fi
}

main() {
  if ! command_exists git; then
    log_error "git is not installed or is not in PATH."
    exit 1
  fi

  print_existing_git_state
  prompt_action

  if [[ "$fail_count" -gt 0 ]]; then
    log_error "Completed with $fail_count error(s)."
    exit 1
  fi

  if [[ "$action_performed" -eq 1 ]]; then
    print_next_steps
  fi
  log_ok "Git setup complete."
}

main "$@"
