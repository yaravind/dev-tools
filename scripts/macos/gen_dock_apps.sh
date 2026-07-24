#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

APPLIST_FILE="${0:A:h}/../../config/dock_apps.txt"

ebk_log_phase "Generating ${APPLIST_FILE} from current Dock"
dockutil --list | awk -F '\t' '{print $2}' | \
  grep '^file:///' | \
  grep '.app/' | \
  sed 's|file://||;s|/$||' > "$APPLIST_FILE"
ebk_log_ok "${APPLIST_FILE} created."

ebk_log_info "Awesome, all set. Now run dock_setup.sh."