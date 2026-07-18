#!/bin/bash

set -o pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[0;31m'
  GOLD=$'\033[0;33m'
  GREEN=$'\033[0;32m'
  MAGENTA=$'\033[0;35m'
  BLUE=$'\033[0;34m'
  NC=$'\033[0m'
else
  RED=''
  GOLD=''
  GREEN=''
  MAGENTA=''
  BLUE=''
  NC=''
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VSCODE_EXT_FILE="$(cd "${SCRIPT_DIR}/../../config" && pwd -P)/vscode.txt"

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

trim() {
  local value="$1"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

run_cmd() {
  printf '%s$' "$BLUE"
  printf ' %q' "$@"
  printf '%s\n' "$NC"
  "$@"
}

is_installed() {
  local wanted
  local installed
  wanted="$(lowercase "$1")"

  while IFS= read -r installed; do
    if [[ "$(lowercase "$installed")" == "$wanted" ]]; then
      return 0
    fi
  done < <(code --list-extensions)

  return 1
}

if ! command -v code >/dev/null 2>&1; then
  printf '%sERROR: VSCode CLI "code" not found. Please install it first.%s\n' "$RED" "$NC"
  exit 1
fi

if [[ ! -f "$VSCODE_EXT_FILE" ]]; then
  printf '%sERROR: %s not found. Please create it with extension IDs.%s\n' "$RED" "$VSCODE_EXT_FILE" "$NC"
  exit 1
fi

installed_count="$(code --list-extensions | wc -l | tr -d '[:space:]')"
printf '%s==> Installed VSCode extensions detected: %s%s\n' "$MAGENTA" "$installed_count" "$NC"
printf '%s\n==> Reading extensions from %s%s\n' "$MAGENTA" "$VSCODE_EXT_FILE" "$NC"

exts_to_install=()
duplicate_count=0
invalid_count=0
seen_exts=$'\n'

while IFS= read -r ext || [[ -n "$ext" ]]; do
  ext="$(trim "$ext")"

  if [[ -z "$ext" || "$ext" == \#* ]]; then
    continue
  fi

  if [[ ! "$ext" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*\.[A-Za-z0-9][A-Za-z0-9_.-]*(@[A-Za-z0-9_.-]+)?$ ]]; then
    printf '%sWARN: Ignoring invalid extension ID "%s".%s\n' "$GOLD" "$ext" "$NC"
    ((invalid_count++))
    continue
  fi

  ext="$(lowercase "$ext")"
  if [[ "$seen_exts" == *$'\n'"$ext"$'\n'* ]]; then
    printf '%sWARN: Duplicate extension "%s" in config, ignoring.%s\n' "$GOLD" "$ext" "$NC"
    ((duplicate_count++))
    continue
  fi

  seen_exts+="$ext"$'\n'
  exts_to_install+=("$ext")
done < "$VSCODE_EXT_FILE"

printf '%s\n==> Extensions to be installed from %s:%s\n' "$MAGENTA" "$VSCODE_EXT_FILE" "$NC"
for ext in "${exts_to_install[@]}"; do
  printf '%s%s%s\n' "$BLUE" "$ext" "$NC"
done
printf '%sTotal extensions found: %d%s\n\n' "$MAGENTA" "${#exts_to_install[@]}" "$NC"

install_count=0
skip_count=0
fail_count=0

for ext in "${exts_to_install[@]}"; do
  if is_installed "$ext"; then
    printf '%sWARN: Extension "%s" is already installed, skipping installation.%s\n' "$GOLD" "$ext" "$NC"
    ((skip_count++))
    continue
  fi

  printf '%s==> Installing extension: %s%s\n' "$MAGENTA" "$ext" "$NC"
  if run_cmd code --install-extension "$ext"; then
    if is_installed "$ext"; then
      printf '%sSUCCESS: Installed "%s".%s\n' "$GREEN" "$ext" "$NC"
      ((install_count++))
    else
      printf '%sERROR: Command completed but "%s" was not found in the installed extension list.%s\n' "$RED" "$ext" "$NC"
      ((fail_count++))
    fi
  else
    printf '%sERROR: Failed to install "%s".%s\n' "$RED" "$ext" "$NC"
    ((fail_count++))
  fi
  sleep 0.2
done

printf '%s\n==> VSCode extension installation complete.%s\n' "$MAGENTA" "$NC"
printf '%sInstalled: %d%s\n' "$GREEN" "$install_count" "$NC"
printf '%sSkipped: %d%s\n' "$GOLD" "$skip_count" "$NC"
printf '%sDuplicates ignored: %d%s\n' "$GOLD" "$duplicate_count" "$NC"
printf '%sInvalid ignored: %d%s\n' "$GOLD" "$invalid_count" "$NC"
printf '%sFailed: %d%s\n' "$RED" "$fail_count" "$NC"

if ((fail_count > 0 || invalid_count > 0)); then
  printf '%s\nERROR: VSCode setup completed with issues.%s\n' "$RED" "$NC"
  exit 1
fi

printf '%s\nAll done.%s\n' "$GREEN" "$NC"
