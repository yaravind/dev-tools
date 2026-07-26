#!/bin/zsh

# Clone GitHub repositories listed as "org/repo-name".
#
# Usage:
#   ./scripts/macos/clone_github_repos.sh
#   ./scripts/macos/clone_github_repos.sh repos.txt
#   ./scripts/macos/clone_github_repos.sh repos.txt /path/to/destination
#   cat repos.txt | ./scripts/macos/clone_github_repos.sh -
#
# config/github-repos.txt example:
#   openai/openai-python
#   cli/cli

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

set -u

SCRIPT_DIR="${0:A:h}"
DEFAULT_REPO_LIST="${SCRIPT_DIR:h:h}/config/github-repos.txt"
SCRIPT_START_SECONDS=$SECONDS

usage() {
  cat <<'EOF'
Usage: clone_github_repos.sh [repo-list-file|-] [destination-dir]

Each non-empty, non-comment line must use:
  org/repo-name

With no arguments, the script reads:
  config/github-repos.txt

Examples:
  clone_github_repos.sh
  clone_github_repos.sh repos.txt
  clone_github_repos.sh repos.txt ~/Developer
  cat repos.txt | clone_github_repos.sh -
EOF
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

print_normalized_output() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == Warning:* ]]; then
      log_warn "${line#Warning: }"
    elif [[ "$line" == warning:* ]]; then
      log_warn "${line#warning: }"
    else
      printf '%s\n' "$line"
    fi
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
  printf '  %-24s %s\n' "Script" "Clone GitHub Repositories (macOS)"
  printf '  %-24s %s\n' "Repo source" "$repo_list"
  printf '  %-24s %s\n' "Destination" "$destination_dir"
  printf "  %-24s ${status_color}%s %s${EBK_RESET}\n" "Status" "$status_icon" "$status_label"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
  printf '  %-24s %d\n' "Total entries" "$total"
  printf '  %-24s %d\n' "Cloned" "$cloned"
  printf '  %-24s %d\n' "Skipped existing" "$skipped"
  printf '  %-24s %d\n' "Failed clones" "$failed"
  printf '  %-24s %d\n' "Invalid entries" "$invalid"
  printf '  %-24s %s\n' "Duration" "$(format_duration $((SECONDS - SCRIPT_START_SECONDS)))"
  printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET"
}

if [ "$#" -gt 2 ]; then
  usage >&2
  exit 2
fi

repo_list="${1:-$DEFAULT_REPO_LIST}"
destination_dir="${2:-.}"

if ! command_exists git; then
  log_error "git is not installed or is not in PATH."
  exit 1
fi

if [ "$repo_list" != "-" ] && [ ! -f "$repo_list" ]; then
  log_error "repo list file not found: $repo_list"
  exit 1
fi

if ! mkdir -p "$destination_dir"; then
  log_error "Failed to create destination directory: $destination_dir"
  exit 1
fi

total=0
cloned=0
skipped=0
failed=0
invalid=0

clone_repo() {
  local line="$1"
  local repo repo_name clone_path
  local clone_output

  repo="$(trim "${line%%#*}")"

  if [ -z "$repo" ]; then
    return 0
  fi

  total=$((total + 1))

  if [[ ! "$repo" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]]; then
    log_error "Invalid repo entry, expected org/repo-name: $repo"
    invalid=$((invalid + 1))
    return 0
  fi

  repo_name="${repo:t}"
  clone_path="${destination_dir}/${repo_name}"

  if [ -e "$clone_path" ]; then
    log_warn "Skipping $repo: $clone_path already exists."
    skipped=$((skipped + 1))
    return 0
  fi

  log_info "Cloning $repo into $clone_path..."
  if clone_output="$(git clone "https://github.com/${repo}.git" "$clone_path" 2>&1)"; then
    if [[ -n "$clone_output" ]]; then
      print_normalized_output <<< "$clone_output"
    fi
    log_ok "Cloned $repo."
    cloned=$((cloned + 1))
  else
    if [[ -n "$clone_output" ]]; then
      print_normalized_output <<< "$clone_output"
    fi
    log_error "Failed to clone $repo."
    failed=$((failed + 1))
  fi
}

log_step "DISCOVER"
if [ "$repo_list" = "-" ]; then
  log_info "Repo list: stdin"
else
  log_info "Repo list: $repo_list"
fi
log_info "Destination: $destination_dir"
log_step "EXECUTE"

if [ "$repo_list" = "-" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    clone_repo "$line"
  done
else
  while IFS= read -r line || [ -n "$line" ]; do
    clone_repo "$line"
  done < "$repo_list"
fi

log_step "SUMMARY"
final_status="SUCCESS"
if [ "$failed" -gt 0 ] || [ "$invalid" -gt 0 ]; then
  final_status="FAILED"
elif [ "$cloned" -eq 0 ] && [ "$skipped" -gt 0 ]; then
  final_status="NO CHANGES"
fi
print_structured_report "$final_status"

if [ "$failed" -gt 0 ] || [ "$invalid" -gt 0 ]; then
  exit 1
fi
