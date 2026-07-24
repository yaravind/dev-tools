#!/bin/zsh

# Interactively configure macOS system and user defaults.
# Each setting is presented with a description and recommendation tag before
# asking whether to apply it.
#
# Based on: https://github.com/mathiasbynens/dotfiles/blob/main/.macos

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

source "${0:A:h}/colors.sh"

INFO="${CYAN}"
ACTION="${BLUE}"
SUCCESS="${GREEN}"
WARN="${YELLOW}"
ERROR="${RED}"
SECTION="${BMAGENTA}"
MUTED="${BBLACK}"
SCRIPT_NAME="${0:A:t}"

APPLIED=0
SKIPPED=0
DRY_RUN=0
SILENT=0
RUN_MODE=""
CONFIG_FILE=""
SAVE_CHOICES_FILE=""
SUDO_KEEPALIVE_PID=""
CURRENT_SECTION=""

typeset -A CONFIG_CHOICES
typeset -A RECORDED_CHOICES
typeset -a RECORDED_ORDER

# ─── Usage ────────────────────────────────────────────────────────────────────

print_usage() {
  printf "
${INFO}Usage: %s MODE [OPTIONS]${RESET}
" "$SCRIPT_NAME"
  printf "
${INFO}Modes:${RESET}
"
  printf "${INFO}  --admin-only      Configure system-level settings (sudo) AND user defaults${RESET}
"
  printf "${INFO}  --non-admin-only  Configure user defaults only — no sudo required${RESET}
"
  printf "
${INFO}Options:${RESET}
"
  printf "${INFO}  --dry-run, -n        Preview all changes without applying them${RESET}
"
  printf "${INFO}  --silent            Run non-interactively using --config choices${RESET}
"
  printf "${INFO}  --config FILE       Load MODE and saved option choices from FILE${RESET}
"
  printf "${INFO}  --save-choices FILE Save selected choices to FILE for reuse${RESET}
"
  printf "${INFO}  --help,    -h       Show this help message${RESET}

"
}

# ─── Argument parsing ─────────────────────────────────────────────────────────

load_config_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    printf "${ERROR}✖ ERROR Config file not found: %s${RESET}
" "$file_path"
    exit 1
  fi

  local line trimmed key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == '#'* ]] && continue
    [[ "$trimmed" != *=* ]] && continue

    key="${trimmed%%=*}"
    value="${trimmed#*=}"
    key="$(printf '%s' "$key" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"


    CONFIG_CHOICES["$key"]="$value"
  done < "$file_path"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-only|--non-admin-only)
      if [[ -n "$RUN_MODE" ]]; then
        printf "${ERROR}✖ ERROR Specify only one mode.${RESET}
"
        print_usage
        exit 1
      fi
      RUN_MODE="$1"
      shift
      ;;
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --silent)
      SILENT=1
      shift
      ;;
    --config)
      if [[ -z "$2" ]]; then
        printf "${ERROR}✖ ERROR --config requires a file path.${RESET}
"
        exit 1
      fi
      CONFIG_FILE="$2"
      shift 2
      ;;
    --save-choices)
      if [[ -z "$2" ]]; then
        printf "${ERROR}✖ ERROR --save-choices requires a file path.${RESET}
"
        exit 1
      fi
      SAVE_CHOICES_FILE="$2"
      shift 2
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      printf "${ERROR}✖ ERROR Unknown argument: %s${RESET}
" "$1"
      print_usage
      exit 1
      ;;
  esac
done

if [[ -n "$CONFIG_FILE" ]]; then
  load_config_file "$CONFIG_FILE"
fi

if [[ -z "$RUN_MODE" && -n "${CONFIG_CHOICES["MODE"]}" ]]; then
  case "${CONFIG_CHOICES["MODE"]}" in
    admin-only|--admin-only)
      RUN_MODE="--admin-only"
      ;;
    non-admin-only|--non-admin-only)
      RUN_MODE="--non-admin-only"
      ;;
  esac
fi

if [[ -z "$RUN_MODE" ]]; then
  printf "${ERROR}✖ ERROR A mode is required (or set MODE in --config).${RESET}
"
  print_usage
  exit 1
fi

if [[ "$SILENT" -eq 1 && -z "$CONFIG_FILE" ]]; then
  printf "${ERROR}✖ ERROR --silent requires --config FILE.${RESET}
"
  exit 1
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────

print_section() {
  local section_name="$1"
  local border="════════════════════════════════════════════════════════════"
  CURRENT_SECTION="$section_name"
  printf "
${SECTION}%s${RESET}
" "$border"
  printf "${SECTION}SECTION: %s${RESET}
" "$section_name"
  printf "${SECTION}%s${RESET}
" "$border"
  printf "${INFO}Each option below is part of this section.${RESET}
"
}

to_option_key() {
  local label="$1"
  local raw_key="${CURRENT_SECTION}_${label}"
  printf "opt_%s" "$(printf '%s' "$raw_key" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//; s/_+/_/g')"
}

to_yes_no() {
  local value="$1"
  case "${value:l}" in
    y|yes|true|1|on)
      printf "y"
      ;;
    n|no|false|0|off)
      printf "n"
      ;;
    *)
      printf ""
      ;;
  esac
}

record_choice() {
  local key="$1"
  local value="$2"
  if [[ -z "${RECORDED_CHOICES["$key"]}" ]]; then
    RECORDED_ORDER+=("$key")
  fi
  RECORDED_CHOICES["$key"]="$value"
}

save_choices_file() {
  local output_file="$1"
  local output_dir="${output_file:h}"
  [[ -n "$output_dir" && "$output_dir" != "$output_file" ]] && mkdir -p "$output_dir"

  {
    printf "# Saved macOS setup choices
"
    printf "# Generated by %s

" "$SCRIPT_NAME"
    if [[ "$RUN_MODE" == "--admin-only" ]]; then
      printf "MODE=admin-only
"
    else
      printf "MODE=non-admin-only
"
    fi

    local key
    for key in "${RECORDED_ORDER[@]}"; do
      printf "%s=%s
" "$key" "${RECORDED_CHOICES["$key"]}"
    done
  } > "$output_file"

  printf "${SUCCESS}✓ OK    Saved choices to %s${RESET}
" "$output_file"
}

print_loaded_choices_preview() {
  local key clean_key
  local count=0
  printf "
${INFO}Loaded choices from %s:${RESET}
" "$CONFIG_FILE"
  for key in ${(k)CONFIG_CHOICES}; do
    clean_key="${(Q)key}"
    [[ "$clean_key" == "MODE" ]] && continue
    printf "  ${MUTED}%s=%s${RESET}
" "$clean_key" "${CONFIG_CHOICES["$clean_key"]}"
    count=$(( count + 1 ))
  done
  printf "${INFO}Loaded %d choice entries.${RESET}
" "$count"
}


