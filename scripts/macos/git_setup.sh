#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

set -u

fail_count=0
action_performed=0
selected_action="none"
SCRIPT_START_SECONDS=$SECONDS

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

log_phase() {
  ebk_log_phase "$1"
  [[ -n "${2:-}" ]] && ebk_log_info "$2"
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
    log_info "  $line"
  done
}

format_duration() {
  local total_seconds="$1"
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  if (( hours > 0 )); then
    printf '%dh %dm %ds' "$hours" "$minutes" "$seconds"
  elif (( minutes > 0 )); then
    printf '%dm %ds' "$minutes" "$seconds"
  else
    printf '%ds' "$seconds"
  fi
}

print_structured_report() {
  local status_label="$1"
  local status_icon
  local status_color

  case "$status_label" in
    SUCCESS)
      status_icon="✔"
      status_color="$EBK_OK_COLOR"
      ;;
    FAILED)
      status_icon="✖"
      status_color="$EBK_ERROR_COLOR"
      ;;
    *)
      status_icon="⚠"
      status_color="$EBK_WARN_COLOR"
      ;;
  esac

  printf '\n%sFinal Status Report%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
  printf '  %-24s %s\n' "Script" "Git Setup (macOS)"
  printf '  %-24s %s\n' "Action selected" "$selected_action"
  printf "  %-24s ${status_color}%s %s${EBK_RESET}\n" "Status" "$status_icon" "$status_label"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
  printf '  %-24s %d\n' "Action performed" "$action_performed"
  printf '  %-24s %d\n' "Failures" "$fail_count"
  printf '  %-24s %s\n' "Duration" "$(format_duration $((SECONDS - SCRIPT_START_SECONDS)))"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
}

print_existing_git_state() {
  local current_name current_email helpers_output gh_status

  current_name="$(git_global_value user.name)"
  current_email="$(git_global_value user.email)"
  helpers_output="$(git config --global --get-all credential.helper 2>/dev/null || true)"

  log_phase "DISCOVER" "Reading existing Git and GitHub CLI configuration"
  log_info "Global user.name: ${current_name:-not set}"
  log_info "Global user.email: ${current_email:-not set}"

  if [[ -z "$helpers_output" ]]; then
    log_info "Credential helpers: not set"
  else
    log_info "Credential helpers:"
    print_indented <<< "$helpers_output"
  fi

  log_phase "DISCOVER" "Reading existing GitHub CLI authentication state"
  if command_exists gh; then
    gh_status="$(gh auth status 2>&1)"
    if [[ -z "$gh_status" ]]; then
      log_warn "gh returned no account status."
    else
      print_indented <<< "$gh_status"
    fi
  else
    log_warn "gh is not installed or is not in PATH."
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

  log_phase "CONFIGURE" "Updating global Git identity and credential helper"
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
  selected_action="update-global-identity"
}

add_github_account() {
  log_phase "CONFIGURE" "Adding a GitHub CLI account"

  if ! command_exists gh; then
    record_failure "gh is not installed or is not in PATH. Install GitHub CLI first, then rerun this option."
    return 1
  fi

  log_info "Starting gh auth login. Follow the GitHub CLI prompts to add an account."
  if gh auth login; then
    log_ok "GitHub CLI account setup completed."
    action_performed=1
    selected_action="add-gh-account"
  else
    record_failure "gh auth login failed or was canceled."
    return 1
  fi
}

print_next_steps() {
  log_phase "NEXT STEPS"
  log_info "1. If Git prompts for GitHub credentials, use your GitHub username and a personal access token as the password."
  log_info "2. To generate a token, go to GitHub > Settings > Developer settings > Personal access tokens."
  log_info "3. Prefer a fine-grained token when you want to limit repository access or your organization requires it."
  log_info "4. macOS will store accepted HTTPS credentials through the osxkeychain helper."
}

prompt_action() {
  local choice

  if has_existing_git_state; then
    log_phase "CHOOSE" "Select a Git setup action"
    log_info "1. Skip changes"
    log_info "2. Update global Git identity and credential helper"
    log_info "3. Add another GitHub CLI account with gh auth login"
    printf '\nSelect an option [1-3] (default: 1): '
    IFS= read -r choice

    case "$(trim "$choice")" in
      ""|1|skip)
        selected_action="skip"
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
        selected_action="skip-invalid-choice"
        log_warn "Unknown selection '$choice'; skipping changes."
        return 0
        ;;
    esac
  else
    log_phase "CHOOSE" "Select a Git setup action"
    log_info "1. Configure global Git identity and credential helper"
    log_info "2. Add a GitHub CLI account with gh auth login"
    log_info "3. Skip changes"
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
        selected_action="skip"
        log_ok "Skipped Git setup changes."
        return 0
        ;;
      *)
        selected_action="skip-invalid-choice"
        log_warn "Unknown selection '$choice'; skipping changes."
        return 0
        ;;
    esac
  fi
}

main() {
  local final_status="SUCCESS"

  if ! command_exists git; then
    log_error "git is not installed or is not in PATH."
    exit 1
  fi

  print_existing_git_state
  prompt_action

  if [[ "$action_performed" -eq 1 ]]; then
    print_next_steps
  fi

  if [[ "$fail_count" -gt 0 ]]; then
    final_status="FAILED"
  elif [[ "$action_performed" -eq 0 ]]; then
    final_status="NO CHANGES"
  fi

  log_phase "SUMMARY" "Compiling final run report"
  print_structured_report "$final_status"

  if [[ "$fail_count" -gt 0 ]]; then
    log_error "Completed with $fail_count error(s)."
    exit 1
  fi

  log_ok "Git setup complete."
}

main "$@"
