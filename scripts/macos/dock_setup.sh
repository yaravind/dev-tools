#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

SCRIPT_DIR="${0:A:h}"
DOCK_FILE="${SCRIPT_DIR}/../../config/dock_apps.txt"
DOCK_PLIST="$HOME/Library/Preferences/com.apple.dock.plist"
DOCK_PLIST_BAK="$HOME/Library/Preferences/com.apple.dock.plist.bak.$(date +%Y%m%d%H%M%S)"
SCRIPT_NAME="${0:A:t}"
DRY_RUN=0

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

# Print and run a command in blue
run_cmd() {
  printf "\033[0;34m$ %s\033[0m\n" "$*"
  "$@"
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
  if [ -f "$DOCK_PLIST_BAK" ]; then
    ebk_log_warn "Rolling back Dock to previous state..."
    run_cmd cp "$DOCK_PLIST_BAK" "$DOCK_PLIST"
    run_cmd killall Dock
    ebk_log_ok "Rollback complete."
  else
    ebk_log_warn "No backup found. Manual recovery may be required."
  fi
  exit 1
}

# Check if the app list file exists, else terminate with error
if [ ! -f "$DOCK_FILE" ]; then
  ebk_log_error "${DOCK_FILE} not found. Please run gen_dock_apps.sh to create it."
  exit 1
else
  ebk_log_info "Reading from ${DOCK_FILE}"
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

  if ! command -v dockutil >/dev/null 2>&1; then
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

  printf "\nThe following items will be ADDED to the Dock in this order:\n"
  for item in "${add_list[@]}"; do
    if [[ "$item" == "[spacer]" ]]; then
      printf "  %2d. [spacer]\n" "$index"
    elif [ -e "$item" ]; then
      printf "  %2d. %s\n" "$index" "$item"
    else
      printf "  %2d. %s (missing, will be skipped)\n" "$index" "$item"
    fi
    ((index++))
  done

  printf "\nThe following explicit config removals will be applied if present:\n"
  if [[ "${#remove_list[@]}" -eq 0 ]]; then
    printf "  - none\n"
  else
    for item in "${remove_list[@]}"; do
      printf "  - %s\n" "$item"
    done
  fi

  printf "\nThe following current Dock apps will be removed because they are not in the target config:\n"
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
fi

print_plan

if [[ "$DRY_RUN" -eq 1 ]]; then
  ebk_log_ok "Dry run complete. No Dock changes were made."
  exit 0
fi

printf "\nWould you like to proceed? (y/n): "
read -r proceed
if [[ ! "$proceed" =~ ^[yY]$ ]]; then
  ebk_log_warn "Aborted by user. No changes made."
  exit 0
fi

ebk_log_phase "Backing up current Dock to ${DOCK_PLIST_BAK}"
run_cmd cp "$DOCK_PLIST" "$DOCK_PLIST_BAK" || { rollback "Failed to backup Dock plist."; }

#printf "\nUsing existing %s.\n" "$DOCK_FILE"

ebk_log_phase "Changing Dock settings"
printf "\nTurning off Dock magnification...\n"
run_cmd defaults write com.apple.dock magnification -bool false || rollback "Failed to set Dock magnification."

DOCK_ICON_SIZE=45
printf "\nSetting Dock icon size to %d pixels...\n" "$DOCK_ICON_SIZE"
run_cmd defaults write com.apple.dock tilesize -int "$DOCK_ICON_SIZE" || rollback "Failed to set Dock icon size."

printf "\nSetting minimize window animation to Genie Effect...\n"
run_cmd defaults write com.apple.dock mineffect -string "genie" || rollback "Failed to set minimize effect."

printf "\nEnabling 'Minimize windows into application icon'...\n"
run_cmd defaults write com.apple.dock minimize-to-application -bool true || rollback "Failed to enable minimize to application."

printf "\nSetting Dock auto-hide to false...\n"
run_cmd defaults write com.apple.dock autohide -bool false || rollback "Failed to set Dock auto-hide."

ebk_log_phase "Removing all existing Dock apps"
run_cmd dockutil --remove all --no-restart || rollback "Failed to remove all Dock apps."

ebk_log_phase "Re-adding apps from ${DOCK_FILE}"
count=0
skipped=0
while IFS= read -r app; do
  # Remove apps that start with --
  if [[ "$app" =~ ^-- ]]; then
    app_to_remove="${app#--}"
    app_to_remove="${app_to_remove## }" # trim leading spaces
    if [ -n "$app_to_remove" ]; then
      app_to_remove="$(unescape_app_path "$app_to_remove")"
      # Check if the app is present in the Dock before removing
      if dockutil --list | grep -Fq "$app_to_remove"; then
        printf "\nRemoving %s from Dock...\n" "$app_to_remove"
        run_cmd dockutil --remove "$app_to_remove" --no-restart 2>/dev/null || ebk_log_error "Failed to remove ${app_to_remove} from Dock."
      fi
    fi
    ((skipped++))
    continue
  fi
  # Ignore empty lines, comments, or lines starting with //
  if [[ -z "$app" ]] || [[ "$app" =~ ^// ]]; then
    ((skipped++))
    continue
  fi
  # Add a Dock spacer if the line is 'spacer' (case-insensitive, trimmed)
  if [[ "${app// /}" =~ ^[sS][pP][aA][cC][eE][rR]$ ]]; then
    printf "\nAdding spacer to Dock...\n"
    run_cmd dockutil --add "" --type spacer --section apps --no-restart || rollback "Failed to add spacer to Dock."
    ((count++))
    continue
  fi
  app_real="$(unescape_app_path "$app")"
  if [ -e "$app_real" ]; then
    #printf "\nAdding %s to Dock...\n" "$app_real"
    run_cmd dockutil --add "$app_real" --no-restart || rollback "Failed to add $app_real to Dock."
    ((count++))
  else
    ebk_log_warn "${app_real} does not exist, skipping."
    ((skipped++))
  fi
done < "$DOCK_FILE"

ebk_log_ok "Added ${count} apps to Dock. Skipped ${skipped} entries."

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

ebk_log_ok "Awesome, all set."
