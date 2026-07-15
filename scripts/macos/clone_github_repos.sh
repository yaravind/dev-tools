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

set -u

SCRIPT_DIR="${0:A:h}"
DEFAULT_REPO_LIST="${SCRIPT_DIR:h:h}/config/github-repos.txt"

if [ -t 1 ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'
  MAGENTA=$'\033[0;35m'
  CYAN=$'\033[0;36m'
  RESET=$'\033[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  RESET=""
fi

log_step() {
  printf '%s===> %s%s\n' "$MAGENTA" "$1" "$RESET"
}

log_info() {
  printf '%s===> %s%s\n' "$CYAN" "$1" "$RESET"
}

log_ok() {
  printf '%s===> %s%s\n' "$GREEN" "$1" "$RESET"
}

log_warn() {
  printf '%s===> %s%s\n' "$YELLOW" "$1" "$RESET"
}

log_error() {
  printf '%sERROR: %s%s\n' "$RED" "$1" "$RESET" >&2
}

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

if [ "$#" -gt 2 ]; then
  usage >&2
  exit 2
fi

repo_list="${1:-$DEFAULT_REPO_LIST}"
destination_dir="${2:-.}"

if ! command -v git >/dev/null 2>&1; then
  log_error "git is not installed or is not in PATH."
  exit 1
fi

if [ "$repo_list" != "-" ] && [ ! -f "$repo_list" ]; then
  log_error "repo list file not found: $repo_list"
  exit 1
fi

mkdir -p "$destination_dir" || exit 1

total=0
cloned=0
skipped=0
failed=0
invalid=0

clone_repo() {
  local line="$1"
  local repo repo_name clone_path

  repo="${line%%#*}"
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"

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
  if git clone "https://github.com/${repo}.git" "$clone_path"; then
    log_ok "Cloned $repo."
    cloned=$((cloned + 1))
  else
    log_error "Failed to clone $repo."
    failed=$((failed + 1))
  fi
}

log_step "Clone GitHub repositories"
log_info "Repo list: $repo_list"
log_info "Destination: $destination_dir"

if [ "$repo_list" = "-" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    clone_repo "$line"
  done
else
  while IFS= read -r line || [ -n "$line" ]; do
    clone_repo "$line"
  done < "$repo_list"
fi

echo
log_step "Summary"
printf '  Total:   %s\n' "$total"
printf '  Cloned:  %s\n' "$cloned"
printf '  Skipped: %s\n' "$skipped"
printf '  Failed:  %s\n' "$failed"
printf '  Invalid: %s\n' "$invalid"

if [ "$failed" -gt 0 ] || [ "$invalid" -gt 0 ]; then
  exit 1
fi
