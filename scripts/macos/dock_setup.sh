#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

SCRIPT_DIR="${0:A:h}"
DOCK_FILE="${SCRIPT_DIR}/../../config/dock_apps.txt"
DOCK_PLIST="$HOME/Library/Preferences/com.apple.dock.plist"
DOCK_PLIST_BAK="$HOME/Library/Preferences/com.apple.dock.plist.bak.$(date +%Y%m%d%H%M%S)"
SCRIPT_NAME="${0:A:t}"
SCRIPT_START_SECONDS=$SECONDS
USER_CANCEL_EXIT=75
DRY_RUN=0
ADDED_COUNT=0
SPACER_COUNT=0
SKIPPED_COUNT=0
REMOVED_EXPLICIT_COUNT=0
REMOVED_DRIFT_COUNT=0
WARN_COUNT=0

print_usage() {
  printf "Usage: %s [--dry-run]\n" "$SCRIPT_NAME"
  printf "Options:\n"
  printf "  --dry-run, -n   Show Dock changes without applying them.\n"
  printf "  --help, -h      Show this help message.\n"
}

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)
      DRY_RUN=1
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      ebk_log_error "Unknown argument: $arg"
      print_usage
      exit 1
      ;;
  esac
done

run_cmd() {
  ebk_log_debug "Running: $*"
  "$@"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

format_duration() {
  local total_seconds="$1"
  printf '%02dh:%02dm:%02ds' \
    $((total_seconds / 3600)) \
    $(((total_seconds % 3600) / 60)) \
    $((total_seconds % 60))
}

unescape_app_path() {
  local app="$1"
  app="${app//\\ / }"
  app="${app/#\$HOME/$HOME}"
  app="${app/#\$\{HOME\}/$HOME}"
  app="${app/#\~/$HOME}"
  printf "%s" "$app"
}

path_in_list() {
  local needle="$1"
  shift

  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

# Rollback function
rollback() {
  ebk_log_error "$1"
  WARN_COUNT=$((WARN_COUNT + 1))
  if [ -f "$DOCK_PLIST_BAK" ]; then
    ebk_log_warn "Rolling back Dock to previous state..."
    WARN_COUNT=$((WARN_COUNT + 1))
    run_cmd cp "$DOCK_PLIST_BAK" "$DOCK_PLIST"
    run_cmd killall Dock
    ebk_log_ok "Rollback complete."
  else
    ebk_log_warn "No backup found. Manual recovery may be required."
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
  exit 1
}

# Check if the app list file exists, else terminate with error
if [ ! -f "$DOCK_FILE" ]; then
  ebk_log_error "${DOCK_FILE} not found. Please run gen_dock_apps.sh to create it."
  exit 1
else
  ebk_log_info "Using Dock config: ${DOCK_FILE}"
fi

add_list=()
remove_list=()
target_app_paths=()
current_dock_paths=()
current_remove_list=()

parse_dock_file() {
  local app
  local app_real
  local app_to_remove

  while IFS= read -r app; do
    if [[ "$app" =~ ^-- ]]; then
      app_to_remove="${app#--}"
      app_to_remove="${app_to_remove## }"
      if [ -n "$app_to_remove" ]; then
        remove_list+=("$(unescape_app_path "$app_to_remove")")
      fi
      continue
    fi

    if [[ -z "$app" ]] || [[ "$app" =~ ^// ]]; then
      continue
    fi

    if [[ "${app// /}" =~ ^[sS][pP][aA][cC][eE][rR]$ ]]; then
      add_list+=("[spacer]")
      continue
    fi

    app_real="$(unescape_app_path "$app")"
    add_list+=("$app_real")
    target_app_paths+=("$app_real")
  done < "$DOCK_FILE"
}

collect_current_dock_apps() {
  local dock_path

  if ! command_exists dockutil; then
    return 1
  fi

  while IFS= read -r dock_path; do
    if [[ -n "$dock_path" ]]; then
      current_dock_paths+=("$dock_path")
    fi
  done < <(dockutil --list | awk -F '\t' '{print $2}' | grep '^file:///' | sed 's|^file://||;s|/$||;s|%20| |g')

  for dock_path in "${current_dock_paths[@]}"; do
    if ! path_in_list "$dock_path" "${target_app_paths[@]}"; then
      current_remove_list+=("$dock_path")
    fi
  done
}

print_plan() {
  local index=1
  local item

  ebk_log_phase "Planned Dock changes"
  ebk_log_info "Items to add (in order):"
  for item in "${add_list[@]}"; do
    if [[ "$item" == "[spacer]" ]]; then
      printf "  %2d. [spacer]\n" "$index"
    elif [ -e "$item" ]; then
      printf "  %2d. %s\n" "$index" "$item"
    else
      printf "  %2d. %s (missing, will be skipped)\n" "$index" "$item"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
    ((index++))
  done

  ebk_log_info "Explicit removals from config:"
  if [[ "${#remove_list[@]}" -eq 0 ]]; then
    printf "  - none\n"
  else
    for item in "${remove_list[@]}"; do
      printf "  - %s\n" "$item"
    done
  fi

  ebk_log_info "Current Dock apps not in config (to be removed):"
  if [[ "${#current_remove_list[@]}" -eq 0 ]]; then
    printf "  - none\n"
  else
    for item in "${current_remove_list[@]}"; do
      printf "  - %s\n" "$item"
    done
  fi
}

parse_dock_file
if ! collect_current_dock_apps; then
  ebk_log_warn "dockutil is not available; unable to compare against the current Dock."
  WARN_COUNT=$((WARN_COUNT + 1))
fi

print_plan

if [[ "$DRY_RUN" -eq 1 ]]; then
  ebk_log_ok "Dry run complete. No Dock changes were made."
  exit 0
fi

if ! command_exists dockutil; then
  ebk_log_error "dockutil is required. Install it with: brew install dockutil"
  exit 1
fi

if [[ ! -f "$DOCK_PLIST" ]]; then
  ebk_log_error "Dock plist not found at ${DOCK_PLIST}."
  exit 1
fi

if ! command_exists defaults; then
  ebk_log_error "defaults command is required on macOS."
  exit 1
fi

ebk_log_info "Review the plan above before continuing."
printf "\nWould you like to proceed? (y/n): "
read -r proceed
if [[ ! "$proceed" =~ ^[yY]$ ]]; then
  ebk_log_warn "Aborted by user. No changes made."
  exit "$USER_CANCEL_EXIT"
fi

ebk_log_phase "Backing up current Dock to ${DOCK_PLIST_BAK}"
run_cmd cp "$DOCK_PLIST" "$DOCK_PLIST_BAK" || { rollback "Failed to backup Dock plist."; }

#printf "\nUsing existing %s.\n" "$DOCK_FILE"

ebk_log_phase "Changing Dock settings"
ebk_log_info "Turning off Dock magnification..."
run_cmd defaults write com.apple.dock magnification -bool false || rollback "Failed to set Dock magnification."

DOCK_ICON_SIZE=45
ebk_log_info "Setting Dock icon size to ${DOCK_ICON_SIZE}px..."
run_cmd defaults write com.apple.dock tilesize -int "$DOCK_ICON_SIZE" || rollback "Failed to set Dock icon size."

ebk_log_info "Setting minimize effect to Genie..."
run_cmd defaults write com.apple.dock mineffect -string "genie" || rollback "Failed to set minimize effect."

ebk_log_info "Enabling minimize-to-application..."
run_cmd defaults write com.apple.dock minimize-to-application -bool true || rollback "Failed to enable minimize to application."

ebk_log_info "Setting Dock auto-hide to false..."
run_cmd defaults write com.apple.dock autohide -bool false || rollback "Failed to set Dock auto-hide."

ebk_log_phase "Removing all existing Dock apps"
run_cmd dockutil --remove all --no-restart || rollback "Failed to remove all Dock apps."

ebk_log_phase "Re-adding apps from ${DOCK_FILE}"
while IFS= read -r app; do
  # Remove apps that start with --
  if [[ "$app" =~ ^-- ]]; then
    app_to_remove="${app#--}"
    app_to_remove="${app_to_remove## }" # trim leading spaces
    if [ -n "$app_to_remove" ]; then
      app_to_remove="$(unescape_app_path "$app_to_remove")"
      # Check if the app is present in the Dock before removing
      if dockutil --list | grep -Fq "$app_to_remove"; then
        ebk_log_info "Removing ${app_to_remove} from Dock..."
        run_cmd dockutil --remove "$app_to_remove" --no-restart 2>/dev/null || ebk_log_error "Failed to remove ${app_to_remove} from Dock."
        REMOVED_EXPLICIT_COUNT=$((REMOVED_EXPLICIT_COUNT + 1))
      fi
    fi
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi
  # Ignore empty lines, comments, or lines starting with //
  if [[ -z "$app" ]] || [[ "$app" =~ ^// ]]; then
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi
  # Add a Dock spacer if the line is 'spacer' (case-insensitive, trimmed)
  if [[ "${app// /}" =~ ^[sS][pP][aA][cC][eE][rR]$ ]]; then
    ebk_log_info "Adding spacer to Dock..."
    run_cmd dockutil --add "" --type spacer --section apps --no-restart || rollback "Failed to add spacer to Dock."
    SPACER_COUNT=$((SPACER_COUNT + 1))
    ADDED_COUNT=$((ADDED_COUNT + 1))
    continue
  fi
  app_real="$(unescape_app_path "$app")"
  if [ -e "$app_real" ]; then
    ebk_log_info "Adding ${app_real}..."
    run_cmd dockutil --add "$app_real" --no-restart || rollback "Failed to add $app_real to Dock."
    ADDED_COUNT=$((ADDED_COUNT + 1))
  else
    ebk_log_warn "${app_real} does not exist, skipping."
    WARN_COUNT=$((WARN_COUNT + 1))
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  fi
done < "$DOCK_FILE"

REMOVED_DRIFT_COUNT=${#current_remove_list[@]}
ebk_log_ok "Applied Dock item changes."

#printf "\nAdding 'Other' folder to Dock...\n"
#run_cmd dockutil --add ~/Documents/Other --view grid --display folder --no-restart || rollback "Failed to add 'Other' folder to Dock."

ebk_log_phase "Restarting Dock to apply changes"
run_cmd killall Dock || rollback "Failed to restart Dock."
ebk_log_ok "Dock setup complete."

# Ask user if they want to remove the backup
printf "\nDo you want to remove the Dock backup file %s? (y/n): " "$DOCK_PLIST_BAK"
read -r remove_bak
if [[ "$remove_bak" =~ ^[yY]$ ]]; then
  run_cmd rm "$DOCK_PLIST_BAK" && ebk_log_ok "Backup removed."
else
  ebk_log_info "Backup retained at ${DOCK_PLIST_BAK}."
fi

elapsed_seconds=$((SECONDS - SCRIPT_START_SECONDS))
ebk_log_phase "Summary"
ebk_log_ok "Status: completed"
ebk_log_ok "Dock items added: ${ADDED_COUNT} (spacers: ${SPACER_COUNT})"
ebk_log_ok "Config entries skipped: ${SKIPPED_COUNT}"
ebk_log_ok "Current Dock drift removals planned: ${REMOVED_DRIFT_COUNT}"
ebk_log_ok "Explicit removals applied: ${REMOVED_EXPLICIT_COUNT}"
if [[ "$WARN_COUNT" -gt 0 ]]; then
  ebk_log_warn "Warnings: ${WARN_COUNT}"
else
  ebk_log_ok "Warnings: 0"
fi
ebk_log_ok "Duration: $(format_duration "$elapsed_seconds")"