# Ask the user y/n for a setting.
# Usage: ask "Label" "Description" "recommended|optional" "action-preview"
# Returns 0 (yes) or 1 (no/skip).
resolve_current_value() {
  local action_preview="$1"
  local command_preview="$action_preview"

  command_preview="${command_preview#sudo }"

  local -a parts
  parts=(${(z)command_preview})

  if [[ ${#parts[@]} -eq 0 ]]; then
    printf "Unknown"
    return
  fi

  if [[ "${parts[1]}" == "defaults" ]]; then
    local domain="" key="" current=""
    if [[ "${parts[2]}" == "-currentHost" && "${parts[3]}" == "write" ]]; then
      domain="${parts[4]}"
      key="${parts[5]}"
      current="$(defaults -currentHost read "$domain" "$key" 2>/dev/null)"
    elif [[ "${parts[2]}" == "write" ]]; then
      domain="${parts[3]}"
      key="${parts[4]}"
      current="$(defaults read "$domain" "$key" 2>/dev/null)"
    fi

    if [[ -n "$current" ]]; then
      printf "%s" "$current"
    else
      printf "Not set"
    fi
    return
  fi

  if [[ "${parts[1]}" == "nvram" && -n "${parts[2]}" ]]; then
    local key="${parts[2]%%=*}"
    local current
    current="$(nvram -p 2>/dev/null | awk -v k="$key" '$1==k { $1=""; sub(/^\t+/, ""); print }')"
    if [[ -n "$current" ]]; then
      printf "%s" "$current"
    else
      printf "Not set"
    fi
    return
  fi

  if [[ "${parts[1]}" == "pmset" && ${#parts[@]} -ge 4 ]]; then
    local key="${parts[3]}"
    local current
    current="$(pmset -g 2>/dev/null | awk -v k="$key" '$1==k {print $2; exit}')"
    if [[ -n "$current" ]]; then
      printf "%s" "$current"
    else
      printf "Unknown"
    fi
    return
  fi

  if [[ "${parts[1]}" == "systemsetup" && "${parts[2]}" == "-settimezone" ]]; then
    local current
    current="$(systemsetup -gettimezone 2>/dev/null | sed 's/^Time Zone: //')"
    [[ -n "$current" ]] && printf "%s" "$current" || printf "Unknown"
    return
  fi

  if [[ "${parts[1]}" == "systemsetup" && "${parts[2]}" == "-setrestartfreeze" ]]; then
    local current
    current="$(systemsetup -getrestartfreeze 2>/dev/null | sed 's/^Restart After Freeze: //')"
    [[ -n "$current" ]] && printf "%s" "$current" || printf "Unknown"
    return
  fi

  if [[ "${parts[1]}" == "systemsetup" && "${parts[2]}" == "-setcomputersleep" ]]; then
    local current
    current="$(systemsetup -getcomputersleep 2>/dev/null | sed 's/^Computer Sleep: //')"
    [[ -n "$current" ]] && printf "%s" "$current" || printf "Unknown"
    return
  fi

  if [[ "${parts[1]}" == "chflags" && -n "${parts[3]}" ]]; then
    local path="${parts[3]}"
    local current
    current="$(ls -ldO "$path" 2>/dev/null | awk '{print $5}')"
    [[ -n "$current" ]] && printf "%s" "$current" || printf "Unknown"
    return
  fi

  if [[ "${parts[1]}" == "mdutil" || "${parts[1]}" == "ln" || "${parts[1]}" == "rm" || "${parts[1]}" == "touch" ]]; then
    printf "Will apply command"
    return
  fi

  printf "Unknown"
}

ask() {
  local label="$1" desc="$2" rec="$3" action_preview="$4"
  local option_key choice_value current_value

  option_key="$(to_option_key "$label")"

  if [[ "$rec" == "recommended" ]]; then
    printf "
  ${BGREEN}[✅ RECOMMENDED]${RESET} ${BWHITE}%s${RESET}
" "$label"
  else
    printf "
  ${BYELLOW}[⚠️  OPTIONAL]${RESET}    ${BWHITE}%s${RESET}
" "$label"
  fi
  printf "  ${INFO}↳ %s${RESET}
" "$desc"

  if [[ -n "$action_preview" ]]; then
    current_value="$(resolve_current_value "$action_preview")"
    printf "  ${MUTED}Current value: %s${RESET}
" "$current_value"
  else
    printf "  ${MUTED}Current value: Unknown${RESET}
"
  fi

  if [[ "$SILENT" -eq 1 ]]; then
    choice_value="$(to_yes_no "${CONFIG_CHOICES["$option_key"]}")"
    if [[ -z "$choice_value" ]]; then
      printf "  ${WARN}No valid saved choice for key %s; defaulting to skip.${RESET}
" "$option_key"
      record_choice "$option_key" "n"
      SKIPPED=$(( SKIPPED + 1 ))
      return 1
    fi

    printf "  ${INFO}Saved choice (%s): %s${RESET}
" "$option_key" "$choice_value"
    record_choice "$option_key" "$choice_value"
    if [[ "$choice_value" == "y" ]]; then
      return 0
    fi

    printf "    ${MUTED}─ Skipped${RESET}
"
    SKIPPED=$(( SKIPPED + 1 ))
    return 1
  fi

  printf "  Apply? (y/n): "
  local answer
  read -r answer </dev/tty
  if [[ "$answer" =~ ^[yY]$ ]]; then
    record_choice "$option_key" "y"
    return 0
  fi

  record_choice "$option_key" "n"
  printf "    ${MUTED}─ Skipped${RESET}
"
  SKIPPED=$(( SKIPPED + 1 ))
  return 1
}

# Run a command, or print it as a dry-run preview.
do_run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "    ${ACTION}[dry-run] %s${RESET}
" "$*"
  else
    "$@"
  fi
}

ok() {
  printf "    ${SUCCESS}✓ Applied${RESET}
"
  APPLIED=$(( APPLIED + 1 ))
}

cleanup() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
}
trap cleanup EXIT

# ─── Banner ───────────────────────────────────────────────────────────────────

printf "
${SECTION}╔══════════════════════════════════════╗${RESET}
"
printf "${SECTION}║    macOS Settings Configurator       ║${RESET}
"
printf "${SECTION}╚══════════════════════════════════════╝${RESET}
"
printf "
${INFO}Mode    : %s${RESET}
" "$RUN_MODE"
printf "${INFO}Silent  : %s${RESET}
" "$([[ "$SILENT" -eq 1 ]] && printf yes || printf no)"
[[ -n "$CONFIG_FILE" ]] && printf "${INFO}Config  : %s${RESET}
" "$CONFIG_FILE"
[[ -n "$SAVE_CHOICES_FILE" ]] && printf "${INFO}Save to : %s${RESET}
" "$SAVE_CHOICES_FILE"
[[ "$DRY_RUN" -eq 1 ]] && printf "${WARN}Dry-run : ON — no changes will be written${RESET}
"

if [[ "$SILENT" -eq 1 && "$DRY_RUN" -eq 1 ]]; then
  print_loaded_choices_preview
fi

# Close System Preferences to prevent it from overriding changes.
osascript -e 'tell application "System Preferences" to quit' 2>/dev/null

# ─── Sudo setup (admin-only) ──────────────────────────────────────────────────

if [[ "$RUN_MODE" == "--admin-only" ]]; then
  printf "
${WARN}⚠ WARN  This mode requires administrator privileges.${RESET}
"
  if ! sudo -v 2>/dev/null; then
    printf "${ERROR}✖ ERROR sudo authentication failed. Exiting.${RESET}
"
    exit 1
  fi
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
fi

# ══════════════════════════════════════════════════════════════════════════════
#  PART 1 — SYSTEM SETTINGS  (admin-only mode only, requires sudo)
# ══════════════════════════════════════════════════════════════════════════════

if [[ "$RUN_MODE" == "--admin-only" ]]; then

  # ── Boot / Login ────────────────────────────────────────────────────────────

  print_section "Boot & Login"

  if ask "Disable boot chime" \
    "Silences the startup sound when the Mac powers on." \
    "recommended" \
    "sudo nvram SystemAudioVolume=\" \""; then
    do_run sudo nvram SystemAudioVolume=" "
    ok
  fi

  if ask "Show system info (IP, hostname, OS) on login window" \
    "Clicking the clock on the login screen reveals the machine's IP address, hostname, and macOS version." \
    "recommended" \
    "sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName"; then
    do_run sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
    ok
  fi

  if ask "Show language/input menu on login screen" \
    "Displays an input source selector in the top-right corner of the login screen." \
    "optional" \
    "sudo defaults write /Library/Preferences/com.apple.loginwindow showInputMenu -bool true"; then
    do_run sudo defaults write /Library/Preferences/com.apple.loginwindow showInputMenu -bool true
    ok
  fi

  # ── Energy & Power ──────────────────────────────────────────────────────────

  print_section "Energy & Power Management"

  if ask "Wake on lid open" \
    "Wakes the Mac automatically when the lid is lifted." \
    "recommended" \
    "sudo pmset -a lidwake 1"; then
    do_run sudo pmset -a lidwake 1
    ok
  fi

  if ask "Auto-restart after unexpected power loss" \
    "Automatically boots the Mac if power is interrupted (e.g. unplugged during sleep)." \
    "recommended" \
    "sudo pmset -a autorestart 1"; then
    do_run sudo pmset -a autorestart 1
    ok
  fi

  if ask "Auto-restart on system freeze" \
    "Automatically reboots if the kernel detects the system has hung completely." \
    "recommended" \
    "sudo systemsetup -setrestartfreeze on"; then
    do_run sudo systemsetup -setrestartfreeze on
    ok
  fi

  if ask "Sleep display after 15 minutes of inactivity" \
    "Turns off the screen after 15 minutes to save energy. The system itself stays awake." \
    "recommended" \
    "sudo pmset -a displaysleep 15"; then
    do_run sudo pmset -a displaysleep 15
    ok
  fi

  if ask "Prevent system sleep while plugged into AC power" \
    "Keeps the Mac fully awake when on mains power — good for servers, long builds, or overnight tasks." \
    "optional" \
    "sudo pmset -c sleep 0"; then
    do_run sudo pmset -c sleep 0
    ok
  fi

  if ask "System sleep after 5 minutes on battery" \
    "Puts the Mac to sleep quickly when unplugged to preserve battery life." \
    "recommended" \
    "sudo pmset -b sleep 5"; then
    do_run sudo pmset -b sleep 5
    ok
  fi

  if ask "Extend standby delay to 24 hours (default: 1 hour)" \
    "Delays deep hibernation (disk-based sleep) for 24 hours, so the Mac wakes up faster at the cost of slightly more battery drain in standby." \
    "recommended" \
    "sudo pmset -a standbydelay 86400"; then
    do_run sudo pmset -a standbydelay 86400
    ok
  fi

  if ask "Disable hibernation (hibernatemode 0) and remove sleep image" \
    "Skips writing RAM to disk on sleep for faster sleep/wake. Reclaims several GB of disk space. ⚠️ System state will be lost if power fails during sleep." \
    "optional" \
    "sudo pmset -a hibernatemode 0"; then
    do_run sudo pmset -a hibernatemode 0
    do_run sudo rm -f /private/var/vm/sleepimage
    do_run sudo touch /private/var/vm/sleepimage
    do_run sudo chflags uchg /private/var/vm/sleepimage
    ok
  fi

  # ── Display ─────────────────────────────────────────────────────────────────

  print_section "Display"

  if ask "Enable HiDPI display modes" \
    "Unlocks Retina-quality HiDPI resolution options on external monitors. Requires a restart to take effect." \
    "recommended" \
    "sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true"; then
    do_run sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true
    ok
  fi

  # ── Filesystem ──────────────────────────────────────────────────────────────

  print_section "Filesystem"

  if ask "Unhide /Volumes in Finder" \
    "Makes the /Volumes directory visible so you can browse all mounted drives in Finder." \
    "recommended" \
    "sudo chflags nohidden /Volumes"; then
    do_run sudo chflags nohidden /Volumes
    ok
  fi

  # ── Spotlight (system level) ─────────────────────────────────────────────────

  print_section "Spotlight (system)"

  if ask "Exclude /Volumes from Spotlight auto-indexing" \
    "Prevents Spotlight from automatically indexing any new external volume that is mounted, avoiding unnecessary disk I/O and cluttered search results." \
    "recommended" \
    "sudo defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array \"/Volumes\""; then
    do_run sudo defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array "/Volumes"
    ok
  fi

  if ask "Enable and rebuild the Spotlight index" \
    "Ensures the main volume (/) has indexing enabled and forces a full index rebuild to apply any changes." \
    "recommended" \
    "sudo mdutil -i on / > /dev/null"; then
    killall mds > /dev/null 2>&1 || true
    do_run sudo mdutil -i on / > /dev/null
    do_run sudo mdutil -E / > /dev/null
    ok
  fi

fi  # end --admin-only

# ══════════════════════════════════════════════════════════════════════════════
#  PART 2 — USER DEFAULTS  (both modes)
# ══════════════════════════════════════════════════════════════════════════════

# ── General UI/UX ─────────────────────────────────────────────────────────────

print_section "General UI/UX"

if ask "Reduce UI transparency" \
  "Disables frosted-glass transparency in the menu bar, Dock, and sidebars. May help performance on older Macs." \
  "optional" \
  "defaults write com.apple.universalaccess reduceTransparency -bool true"; then
  do_run defaults write com.apple.universalaccess reduceTransparency -bool true
  ok
fi

if ask "Set sidebar icon size to medium" \
  "Sets Finder/app sidebar icons to the 'medium' size for a balanced layout." \
  "recommended" \
  "defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2"; then
  do_run defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2
  ok
fi

if ask "Always show scrollbars" \
  "Forces scrollbars to be permanently visible instead of appearing only when scrolling. Makes it obvious when content is scrollable." \
  "recommended" \
  "defaults write NSGlobalDomain AppleShowScrollBars -string \"Always\""; then
  do_run defaults write NSGlobalDomain AppleShowScrollBars -string "Always"
  ok
fi

if ask "Disable animated focus ring" \
  "Removes the bouncy pulse animation from the keyboard-focus ring around text fields and controls." \
  "recommended" \
  "defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool false"; then
  do_run defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool false
  ok
fi

if ask "Remove toolbar title rollover delay" \
  "Eliminates the hover delay before a Finder window's proxy icon becomes draggable." \
  "recommended" \
  "defaults write NSGlobalDomain NSToolbarTitleViewRolloverDelay -float 0"; then
  do_run defaults write NSGlobalDomain NSToolbarTitleViewRolloverDelay -float 0
  ok
fi

if ask "Make window resize animation nearly instant" \
  "Sets the resize animation duration to 0.001s, making all Cocoa windows resize snappily." \
  "recommended" \
  "defaults write NSGlobalDomain NSWindowResizeTime -float 0.001"; then
  do_run defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
  ok
fi

if ask "Expand Save panel by default" \
  "Opens the Save dialog in its expanded form with folder navigation instead of the compact dropdown." \
  "recommended" \
  "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true"; then
  do_run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  do_run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
  ok
fi

if ask "Expand Print panel by default" \
  "Opens the Print dialog with all options fully visible instead of the collapsed summary." \
  "recommended" \
  "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true"; then
  do_run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
  do_run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
  ok
fi

if ask "Save new documents to local disk (not iCloud)" \
  "New documents default to a local path instead of iCloud Drive, avoiding unexpected cloud uploads." \
  "recommended" \
  "defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false"; then
  do_run defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
  ok
fi

if ask "Auto-quit printer app when all jobs finish" \
  "The Printer app exits automatically once the print queue is empty — no manual cleanup needed." \
  "recommended" \
  "defaults write com.apple.print.PrintingPrefs \"Quit When Finished\" -bool true"; then
  do_run defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true
  ok
fi

if ask "Disable Gatekeeper 'Are you sure?' app-open warning" \
  "Removes the confirmation dialog when opening downloaded apps for the first time. ⚠️ Skips a security layer — only recommended if you carefully vet what you download." \
  "optional" \
  "defaults write com.apple.LaunchServices LSQuarantine -bool false"; then
  do_run defaults write com.apple.LaunchServices LSQuarantine -bool false
  ok
fi

if ask "Disable window/app Resume on reopen" \
  "Stops apps from restoring their previous windows when relaunched." \
  "recommended" \
  "defaults write com.apple.systempreferences NSQuitAlwaysKeepsWindows -bool false"; then
  do_run defaults write com.apple.systempreferences NSQuitAlwaysKeepsWindows -bool false
  ok
fi

if ask "Disable automatic termination of inactive background apps" \
  "Keeps background apps alive so they don't have to reload next time you switch to them." \
  "recommended" \
  "defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true"; then
  do_run defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true
  ok
fi

# ── Typing & Text ─────────────────────────────────────────────────────────────

print_section "Typing & Text Substitution"

if ask "Disable auto-capitalization" \
  "Prevents macOS from auto-capitalizing the first word of sentences — essential when typing code or terminal commands." \
  "recommended" \
  "defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false"; then
  do_run defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  ok
fi

if ask "Disable smart dashes" \
  "Keeps literal hyphens (--) instead of converting them to an em-dash (—). Avoids broken CLI flags and code." \
  "recommended" \
  "defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false"; then
  do_run defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  ok
fi

if ask "Disable smart quotes" \
  "Keeps straight quotes (\" and ') instead of curly/typographic quotes. Prevents broken code and config values." \
  "recommended" \
  "defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false"; then
  do_run defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  ok
fi

if ask "Disable auto-correct" \
  "Disables the system spell-corrector that silently changes words as you type." \
  "recommended" \
  "defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false"; then
  do_run defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  ok
fi

if ask "Disable automatic period insertion (double-space → period)" \
  "Stops double-space from inserting a period and space. Avoids accidental punctuation in terminals and editors." \
  "recommended" \
  "defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false"; then
  do_run defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  ok
fi

# ── Trackpad & Keyboard ───────────────────────────────────────────────────────

print_section "Trackpad & Keyboard"

if ask "Enable tap-to-click on trackpad" \
  "A light tap on the trackpad registers as a click, without needing to press down physically." \
  "recommended" \
  "defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true"; then
  do_run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  do_run defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  do_run defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  ok
fi

if ask "Map bottom-right trackpad corner to right-click" \
  "Tapping or clicking the bottom-right corner of the trackpad triggers a secondary (right) click." \
  "recommended" \
  "defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2"; then
  do_run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
  do_run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
  do_run defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 1
  do_run defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true
  ok
fi

if ask "Disable 'natural' (Lion-style) scrolling" \
  "Reverses scroll direction to the traditional style: scroll up moves content upward. Disable to keep natural/touchpad-style scrolling." \
  "optional" \
  "defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false"; then
  do_run defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
  ok
fi

if ask "Raise Bluetooth headset audio quality (bitpool min = 40)" \
  "Increases the minimum Bluetooth audio bitpool for wireless headphones/headsets, improving audio fidelity." \
  "recommended" \
  "defaults write com.apple.BluetoothAudioAgent \"Apple Bitpool Min (editable)\" -int 40"; then
  do_run defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40
  ok
fi

if ask "Enable full keyboard access for all UI controls" \
  "Allows the Tab key to cycle through every UI control in dialogs (buttons, checkboxes, menus), not just text fields." \
  "recommended" \
  "defaults write NSGlobalDomain AppleKeyboardUIMode -int 3"; then
  do_run defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
  ok
fi

if ask "Enable Ctrl+scroll to zoom the entire screen" \
  "Holding Ctrl and scrolling up/down zooms the whole display. Useful for demos and accessibility." \
  "optional" \
  "defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true"; then
  do_run defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
  do_run defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144
  do_run defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true
  ok
fi

if ask "Disable press-and-hold accent popup; use key repeat instead" \
  "Removes the accent/emoji picker that appears when holding a key, enabling continuous fast key-repeat — much better for coding and navigation." \
  "recommended" \
  "defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false"; then
  do_run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
  ok
fi

if ask "Set the fastest key repeat rate and shortest initial delay" \
  "Sets KeyRepeat=1 (fastest) and InitialKeyRepeat=10 (shortest delay). Drastically speeds up text editing and navigation with held keys." \
  "recommended" \
  "defaults write NSGlobalDomain KeyRepeat -int 1"; then
  do_run defaults write NSGlobalDomain KeyRepeat -int 1
  do_run defaults write NSGlobalDomain InitialKeyRepeat -int 10
  ok
fi

# ── Screen & Screenshots ───────────────────────────────────────────────────────

print_section "Screen & Screenshots"

if ask "Require password immediately after sleep or screensaver" \
  "The lock screen prompts for a password the instant the display wakes from sleep or screensaver." \
  "recommended" \
  "defaults write com.apple.screensaver askForPassword -int 1"; then
  do_run defaults write com.apple.screensaver askForPassword -int 1
  do_run defaults write com.apple.screensaver askForPasswordDelay -int 0
  ok
fi

if ask "Save screenshots to the Desktop" \
  "All screenshots (Cmd+Shift+3/4/5) are saved to ~/Desktop." \
  "recommended" \
  "defaults write com.apple.screencapture location -string \"${HOME}/Desktop\""; then
  do_run defaults write com.apple.screencapture location -string "${HOME}/Desktop"
  ok
fi

if ask "Save screenshots as PNG" \
  "Sets the screenshot format to lossless PNG. Other options: JPG, GIF, PDF, TIFF, BMP." \
  "recommended" \
  "defaults write com.apple.screencapture type -string \"png\""; then
  do_run defaults write com.apple.screencapture type -string "png"
  ok
fi

if ask "Disable drop shadow on window screenshots" \
  "Removes the macOS window drop shadow when capturing a specific window (Cmd+Shift+4, then Space)." \
  "recommended" \
  "defaults write com.apple.screencapture disable-shadow -bool true"; then
  do_run defaults write com.apple.screencapture disable-shadow -bool true
  ok
fi

if ask "Enable font smoothing on non-Apple displays" \
  "Applies subpixel antialiasing for crisper text rendering on external LCD monitors." \
  "recommended" \
  "defaults write NSGlobalDomain AppleFontSmoothing -int 1"; then
  do_run defaults write NSGlobalDomain AppleFontSmoothing -int 1
  ok
fi

# ── Finder ─────────────────────────────────────────────────────────────────────

print_section "Finder"

if ask "Allow quitting Finder with Cmd+Q" \
  "Enables Finder to be quit like any app. Note: quitting Finder also hides all Desktop icons." \
  "recommended" \
  "defaults write com.apple.finder QuitMenuItem -bool true"; then
  do_run defaults write com.apple.finder QuitMenuItem -bool true
  ok
fi

if ask "Disable Finder window and Get Info animations" \
  "Removes the open/close animation for Finder windows and the expand animation in Get Info (Cmd+I) panels." \
  "recommended" \
  "defaults write com.apple.finder DisableAllAnimations -bool true"; then
  do_run defaults write com.apple.finder DisableAllAnimations -bool true
  ok
fi

if ask "Open new Finder windows to the Desktop" \
  "New Finder windows start at ~/Desktop instead of Recents or the home folder." \
  "optional" \
  "defaults write com.apple.finder NewWindowTarget -string \"PfDe\""; then
  do_run defaults write com.apple.finder NewWindowTarget -string "PfDe"
  do_run defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Desktop/"
  ok
fi

if ask "Show hard drives, servers, and removable media on the Desktop" \
  "External drives, internal volumes, mounted servers, and USB/SD media appear as icons on the Desktop." \
  "recommended" \
  "defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true"; then
  do_run defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
  do_run defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
  do_run defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
  do_run defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
  ok
fi

if ask "Always show file extensions in Finder" \
  "Displays extensions (e.g. .txt, .py, .sh) for all files, including types macOS normally hides them for." \
  "recommended" \
  "defaults write NSGlobalDomain AppleShowAllExtensions -bool true"; then
  do_run defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  ok
fi

if ask "Show Finder status bar" \
  "Shows a bar at the bottom of Finder windows with item count and remaining disk space." \
  "recommended" \
  "defaults write com.apple.finder ShowStatusBar -bool true"; then
  do_run defaults write com.apple.finder ShowStatusBar -bool true
  ok
fi

if ask "Show Finder path bar" \
  "Displays a clickable breadcrumb trail at the bottom of every Finder window." \
  "recommended" \
  "defaults write com.apple.finder ShowPathbar -bool true"; then
  do_run defaults write com.apple.finder ShowPathbar -bool true
  ok
fi

if ask "Display full POSIX path in Finder window title" \
  "Shows the complete absolute path (e.g. /Users/you/Documents/project) as the Finder window title." \
  "optional" \
  "defaults write com.apple.finder _FXShowPosixPathInTitle -bool true"; then
  do_run defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
  ok
fi

if ask "Keep folders on top when sorting by name" \
  "Directories always appear above files when Finder is sorted alphabetically by name." \
  "recommended" \
  "defaults write com.apple.finder _FXSortFoldersFirst -bool true"; then
  do_run defaults write com.apple.finder _FXSortFoldersFirst -bool true
  ok
fi

if ask "Default Finder search to the current folder" \
  "When you type in the Finder search bar, it searches the current directory instead of the whole Mac." \
  "recommended" \
  "defaults write com.apple.finder FXDefaultSearchScope -string \"SCcf\""; then
  do_run defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  ok
fi

if ask "Disable file-extension change warning in Finder" \
  "Stops Finder from showing a confirmation dialog when you rename a file to change its extension." \
  "recommended" \
  "defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false"; then
  do_run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  ok
fi

if ask "Enable spring-loaded folders with no hover delay" \
  "Hovering over a folder while dragging a file opens it automatically. Setting delay to 0 makes the spring action instant." \
  "recommended" \
  "defaults write NSGlobalDomain com.apple.springing.enabled -bool true"; then
  do_run defaults write NSGlobalDomain com.apple.springing.enabled -bool true
  do_run defaults write NSGlobalDomain com.apple.springing.delay -float 0
  ok
fi

if ask "Don't create .DS_Store files on network or USB volumes" \
  "Prevents macOS from writing hidden .DS_Store metadata files onto network shares and USB drives — avoids polluting shared/cross-platform storage." \
  "recommended" \
  "defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true"; then
  do_run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  do_run defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
  ok
fi

if ask "Disable disk image checksum verification" \
  "Skips the integrity check when mounting .dmg files. Speeds up opening disk images. ⚠️ Removes a safety check — only use if you trust your sources." \
  "optional" \
  "defaults write com.apple.frameworks.diskimages skip-verify -bool true"; then
  do_run defaults write com.apple.frameworks.diskimages skip-verify -bool true
  do_run defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
  do_run defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true
  ok
fi

if ask "Auto-open a Finder window when a volume is mounted" \
  "Automatically opens a Finder window to show the contents when a disk or USB drive is mounted." \
  "optional" \
  "defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true"; then
  do_run defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
  do_run defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
  do_run defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
  ok
fi

if ask "Use List view in all Finder windows by default" \
  "Sets the default Finder view to List view (Nlsv). Other options: icnv (Icon), clmv (Column), glyv (Gallery)." \
  "recommended" \
  "defaults write com.apple.finder FXPreferredViewStyle -string \"Nlsv\""; then
  do_run defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  ok
fi

if ask "Disable 'Empty Trash' confirmation dialog" \
  "Removes the warning prompt when you empty the Trash." \
  "recommended" \
  "defaults write com.apple.finder WarnOnEmptyTrash -bool false"; then
  do_run defaults write com.apple.finder WarnOnEmptyTrash -bool false
  ok
fi

if ask "Enable AirDrop on all network interfaces (including Ethernet)" \
  "Enables AirDrop over wired Ethernet and on older Macs that don't officially support it." \
  "recommended" \
  "defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true"; then
  do_run defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true
  ok
fi

if ask "Unhide ~/Library folder" \
  "Makes the user Library folder (~/Library) visible in Finder. Handy for developer troubleshooting and config access." \
  "recommended" \
  "chflags nohidden ~/Library"; then
  do_run chflags nohidden ~/Library
  xattr -d com.apple.FinderInfo ~/Library 2>/dev/null || true
  ok
fi

if ask "Expand File Info panes: General, Open With, Sharing & Permissions" \
  "Pre-expands these three sections in the Get Info (Cmd+I) panel so they're always open and visible." \
  "recommended" \
  "defaults write com.apple.finder FXInfoPanesExpanded"; then
  do_run defaults write com.apple.finder FXInfoPanesExpanded -dict \
    General -bool true \
    OpenWith -bool true \
    Privileges -bool true
  ok
fi

# ── Dock & Mission Control ─────────────────────────────────────────────────────

print_section "Dock & Mission Control"

if ask "Highlight hovered item in Dock stack grid view" \
  "Highlights an icon when you hover over it in the fan/grid pop-up of a Dock stack folder." \
  "optional" \
  "defaults write com.apple.dock mouse-over-hilite-stack -bool true"; then
  do_run defaults write com.apple.dock mouse-over-hilite-stack -bool true
  ok
fi

if ask "Set Dock icon size to 36px" \
  "A compact 36-pixel icon size keeps the Dock small while remaining legible." \
  "optional" \
  "defaults write com.apple.dock tilesize -int 36"; then
  do_run defaults write com.apple.dock tilesize -int 36
  ok
fi

if ask "Use Scale effect when minimizing windows (instead of Genie)" \
  "Replaces the curling Genie animation with a faster, simpler scale-down effect." \
  "optional" \
  "defaults write com.apple.dock mineffect -string \"scale\""; then
  do_run defaults write com.apple.dock mineffect -string "scale"
  ok
fi

if ask "Minimize windows into their app's Dock icon" \
  "Minimized windows fold into the app icon in the Dock instead of creating a separate thumbnail on the right." \
  "recommended" \
  "defaults write com.apple.dock minimize-to-application -bool true"; then
  do_run defaults write com.apple.dock minimize-to-application -bool true
  ok
fi

if ask "Show indicator dots for open apps in the Dock" \
  "Displays a small dot beneath each running app's icon in the Dock." \
  "recommended" \
  "defaults write com.apple.dock show-process-indicators -bool true"; then
  do_run defaults write com.apple.dock show-process-indicators -bool true
  ok
fi

if ask "Disable app-launch bounce animation in the Dock" \
  "Removes the bouncing animation of icons when you launch an app from the Dock." \
  "recommended" \
  "defaults write com.apple.dock launchanim -bool false"; then
  do_run defaults write com.apple.dock launchanim -bool false
  ok
fi

if ask "Speed up Mission Control open/close animation" \
  "Sets the Mission Control animation duration to 0.1s for an almost-instant response." \
  "recommended" \
  "defaults write com.apple.dock expose-animation-duration -float 0.1"; then
  do_run defaults write com.apple.dock expose-animation-duration -float 0.1
  ok
fi

if ask "Don't group windows by app in Mission Control" \
  "Shows every window individually in Mission Control (classic Exposé behavior) rather than clustered by application." \
  "optional" \
  "defaults write com.apple.dock expose-group-by-app -bool false"; then
  do_run defaults write com.apple.dock expose-group-by-app -bool false
  ok
fi

if ask "Disable Dashboard" \
  "Turns off the Dashboard widget layer. Dashboard is deprecated in modern macOS and unused by most people." \
  "recommended" \
  "defaults write com.apple.dashboard mcx-disabled -bool true"; then
  do_run defaults write com.apple.dashboard mcx-disabled -bool true
  do_run defaults write com.apple.dock dashboard-in-overlay -bool true
  ok
fi

if ask "Don't auto-rearrange Spaces by recent use" \
  "Prevents macOS from reordering your virtual desktops (Spaces) based on which you used most recently. Keeps your layout predictable." \
  "recommended" \
  "defaults write com.apple.dock mru-spaces -bool false"; then
  do_run defaults write com.apple.dock mru-spaces -bool false
  ok
fi

if ask "Remove Dock auto-hide delay and animation" \
  "When Dock auto-hide is enabled, this makes it appear and disappear instantly with no delay or slide animation." \
  "recommended" \
  "defaults write com.apple.dock autohide-delay -float 0"; then
  do_run defaults write com.apple.dock autohide-delay -float 0
  do_run defaults write com.apple.dock autohide-time-modifier -float 0
  ok
fi

if ask "Enable Dock auto-hide" \
  "Automatically hides the Dock when the cursor moves away, freeing up screen space." \
  "recommended" \
  "defaults write com.apple.dock autohide -bool true"; then
  do_run defaults write com.apple.dock autohide -bool true
  ok
fi

if ask "Make hidden-app Dock icons translucent" \
  "Apps hidden with Cmd+H show as semi-transparent icons in the Dock so you can tell they're hidden." \
  "recommended" \
  "defaults write com.apple.dock showhidden -bool true"; then
  do_run defaults write com.apple.dock showhidden -bool true
  ok
fi

if ask "Remove 'Recent Applications' section from Dock" \
  "Hides the automatically populated 'Recents' icons on the right side of the Dock." \
  "recommended" \
  "defaults write com.apple.dock show-recents -bool false"; then
  do_run defaults write com.apple.dock show-recents -bool false
  ok
fi

if ask "Configure hot corners (top-left=Mission Control, top-right=Desktop, bottom-left=Screensaver)" \
  "Moving your cursor to a screen corner triggers an action:\n     • Top-left  → Mission Control\n     • Top-right → Show Desktop\n     • Bottom-left → Start Screensaver" \
  "optional" \
  "defaults write com.apple.dock wvous-tl-corner -int 2"; then
  do_run defaults write com.apple.dock wvous-tl-corner -int 2
  do_run defaults write com.apple.dock wvous-tl-modifier -int 0
  do_run defaults write com.apple.dock wvous-tr-corner -int 4
  do_run defaults write com.apple.dock wvous-tr-modifier -int 0
  do_run defaults write com.apple.dock wvous-bl-corner -int 5
  do_run defaults write com.apple.dock wvous-bl-modifier -int 0
  ok
fi

# ── Safari ─────────────────────────────────────────────────────────────────────

print_section "Safari"

if ask "Don't send search queries to Apple" \
  "Disables Safari's Universal Search from sending your keystrokes to Apple's servers as you type." \
  "recommended" \
  "defaults write com.apple.Safari UniversalSearchEnabled -bool false"; then
  do_run defaults write com.apple.Safari UniversalSearchEnabled -bool false
  do_run defaults write com.apple.Safari SuppressSearchSuggestions -bool true
  ok
fi

if ask "Tab key highlights all items on a webpage (not just text fields)" \
  "Allows Tab to cycle through every link, button, and input on the page." \
  "recommended" \
  "defaults write com.apple.Safari WebKitTabToLinksPreferenceKey -bool true"; then
  do_run defaults write com.apple.Safari WebKitTabToLinksPreferenceKey -bool true
  do_run defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks -bool true
  ok
fi

if ask "Show full URL in Safari address bar" \
  "Displays the complete URL including path instead of just the domain name." \
  "recommended" \
  "defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true"; then
  do_run defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
  ok
fi

if ask "Set Safari home page to 'about:blank' (blank page)" \
  "Opens a blank page for new windows/tabs instead of Top Sites, for a faster start." \
  "optional" \
  "defaults write com.apple.Safari HomePage -string \"about:blank\""; then
  do_run defaults write com.apple.Safari HomePage -string "about:blank"
  ok
fi

if ask "Don't auto-open downloaded files in Safari" \
  "Stops Safari from automatically opening 'safe' file types (PDFs, images, archives) after they finish downloading." \
  "recommended" \
  "defaults write com.apple.Safari AutoOpenSafeDownloads -bool false"; then
  do_run defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
  ok
fi

if ask "Enable Safari Develop menu and Web Inspector" \
  "Adds the Develop menu to Safari's menu bar, enabling the JS console, network inspector, and debugger." \
  "recommended" \
  "defaults write com.apple.Safari IncludeDevelopMenu -bool true"; then
  do_run defaults write com.apple.Safari IncludeDevelopMenu -bool true
  do_run defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  do_run defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
  do_run defaults write NSGlobalDomain WebKitDeveloperExtras -bool true
  ok
fi

if ask "Disable AutoFill in Safari (contacts, passwords, cards, forms)" \
  "Prevents Safari from auto-filling any form data. Improves privacy and avoids accidental data submission." \
  "recommended" \
  "defaults write com.apple.Safari AutoFillFromAddressBook -bool false"; then
  do_run defaults write com.apple.Safari AutoFillFromAddressBook -bool false
  do_run defaults write com.apple.Safari AutoFillPasswords -bool false
  do_run defaults write com.apple.Safari AutoFillCreditCardData -bool false
  do_run defaults write com.apple.Safari AutoFillMiscellaneousForms -bool false
  ok
fi

if ask "Enable fraudulent website warnings in Safari" \
  "Safari warns you before loading sites flagged as phishing or malware by Google Safe Browsing." \
  "recommended" \
  "defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true"; then
  do_run defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true
  ok
fi

if ask "Disable legacy browser plug-ins in Safari" \
  "Disables outdated plug-in support (e.g. Flash, Silverlight). No modern site requires them." \
  "recommended" \
  "defaults write com.apple.Safari WebKitPluginsEnabled -bool false"; then
  do_run defaults write com.apple.Safari WebKitPluginsEnabled -bool false
  do_run defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2PluginsEnabled -bool false
  ok
fi

if ask "Disable Java in Safari" \
  "Disables Java applet support in Safari. Java in browsers is a well-known security risk with no modern use case." \
  "recommended" \
  "defaults write com.apple.Safari WebKitJavaEnabled -bool false"; then
  do_run defaults write com.apple.Safari WebKitJavaEnabled -bool false
  do_run defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled -bool false
  do_run defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles -bool false
  ok
fi

if ask "Block JavaScript pop-up windows in Safari" \
  "Prevents websites from using JavaScript to open new browser windows or tabs." \
  "recommended" \
  "defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false"; then
  do_run defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
  do_run defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false
  ok
fi

if ask "Send 'Do Not Track' header in Safari" \
  "Adds the DNT HTTP header to every request, asking websites not to track your activity." \
  "recommended" \
  "defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true"; then
  do_run defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
  ok
fi

if ask "Auto-update Safari extensions" \
  "Keeps installed Safari extensions updated automatically in the background." \
  "recommended" \
  "defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true"; then
  do_run defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true
  ok
fi

# ── Mail ───────────────────────────────────────────────────────────────────────

print_section "Mail"

if ask "Disable send and reply animations in Mail" \
  "Removes the whoosh animation when composing and sending emails, making Mail feel more responsive." \
  "recommended" \
  "defaults write com.apple.mail DisableReplyAnimations -bool true"; then
  do_run defaults write com.apple.mail DisableReplyAnimations -bool true
  do_run defaults write com.apple.mail DisableSendAnimations -bool true
  ok
fi

if ask "Copy plain email address (no display name)" \
  "When copying an address in Mail, you get just the email (user@host.com) instead of 'Full Name <user@host.com>'." \
  "recommended" \
  "defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false"; then
  do_run defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false
  ok
fi

if ask "Add Cmd+Enter shortcut to send email in Mail" \
  "Maps Cmd+Return to the Send action in the Mail compose window." \
  "recommended" \
  "defaults write com.apple.mail NSUserKeyEquivalents -dict-add \"Send\" \"@\U21a9\""; then
  do_run defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" "@\U21a9"
  ok
fi

if ask "Show attachments as icons instead of inline previews" \
  "Displays email attachments as file icons rather than embedded images/PDFs, keeping messages less cluttered." \
  "optional" \
  "defaults write com.apple.mail DisableInlineAttachmentViewing -bool true"; then
  do_run defaults write com.apple.mail DisableInlineAttachmentViewing -bool true
  ok
fi

# ── Spotlight (user defaults) ─────────────────────────────────────────────────

print_section "Spotlight (search categories)"

if ask "Restrict Spotlight to developer-relevant categories only" \
  "Enables: Apps, System Prefs, Folders, PDFs, Fonts. Disables: Documents, Messages, Contacts, Images, Music, Movies, web suggestions, and more. Reduces noise, speeds up results." \
  "recommended" \
  "defaults write com.apple.spotlight orderedItems"; then
  do_run defaults write com.apple.spotlight orderedItems -array \
    '{"enabled" = 1;"name" = "APPLICATIONS";}' \
    '{"enabled" = 1;"name" = "SYSTEM_PREFS";}' \
    '{"enabled" = 1;"name" = "DIRECTORIES";}' \
    '{"enabled" = 1;"name" = "PDF";}' \
    '{"enabled" = 1;"name" = "FONTS";}' \
    '{"enabled" = 0;"name" = "DOCUMENTS";}' \
    '{"enabled" = 0;"name" = "MESSAGES";}' \
    '{"enabled" = 0;"name" = "CONTACT";}' \
    '{"enabled" = 0;"name" = "EVENT_TODO";}' \
    '{"enabled" = 0;"name" = "IMAGES";}' \
    '{"enabled" = 0;"name" = "BOOKMARKS";}' \
    '{"enabled" = 0;"name" = "MUSIC";}' \
    '{"enabled" = 0;"name" = "MOVIES";}' \
    '{"enabled" = 0;"name" = "PRESENTATIONS";}' \
    '{"enabled" = 0;"name" = "SPREADSHEETS";}' \
    '{"enabled" = 0;"name" = "SOURCE";}' \
    '{"enabled" = 0;"name" = "MENU_DEFINITION";}' \
    '{"enabled" = 0;"name" = "MENU_OTHER";}' \
    '{"enabled" = 0;"name" = "MENU_CONVERSION";}' \
    '{"enabled" = 0;"name" = "MENU_EXPRESSION";}' \
    '{"enabled" = 0;"name" = "MENU_WEBSEARCH";}' \
    '{"enabled" = 0;"name" = "MENU_SPOTLIGHT_SUGGESTIONS";}'
  killall mds > /dev/null 2>&1 || true
  ok
fi

# ── Terminal & iTerm2 ─────────────────────────────────────────────────────────

print_section "Terminal & iTerm2"

if ask "Force UTF-8 encoding in Terminal.app" \
  "Locks Terminal.app to UTF-8 only, preventing character display issues with non-ASCII output." \
  "recommended" \
  "defaults write com.apple.terminal StringEncodings -array 4"; then
  do_run defaults write com.apple.terminal StringEncodings -array 4
  ok
fi

if ask "Enable Secure Keyboard Entry in Terminal.app" \
  "Protects keystrokes in Terminal from being read by other apps — guards against keyloggers." \
  "recommended" \
  "defaults write com.apple.terminal SecureKeyboardEntry -bool true"; then
  do_run defaults write com.apple.terminal SecureKeyboardEntry -bool true
  ok
fi

if ask "Disable Terminal line marks" \
  "Removes the vertical line markers Terminal.app adds next to each command prompt line." \
  "recommended" \
  "defaults write com.apple.Terminal ShowLineMarks -int 0"; then
  do_run defaults write com.apple.Terminal ShowLineMarks -int 0
  ok
fi

if ask "Disable iTerm2 quit confirmation dialog" \
  "Removes the 'Quit iTerm2?' prompt, allowing iTerm2 to close immediately without confirmation." \
  "optional" \
  "defaults write com.googlecode.iterm2 PromptOnQuit -bool false"; then
  do_run defaults write com.googlecode.iterm2 PromptOnQuit -bool false
  ok
fi

# ── Time Machine ───────────────────────────────────────────────────────────────

print_section "Time Machine"

if ask "Don't prompt to use new external disks for Time Machine" \
  "Stops macOS from popping up 'Do you want to use this disk for Time Machine?' every time you plug in a drive." \
  "recommended" \
  "defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true"; then
  do_run defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
  ok
fi

# ── Activity Monitor ──────────────────────────────────────────────────────────

print_section "Activity Monitor"

if ask "Open the main window when Activity Monitor launches" \
  "Always shows the process list on startup instead of requiring you to open it manually." \
  "recommended" \
  "defaults write com.apple.ActivityMonitor OpenMainWindow -bool true"; then
  do_run defaults write com.apple.ActivityMonitor OpenMainWindow -bool true
  ok
fi

if ask "Show live CPU usage graph in Activity Monitor's Dock icon" \
  "The Activity Monitor icon in the Dock displays a real-time CPU usage chart." \
  "recommended" \
  "defaults write com.apple.ActivityMonitor IconType -int 5"; then
  do_run defaults write com.apple.ActivityMonitor IconType -int 5
  ok
fi

if ask "Show all processes in Activity Monitor (not just user processes)" \
  "Displays every system and user process, giving full visibility into what's running." \
  "recommended" \
  "defaults write com.apple.ActivityMonitor ShowCategory -int 0"; then
  do_run defaults write com.apple.ActivityMonitor ShowCategory -int 0
  ok
fi

if ask "Sort Activity Monitor by CPU usage (descending)" \
  "Puts the most CPU-hungry process at the top by default — great for spotting runaway processes." \
  "recommended" \
  "defaults write com.apple.ActivityMonitor SortColumn -string \"CPUUsage\""; then
  do_run defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
  do_run defaults write com.apple.ActivityMonitor SortDirection -int 0
  ok
fi

# ── TextEdit ───────────────────────────────────────────────────────────────────

print_section "TextEdit"

if ask "Default new TextEdit documents to plain text" \
  "New documents open as plain text (.txt) instead of rich text (.rtf). Much better for editing code, configs, and scripts." \
  "recommended" \
  "defaults write com.apple.TextEdit RichText -int 0"; then
  do_run defaults write com.apple.TextEdit RichText -int 0
  ok
fi

if ask "Read and write TextEdit plain text files as UTF-8" \
  "Sets UTF-8 as the default encoding for opening and saving plain text files in TextEdit." \
  "recommended" \
  "defaults write com.apple.TextEdit PlainTextEncoding -int 4"; then
  do_run defaults write com.apple.TextEdit PlainTextEncoding -int 4
  do_run defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
  ok
fi

# ── Mac App Store & Software Updates ─────────────────────────────────────────

print_section "Mac App Store & Software Updates"

if ask "Enable automatic update checks" \
  "Allows macOS to check for new software updates in the background." \
  "recommended" \
  "defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true"; then
  do_run defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
  ok
fi

if ask "Check for updates daily (not weekly)" \
  "Increases the update check frequency from once a week to once a day." \
  "recommended" \
  "defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1"; then
  do_run defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
  ok
fi

if ask "Auto-download available updates in the background" \
  "Silently downloads updates so they're ready to install immediately when you choose to." \
  "recommended" \
  "defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1"; then
  do_run defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1
  ok
fi

if ask "Automatically install system data files and security updates" \
  "Installs critical security patches and system data updates without user interaction." \
  "recommended" \
  "defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1"; then
  do_run defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
  ok
fi

if ask "Enable auto-update for App Store apps" \
  "Automatically updates apps purchased from the Mac App Store when new versions are available." \
  "recommended" \
  "defaults write com.apple.commerce AutoUpdate -bool true"; then
  do_run defaults write com.apple.commerce AutoUpdate -bool true
  ok
fi

# ── Photos ─────────────────────────────────────────────────────────────────────

print_section "Photos"

if ask "Don't auto-launch Photos when a device is plugged in" \
  "Prevents Photos.app from opening automatically when you connect an iPhone, camera, or SD card." \
  "recommended" \
  "defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true"; then
  do_run defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true
  ok
fi

# ── Messages ───────────────────────────────────────────────────────────────────

print_section "Messages"

if ask "Disable smart quotes in Messages" \
  "Keeps straight quotes in Messages — prevents broken code snippets and technical text." \
  "recommended" \
  "defaults write com.apple.messageshelper.MessageController SOInputLineSettings"; then
  do_run defaults write com.apple.messageshelper.MessageController SOInputLineSettings \
    -dict-add "automaticQuoteSubstitutionEnabled" -bool false
  ok
fi

if ask "Disable automatic emoji substitution in Messages" \
  "Stops Messages from converting text smileys (e.g. :) or :D) into emoji automatically." \
  "optional" \
  "defaults write com.apple.messageshelper.MessageController SOInputLineSettings"; then
  do_run defaults write com.apple.messageshelper.MessageController SOInputLineSettings \
    -dict-add "automaticEmojiSubstitutionEnablediMessage" -bool false
  ok
fi

# ── Google Chrome ──────────────────────────────────────────────────────────────

print_section "Google Chrome"

if ask "Disable trackpad back-swipe navigation in Chrome" \
  "Prevents accidental backward page navigation triggered by horizontal trackpad swipes." \
  "recommended" \
  "defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false"; then
  do_run defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
  do_run defaults write com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls -bool false
  ok
fi

if ask "Disable Magic Mouse back-swipe navigation in Chrome" \
  "Prevents accidental backward page navigation when scrolling horizontally on a Magic Mouse." \
  "recommended" \
  "defaults write com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls -bool false"; then
  do_run defaults write com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls -bool false
  do_run defaults write com.google.Chrome.canary AppleEnableMouseSwipeNavigateWithScrolls -bool false
  ok
fi

if ask "Use system print dialog in Chrome (disable Chrome's print preview)" \
  "Uses macOS's native print dialog instead of Chrome's custom preview panel." \
  "recommended" \
  "defaults write com.google.Chrome DisablePrintPreview -bool true"; then
  do_run defaults write com.google.Chrome DisablePrintPreview -bool true
  do_run defaults write com.google.Chrome.canary DisablePrintPreview -bool true
  ok
fi

if ask "Expand print dialog by default in Chrome" \
  "Opens Chrome's print dialog in its fully expanded state with all options visible." \
  "recommended" \
  "defaults write com.google.Chrome PMPrintingExpandedStateForPrint2 -bool true"; then
  do_run defaults write com.google.Chrome PMPrintingExpandedStateForPrint2 -bool true
  do_run defaults write com.google.Chrome.canary PMPrintingExpandedStateForPrint2 -bool true
  ok
fi

# ── Transmission ───────────────────────────────────────────────────────────────

print_section "Transmission (BitTorrent Client)"

if ask "Use ~/Documents/Torrents for incomplete downloads" \
  "Stores in-progress torrent downloads in a dedicated folder, separate from finished files." \
  "optional" \
  "defaults write org.m0k.transmission UseIncompleteDownloadFolder -bool true"; then
  do_run defaults write org.m0k.transmission UseIncompleteDownloadFolder -bool true
  do_run defaults write org.m0k.transmission IncompleteDownloadFolder -string "${HOME}/Documents/Torrents"
  ok
fi

if ask "Move completed downloads to ~/Downloads" \
  "Automatically moves finished torrent downloads to ~/Downloads." \
  "recommended" \
  "defaults write org.m0k.transmission DownloadLocationConstant -bool true"; then
  do_run defaults write org.m0k.transmission DownloadLocationConstant -bool true
  ok
fi

if ask "Enable and auto-update a peer IP blocklist" \
  "Blocks connections to known malicious or abusive peers using an auto-updating blocklist." \
  "recommended" \
  "defaults write org.m0k.transmission BlocklistNew -bool true"; then
  do_run defaults write org.m0k.transmission BlocklistNew -bool true
  do_run defaults write org.m0k.transmission BlocklistURL -string "http://john.bitsurge.net/public/biglist.p2p.gz"
  do_run defaults write org.m0k.transmission BlocklistAutoUpdate -bool true
  ok
fi

if ask "Randomize Transmission's port on each launch" \
  "Uses a random listening port each time Transmission starts, which can help avoid ISP throttling." \
  "recommended" \
  "defaults write org.m0k.transmission RandomPort -bool true"; then
  do_run defaults write org.m0k.transmission RandomPort -bool true
  ok
fi

# ══════════════════════════════════════════════════════════════════════════════
#  Wrap-up — restart affected apps
# ══════════════════════════════════════════════════════════════════════════════

print_section "Summary"
printf "\n  ${SUCCESS}Applied : %d setting(s)${RESET}\n" "$APPLIED"
printf "  ${MUTED}Skipped : %d setting(s)${RESET}\n" "$SKIPPED"

if [[ -n "$SAVE_CHOICES_FILE" ]]; then
  save_choices_file "$SAVE_CHOICES_FILE"
fi

if [[ "$APPLIED" -gt 0 && "$DRY_RUN" -eq 0 ]]; then
  printf "\n${WARN}⚠ WARN  Restarting affected applications to pick up new settings...${RESET}\n"
  for app in \
    "Activity Monitor" \
    "cfprefsd" \
    "Dock" \
    "Finder" \
    "Mail" \
    "Messages" \
    "Photos" \
    "Safari" \
    "SystemUIServer" \
    "Terminal"; do
    killall "${app}" &>/dev/null && printf "  ${MUTED}↺  %s${RESET}\n" "$app"
  done
  printf "\n${SUCCESS}✓ OK    Done. Note: some changes require a logout or full restart to take effect.${RESET}\n"
elif [[ "$DRY_RUN" -eq 1 ]]; then
  printf "\n${INFO}ℹ INFO  Dry-run complete. No changes were written.${RESET}\n"
else
  printf "\n${SUCCESS}✓ OK    No settings were applied.${RESET}\n"
fi
