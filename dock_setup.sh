#!/bin/zsh

DOCK_FILE="dock_apps.txt"
DOCK_PLIST="$HOME/Library/Preferences/com.apple.dock.plist"
DOCK_PLIST_BAK="$HOME/Library/Preferences/com.apple.dock.plist.bak.$(date +%Y%m%d%H%M%S)"

# Print and run a command in blue
run_cmd() {
  printf "\033[0;34m$ %s\033[0m\n" "$*"
  "$@"
}

# Rollback function
rollback() {
  printf "\033[0;31m\nERROR: %s\033[0m\n" "$1"
  if [ -f "$DOCK_PLIST_BAK" ]; then
    printf "\nRolling back Dock to previous state...\n"
    run_cmd cp "$DOCK_PLIST_BAK" "$DOCK_PLIST"
    run_cmd killall Dock
    printf "\nRollback complete.\n"
  else
    printf "\nNo backup found. Manual recovery may be required.\n"
  fi
  exit 1
}

# Check if the app list file exists, else terminate with error
if [ ! -f "$DOCK_FILE" ]; then
  printf "\033[0;31m\nERROR: %s not found. Please run gen_dock_apps.sh to create it.\033[0m\n" "$DOCK_FILE"
  exit 1
else
  printf "\033[0;35m\n==> Reading from %s\033[0m\n" "$DOCK_FILE"
fi

# Preview what will be added and removed
add_list=()
remove_list=()
while IFS= read -r app; do
  if [[ "$app" =~ ^-- ]]; then
    app_to_remove="${app#--}"
    app_to_remove="${app_to_remove## }"
    if [ -n "$app_to_remove" ]; then
      remove_list+=("$app_to_remove")
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
  add_list+=("$app")
done < "$DOCK_FILE"

printf "\nThe following items will be ADDED to the Dock:\n"
for item in "${add_list[@]}"; do
  printf "  + %s\n" "$item"
done
printf "\nThe following items will be REMOVED from the Dock (if present):\n"
for item in "${remove_list[@]}"; do
  printf "  - %s\n" "$item"
done

printf "\nWould you like to proceed? (y/n): "
read -r proceed
if [[ ! "$proceed" =~ ^[yY]$ ]]; then
  printf "\nAborted by user. No changes made.\n"
  exit 0
fi

printf "\033[0;35m\n==> Backing up current Dock to %s...\033[0m\n" "$DOCK_PLIST_BAK"
run_cmd cp "$DOCK_PLIST" "$DOCK_PLIST_BAK" || { rollback "Failed to backup Dock plist."; }

#printf "\nUsing existing %s.\n" "$DOCK_FILE"

printf "\033[0;35m\n==> Changing Dock settings.\033[0m\n"
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

printf "\033[0;35m\n==> Removing all existing Dock apps...\033[0m\n"
run_cmd dockutil --remove all --no-restart || rollback "Failed to remove all Dock apps."

printf "\033[0;35m\n==> Re-adding apps from %s...\033[0m\n" "$DOCK_FILE"
count=0
skipped=0
while IFS= read -r app; do
  # Remove apps that start with --
  if [[ "$app" =~ ^-- ]]; then
    app_to_remove="${app#--}"
    app_to_remove="${app_to_remove## }" # trim leading spaces
    if [ -n "$app_to_remove" ]; then
      # Check if the app is present in the Dock before removing
      if dockutil --list | grep -Fq "$app_to_remove"; then
        printf "\nRemoving %s from Dock...\n" "$app_to_remove"
        run_cmd dockutil --remove "$app_to_remove" --no-restart 2>/dev/null || printf "\033[0;31m\nERROR: Failed to remove %s from Dock.\033[0m\n" "$app_to_remove"
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
    run_cmd dockutil --add "''" --type spacer --section apps --no-restart || rollback "Failed to add spacer to Dock."
    ((count++))
    continue
  fi
  # Unescape any \  to space for existence check and dockutil
  app_real="${app//\\ / }"
  if [ -e "$app_real" ]; then
    #printf "\nAdding %s to Dock...\n" "$app_real"
    run_cmd dockutil --add "$app_real" --no-restart || rollback "Failed to add $app_real to Dock."
    ((count++))
  else
    printf "\033[0;33m\nWARN: %s does not exist, skipping.\033[0m\n" "$app_real"
    ((skipped++))
  fi
done < "$DOCK_FILE"

printf "\033[0;32m\nAdded %d apps to Dock. Skipped %d entries.\033[0m\n" "$count" "$skipped"

#printf "\nAdding 'Other' folder to Dock...\n"
#run_cmd dockutil --add ~/Documents/Other --view grid --display folder --no-restart || rollback "Failed to add 'Other' folder to Dock."

printf "\033[0;35m\n==> Restarting Dock to apply changes...\033[0m\n"
run_cmd killall Dock || rollback "Failed to restart Dock."
printf "\033[0;35m\n==> Dock setup complete.\033[0m\n"

# Ask user if they want to remove the backup
printf "\033[0;35m\n==> Do you want to remove the Dock backup file %s? (y/n): \033[0m" "$DOCK_PLIST_BAK"
read -r remove_bak
if [[ "$remove_bak" =~ ^[yY]$ ]]; then
  run_cmd rm "$DOCK_PLIST_BAK" && printf "\nBackup removed.\n"
else
  printf "\nBackup retained at %s.\n" "$DOCK_PLIST_BAK"
fi

printf "\n\n👌 Awesome, all set.\n"