#!/bin/zsh

# Color codes (from dock_setup.sh style)
RED=$'\033[0;31m'
GOLD=$'\033[0;33m'
GREEN=$'\033[0;32m'
MAGENTA=$'\033[0;35m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

# Print and run a command in blue
run_cmd() {
  printf '%s$ %s%s\n' "$BLUE" "$*" "$NC"
  "$@"
}

VSCODE_EXT_FILE="vscode.txt"

# Check if code CLI is available
if ! command -v code &>/dev/null; then
  printf '%sERROR: VSCode CLI "code" not found. Please install it first.%s\n' "$RED" "$NC"
  exit 1
fi

printf '%s==> Listing currently installed VSCode extensions...%s\n' "$MAGENTA" "$NC"
run_cmd code --list-extensions

# Check if extension list file exists
if [ ! -f "$VSCODE_EXT_FILE" ]; then
  printf '%sERROR: %s not found. Please create it with extension IDs.%s\n' "$RED" "$VSCODE_EXT_FILE" "$NC"
  exit 1
else
  printf '%s\n==> Reading extensions from %s%s\n' "$MAGENTA" "$VSCODE_EXT_FILE" "$NC"
fi

installed_exts=()
while IFS= read -r ext; do
  installed_exts+=("$ext")
done < <(code --list-extensions)

# Read and filter extensions from vscode.txt
exts_to_install=()
while IFS= read -r ext || [[ -n "$ext" ]]; do
  # Remove carriage returns and trim whitespace
  ext="$(echo "$ext" | tr -d '\r' | xargs)"
  # Ignore empty lines
  if [[ -z "$ext" ]]; then
    continue
  fi
  exts_to_install+=("$ext")
done < "$VSCODE_EXT_FILE"

# Print extensions to be installed and their count
printf '%s\n==> Extensions to be installed from %s:%s\n' "$MAGENTA" "$VSCODE_EXT_FILE" "$NC"
for ext in "${exts_to_install[@]}"; do
  printf '%s%s%s\n' "$BLUE" "$ext" "$NC"
done
printf '%sTotal extensions found: %d%s\n\n' "$MAGENTA" "${#exts_to_install[@]}" "$NC"

install_count=0
skip_count=0
fail_count=0

for ext in "${exts_to_install[@]}"; do
  # No need to re-filter, already done above
  # Exclude installation if already installed
  already_installed=false
  for i in "${installed_exts[@]}"; do
    if [[ "$i" == "$ext" ]]; then
      already_installed=true
      break
    fi
  done
  if $already_installed; then
    printf '%sWARN: Extension "%s" is already installed, skipping installation.%s\n' "$GOLD" "$ext" "$NC"
    ((skip_count++))
    continue
  fi
  printf '%s==> Installing extension: %s%s\n' "$MAGENTA" "$ext" "$NC"
  if run_cmd code --install-extension "$ext"; then
    printf '%sSUCCESS: Installed "%s".%s\n' "$GREEN" "$ext" "$NC"
    ((install_count++))
    installed_exts+=("$ext")
  else
    printf '%sERROR: Failed to install "%s".%s\n' "$RED" "$ext" "$NC"
    ((fail_count++))
  fi
  sleep 0.2
done

printf '%s\n==> VSCode extension installation complete.%s\n' "$MAGENTA" "$NC"
printf '%sInstalled: %d%s\n' "$GREEN" "$install_count" "$NC"
printf '%sSkipped: %d%s\n' "$GOLD" "$skip_count" "$NC"
printf '%sFailed: %d%s\n' "$RED" "$fail_count" "$NC"

printf '%s\n👌 All done.%s\n' "$GREEN" "$NC"
