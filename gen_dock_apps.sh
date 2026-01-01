#!/bin/zsh

APPLIST_FILE="dock_apps.txt"

printf "\nGenerating %s from current Dock...\n" "$APPLIST_FILE"
dockutil --list | awk -F '\t' '{print $2}' | \
  grep '^file:///' | \
  grep '.app/' | \
  sed 's|file://||;s|/$||' > "$APPLIST_FILE"
printf "\n%s created.\n" "$APPLIST_FILE"

printf "\n\n👌 Awesome, all set. Now run the doc_setup.sh\n"