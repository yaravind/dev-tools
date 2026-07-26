#!/bin/zsh

# This script is designed to automate the installation and configuration of some
# commonly used developer tools on macOS (Apple Silicon and Intel)

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

# Reuse the shared branding palette so log colors stay consistent with the banner.
INFO="${EBK_INFO_COLOR}"
ACTION="${EBK_INFO_COLOR}"
SUCCESS="${EBK_OK_COLOR}"
WARN="${EBK_WARN_COLOR}"
ERROR="${EBK_ERROR_COLOR}"
SECTION="${EBK_PHASE_COLOR}"
MUTED="${EBK_MUTED}"
RESET="${EBK_RESET}"
SCRIPT_NAME="${0:A:t}"

log_phase() {
  local phase="$1"
  local detail="$2"
  ebk_log_phase "$phase"
  ebk_log_info "$detail"
}

print_usage() {
  echo -e "${INFO}Usage: ${SCRIPT_NAME} MODE [--dry-run]${RESET}"
  echo -e "${INFO}Modes:${RESET}"
  echo -e "${INFO}  --classify-only   Inspect Homebrew metadata and dry-run installs; make no changes.${RESET}"
  echo -e "${INFO}  --non-admin-only  Install formulae and user-space casks only.${RESET}"
  echo -e "${INFO}  --admin-only      Install admin-likely casks only.${RESET}"
  echo -e "${INFO}Optional:${RESET}"
  echo -e "${INFO}  --dry-run, -n     Show planned actions for the selected mode without making changes.${RESET}"
}

# Parse args
DRY_RUN=0
RUN_MODE=""
for arg in "$@"; do
  case "$arg" in
    --classify-only|--non-admin-only|--admin-only)
      if [[ -n "$RUN_MODE" ]]; then
        echo -e "${ERROR}✖ ERROR Specify only one mode.${RESET}"
        print_usage
        exit 1
      fi
      RUN_MODE="$arg"
      ;;
    --dryRun|--dryrun|--dry-run|-n)
      DRY_RUN=1
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      echo -e "${ERROR}✖ ERROR Unknown argument: ${arg}${RESET}"
      print_usage
      exit 1
      ;;
  esac
done

if [[ -z "$RUN_MODE" ]]; then
  echo -e "${ERROR}✖ ERROR Missing required mode.${RESET}"
  print_usage
  exit 1
fi

SCRIPT_START_SECONDS=$SECONDS

# List of Homebrew formulae to be installed. These should not require admin
# privileges when Homebrew is owned by the installing user.
formulae=(
  "python@3.13"
  "rust"
  "direnv"      # Load and unload environment variables (in .envrc) depending on the current directory
  "pipx"        # Needed to install poetry
  "uv"          # Extremely fast Python package installer and resolver, written in Rust
  "htop"        # Improved top (interactive process viewer)
  "tree"        # Display directories as trees (with optional color/HTML output)
  "jq"          # Lightweight and flexible command-line JSON processor
  "gh"          # GitHub command-line tool
  "azure-cli"
  "tlrc"        # Rust client for tldr pages; replacement for deprecated tldr formula
  "eza"         # Eza is a modern replacement for the ls command
  "trash"       # Moves files to the trash, which is safer because it is reversible
  "jenv"        # Manage multiple versions of Java
  "bat"         # Clone of cat(1) with syntax highlighting and Git integration
  "thefuck"     # Programmatically correct last mistyped console command
  "node"        # cross-platform JavaScript runtime environment that lets developers create servers, web apps, command line tools and scripts
  "pandoc"      # Swiss-army knife of markup format conversion.
  "llm"         # A CLI utility and Python library for interacting with Large Language Models. https://llm.datasette.io/en/stable/index.html
  "lnav"        # A robust log colorizer to tail logs:   tail -f your_log_file.log | ccze -A
  "powershell"  # PowerShell for Mac
  #"hugo"        # Configurable fastest static site generator
  "graphviz"    # Convert dot files to images
  "ripgrep"     # ripgrep recursively searches directories for a regex pattern while respecting your gitignore rules
  "dockutil"     # Command line tool for manipulating macOS Dock items to natively talk to Microsoft SQL Server and Sybase databases
  "duti"         # Set default applications for file types and URL schemes via UTI mappings
  "maven"        # Apache Maven build tool
  "pure"         # Pretty, minimal and fast Zsh prompt (sindresorhus/pure)
  "antidote"     # Fast Zsh plugin manager used by zsh_plugins_setup.sh
)

# Casks expected to install as user-space GUI apps. These are installed into
# ~/Applications to avoid writing into system-wide /Applications.
user_casks=(
  #"appcleaner"                # Allows you to thoroughly uninstall unwanted apps.
  "intellij-idea"             # Use intellij-idea for Ultimate Edition
  "pycharm"                   # Use pycharm for Ultimate Edition
  "visual-studio-code"        # VS Code
  "copilot-cli"               # Brings the power of Copilot coding agent directly to your terminal
  "agent-sessions"            # Menu bar app for managing local agent sessions
  #"font-3270-nerd-font"       # Modern fonts to show icons etc
  #"font-anonymice-nerd-font"
  #"font-code-new-roman-nerd-font"
  #"font-fira-code-nerd-font"
  #"font-jetbrains-mono-nerd-font"
  #"microsoft-azure-storage-explorer"
  "drawio"                    # Online diagram software
  "tolaria"                   # Tolaria - markdown-first note app (https://tolaria.md/)
  "dbeaver-community"         # Free Universal Database Tool
  "zed"                       # Multiplayer code editor
  "ollama"                    # Manage Local LLMs
  #"protege"                   # OWL for ontologies and knowledge graph
  #"bunch"                     # Automate tasks on your Mac
  #"alt-tab"                   # Alt-Tab is a window switcher for Mac
  #"hovrly"                    # Display and convert timezones time in different cities
  #"aldente"                   # Menu bar tool to limit maximum charging percentage
  #"maccy"                     # Clipboard manager
  #"bruno"                     # open-source desktop alternative to Postman. saved to filesystem. use markup
  #"fsnotes"                   # Note taking app with markdown support
  #"go2shell"                 # Deprecated, Intel-only on Apple Silicon, and requires Rosetta 2
  "rancher"                   # Kubernetes and container management on the desktop
  #"tad"                       # TAD is a free and open-source data analysis tool for tabular data
  "stats"                     # Stats is a menu bar app that shows your Mac's CPU, GPU, Memory, Disk, Network, Sensors and Battery stats   
)

# Casks that commonly use pkg installers, privileged helpers, drivers, daemons,
# or system-wide install locations. These are installed after user-space tools.
admin_casks=(
  "microsoft-openjdk@11"      # For Fabric Runtime 1.3
  "microsoft-openjdk@21"      # For Apache Jena 5.4.x
  "dotnet-sdk"                # Needed to run different VS Code plugins related to Fabric and Synapse
  "git-credential-manager"    # Cross-platform Git credential storage for multiple hosting providers
  "logi-options+"             # Software for Logitech WebCam
)

if [ "$DRY_RUN" -eq 1 ]; then
  printf "${SECTION}◆ PHASE DryRun: Planned actions (no changes will be made)${RESET}\n"
  printf "${INFO}  - Mode: %s${RESET}\n" "$RUN_MODE"

  case "$RUN_MODE" in
    --classify-only)
      printf "${INFO}  - Ensure Homebrew is available${RESET}\n"
      printf "${INFO}  - Inspect formula metadata and dry-run installs: %s${RESET}\n" "${formulae[*]}"
      printf "${INFO}  - Inspect user-space cask metadata and dry-run installs: %s${RESET}\n" "${user_casks[*]}"
      printf "${INFO}  - Inspect admin-likely cask metadata and dry-run installs: %s${RESET}\n" "${admin_casks[*]}"
      ;;
    --non-admin-only)
      printf "${INFO}  - Ensure Homebrew is available from the pre_setup.sh install and update it${RESET}\n"
      printf "${INFO}  - Ensure the jazzyalex/agent-sessions tap is available for agent-sessions${RESET}\n"
      printf "${INFO}  - Install formulae: %s${RESET}\n" "${formulae[*]}"
      printf "${INFO}  - Install user-space casks into ~/Applications: %s${RESET}\n" "${user_casks[*]}"
      printf "${INFO}  - Configure non-admin shell hooks, aliases, and verify non-admin installs${RESET}\n"
      ;;
    --admin-only)
      printf "${INFO}  - Ensure Homebrew is available from the pre_setup.sh install and update it${RESET}\n"
      printf "${INFO}  - Install admin-likely casks: %s${RESET}\n" "${admin_casks[*]}"
      printf "${INFO}  - Verify admin-likely installs only${RESET}\n"
      ;;
  esac

  exit 0
fi

failed_formulae=()
failed_user_casks=()
failed_admin_casks=()
admin_privilege_failures=()
classification_warnings=()
skipped_formulae=()
homebrew_warning_count=0
installed_formula_names_cache=$'\n'
formula_cache_loaded=0

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

default_homebrew_prefix() {
  case "$(uname -m)" in
    arm64)
      printf '/opt/homebrew\n'
      ;;
    x86_64)
      printf '/usr/local\n'
      ;;
    *)
      printf '/opt/homebrew\n'
      ;;
  esac
}

# Function to make sure Homebrew was prepared by pre_setup.sh
ensure_homebrew_available() {
  local expected_prefix
  local brew_prefix
  expected_prefix="$(default_homebrew_prefix)"

  if ! command_exists brew && [[ -x "${expected_prefix}/bin/brew" ]]; then
    echo -e "${ACTION}ℹ INFO  Loading Homebrew from ${expected_prefix} into this shell...${RESET}"
    eval "$("${expected_prefix}/bin/brew" shellenv zsh)"
  fi

  if ! command_exists brew; then
    echo -e "${ERROR}✖ ERROR Homebrew not found. Run pre_setup.sh first, then re-run setup_env.sh.${RESET}"
    exit 1
  fi

  brew_prefix="$(brew --prefix 2>/dev/null)"
  if [[ "$brew_prefix" == "/opt/homebrew" && -d "$brew_prefix" && "$(stat -f '%Su' "$brew_prefix")" != "$USER" ]]; then
    echo -e "${WARN}⚠ WARN  ${brew_prefix} is not owned by ${USER}; Homebrew installs may fail with permission errors.${RESET}"
  fi
}

quiet_homebrew_hints() {
  export HOMEBREW_NO_AUTO_UPDATE=1
  export HOMEBREW_NO_ENV_HINTS=1
  export HOMEBREW_NO_INSTALL_CLEANUP=1
}

array_contains() {
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

record_homebrew_warning() {
  local warning_text="$1"
  homebrew_warning_count=$((homebrew_warning_count + 1))
  echo -e "${WARN}⚠ WARN  ${warning_text}${RESET}"
}

print_normalized_output() {
  local line
  while IFS= read -r line; do
    if [[ "$line" == Warning:* ]]; then
      record_homebrew_warning "${line#Warning: }"
    elif [[ "$line" == warning:* ]]; then
      record_homebrew_warning "${line#warning: }"
    else
      printf '%s\n' "$line"
    fi
  done
}

print_command_output() {
  local output="$1"
  if [[ -z "$output" ]]; then
    return 0
  fi
  print_normalized_output <<< "$output"
}

load_installed_formula_cache() {
  local output
  local line

  installed_formula_names_cache=$'\n'
  output="$(brew list --formula 2>&1)"
  while IFS= read -r line; do
    if [[ "$line" == Warning:* ]]; then
      record_homebrew_warning "${line#Warning: }"
      continue
    elif [[ "$line" == warning:* ]]; then
      record_homebrew_warning "${line#warning: }"
      continue
    fi

    [[ -z "$line" ]] && continue
    installed_formula_names_cache+="${line}"$'\n'
  done <<< "$output"

  formula_cache_loaded=1
}

formula_is_installed_cached() {
  local formula="$1"
  [[ "$formula_cache_loaded" -eq 1 ]] || load_installed_formula_cache
  [[ "$installed_formula_names_cache" == *$'\n'"$formula"$'\n'* ]]
}

ensure_agent_sessions_tap() {
  if ! array_contains "agent-sessions" "${user_casks[@]}"; then
    return 0
  fi

  echo -e "${INFO}ℹ INFO  Ensuring Homebrew tap 'jazzyalex/agent-sessions' is available for agent-sessions...${RESET}"

  if ! brew tap | grep -q '^jazzyalex/agent-sessions$'; then
    echo -e "${ACTION}ℹ INFO  Tapping jazzyalex/agent-sessions...${RESET}"
    if ! brew tap jazzyalex/agent-sessions; then
      echo -e "${ERROR}✖ ERROR Failed to tap jazzyalex/agent-sessions.${RESET}"
      failed_user_casks+=("agent-sessions")
      return 1
    fi
  fi

  if brew help trust >/dev/null 2>&1; then
    echo -e "${INFO}ℹ INFO  Trusting agent-sessions cask from jazzyalex/agent-sessions...${RESET}"
    brew trust --cask jazzyalex/agent-sessions/agent-sessions >/dev/null 2>&1 || true
  fi
}

precheck_formula_metadata() {
  local formula="$1"
  echo -e "${INFO}ℹ INFO  Checking Homebrew metadata for formula: ${formula}...${RESET}"

  if brew info --json=v2 "$formula" >/dev/null 2>&1; then
    return 0
  fi

  echo -e "${ERROR}✖ ERROR Missing or unreadable Homebrew metadata for formula: ${formula}${RESET}"
  return 1
}

precheck_cask_metadata() {
  local cask="$1"
  echo -e "${INFO}ℹ INFO  Checking Homebrew metadata for cask: ${cask}...${RESET}"

  if brew info --json=v2 --cask "$cask" >/dev/null 2>&1; then
    return 0
  fi

  echo -e "${ERROR}✖ ERROR Missing or unreadable Homebrew metadata for cask: ${cask}${RESET}"
  return 1
}

cask_metadata_looks_admin_required() {
  local cask="$1"
  local metadata

  metadata="$(brew info --json=v2 --cask "$cask" 2>/dev/null)" || return 2

  if printf '%s' "$metadata" | grep -Eq '"pkg"|"installer"|"launchdaemon"|"preflight"|"postflight"|"uninstall_preflight"|"uninstall_postflight"'; then
    return 0
  fi

  return 1
}

is_confirmed_user_space_cask() {
  local cask="$1"

  case "$cask" in
    intellij-idea|pycharm|drawio)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

looks_like_admin_failure() {
  local output="$1"

  if printf '%s' "$output" | grep -Eiq 'sudo|admin|administrator|authentication|permission denied|operation not permitted|not writable|requires.*privilege|privileged|installer'; then
    return 0
  fi

  return 1
}

homebrew_formula_owns_path() {
  local formula="$1"
  local path="$2"
  local owned_path

  while IFS= read -r owned_path; do
    if [[ "$owned_path" == "$path" ]]; then
      return 0
    fi
  done < <(brew list --formula "$formula" 2>/dev/null)

  return 1
}

dotnet_command_conflicts_with_formula() {
  local brew_prefix
  local dotnet_path

  brew_prefix="$(brew --prefix 2>/dev/null)" || return 1
  dotnet_path="${brew_prefix}/bin/dotnet"

  [[ -e "$dotnet_path" || -L "$dotnet_path" ]] || return 1
  homebrew_formula_owns_path "dotnet" "$dotnet_path" && return 1

  return 0
}

should_skip_formula_install() {
  local formula="$1"

  if [[ "$formula" == "powershell" ]] && dotnet_command_conflicts_with_formula; then
    echo -e "${WARN}⚠ WARN  Skipping powershell: brew-linked dotnet exists but is not owned by the Homebrew dotnet formula.${RESET}"
    echo -e "${WARN}⚠ WARN  Choose either Homebrew formula dotnet + powershell, or the admin dotnet-sdk cask without automated PowerShell.${RESET}"
    skipped_formulae+=("powershell: dotnet command conflict")
    return 0
  fi

  return 1
}

install_formula() {
  local formula="$1"
  local output
  local exit_status

  if formula_is_installed_cached "$formula"; then
    echo -e "${SUCCESS}✓ OK    Formula already installed: ${formula}${RESET}"
    return 0
  fi

  if ! precheck_formula_metadata "$formula"; then
    failed_formulae+=("$formula")
    return 1
  fi

  if should_skip_formula_install "$formula"; then
    return 0
  fi

  echo -e "${ACTION}ℹ INFO  Installing formula: ${formula}...${RESET}"

  output="$(brew install "$formula" 2>&1)"
  exit_status=$?
  print_command_output "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    installed_formula_names_cache+="${formula}"$'\n'
    echo -e "${SUCCESS}✓ OK    Installed formula: ${formula}${RESET}"
    return 0
  fi

  echo -e "${ERROR}✖ ERROR Failed to install formula: ${formula}${RESET}"
  failed_formulae+=("$formula")

  if looks_like_admin_failure "$output"; then
    admin_privilege_failures+=("formula:${formula}")
  fi

  return "$exit_status"
}

install_user_cask() {
  local cask="$1"
  local output
  local exit_status

  if ! precheck_cask_metadata "$cask"; then
    failed_user_casks+=("$cask")
    return 1
  fi

  if cask_metadata_looks_admin_required "$cask" && ! is_confirmed_user_space_cask "$cask"; then
    echo -e "${WARN}⚠ WARN  Cask metadata looks admin-likely; attempting user-space install before reclassifying: ${cask}${RESET}"
  fi

  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo -e "${SUCCESS}✓ OK    Cask already installed: ${cask}${RESET}"
    return 0
  fi

  mkdir -p "$HOME/Applications"

  echo -e "${ACTION}ℹ INFO  Installing user-space cask: ${cask}...${RESET}"
  output="$(brew install --cask --appdir="$HOME/Applications" "$cask" 2>&1)"
  exit_status=$?
  print_command_output "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}✓ OK    Installed user-space cask: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ERROR}✖ ERROR Failed to install user-space cask: ${cask}${RESET}"
  failed_user_casks+=("$cask")

  if looks_like_admin_failure "$output"; then
    admin_privilege_failures+=("user_casks:${cask}")
    classification_warnings+=("user_casks:${cask}")
  fi

  return "$exit_status"
}

install_admin_cask() {
  local cask="$1"
  local output
  local exit_status

  if ! precheck_cask_metadata "$cask"; then
    failed_admin_casks+=("$cask")
    return 1
  fi

  if ! cask_metadata_looks_admin_required "$cask"; then
    echo -e "${WARN}⚠ WARN  Cask metadata does not look admin-required; consider moving to user_casks: ${cask}${RESET}"
    classification_warnings+=("admin_casks:${cask}")
  fi

  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo -e "${SUCCESS}✓ OK    Cask already installed: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ACTION}ℹ INFO  Installing admin-likely cask: ${cask}...${RESET}"
  output="$(brew install --cask "$cask" 2>&1)"
  exit_status=$?
  print_command_output "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}✓ OK    Installed admin-likely cask: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ERROR}✖ ERROR Failed to install admin-likely cask: ${cask}${RESET}"
  failed_admin_casks+=("$cask")

  if looks_like_admin_failure "$output"; then
    admin_privilege_failures+=("admin_casks:${cask}")
  fi

  return "$exit_status"
}

classify_formula() {
  local formula="$1"
  local output
  local exit_status

  if ! precheck_formula_metadata "$formula"; then
    failed_formulae+=("$formula")
    return 1
  fi

  echo -e "${ACTION}ℹ INFO  Dry-run formula install: ${formula}...${RESET}"

  output="$(brew install --dry-run "$formula" 2>&1)"
  exit_status=$?
  print_command_output "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}✓ OK    Formula dry-run passed: ${formula}${RESET}"
    return 0
  fi

  echo -e "${ERROR}✖ ERROR Formula dry-run failed: ${formula}${RESET}"
  failed_formulae+=("$formula")

  if looks_like_admin_failure "$output"; then
    admin_privilege_failures+=("formula:${formula}")
  fi

  return "$exit_status"
}

classify_user_cask() {
  local cask="$1"
  local output
  local exit_status

  if ! precheck_cask_metadata "$cask"; then
    failed_user_casks+=("$cask")
    return 1
  fi

  if cask_metadata_looks_admin_required "$cask"; then
    echo -e "${WARN}⚠ WARN  Cask metadata looks admin-required; consider moving out of user_casks: ${cask}${RESET}"
    classification_warnings+=("user_casks:${cask}")
  else
    echo -e "${SUCCESS}✓ OK    Cask metadata looks user-space friendly: ${cask}${RESET}"
  fi

  echo -e "${ACTION}ℹ INFO  Dry-run user-space cask install: ${cask}...${RESET}"
  output="$(brew install --cask --dry-run --appdir="$HOME/Applications" "$cask" 2>&1)"
  exit_status=$?
  print_command_output "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}✓ OK    User-space cask dry-run passed: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ERROR}✖ ERROR User-space cask dry-run failed: ${cask}${RESET}"
  failed_user_casks+=("$cask")

  if looks_like_admin_failure "$output"; then
    admin_privilege_failures+=("user_casks:${cask}")
  fi

  return "$exit_status"
}

classify_admin_cask() {
  local cask="$1"
  local output
  local exit_status

  if ! precheck_cask_metadata "$cask"; then
    failed_admin_casks+=("$cask")
    return 1
  fi

  if cask_metadata_looks_admin_required "$cask"; then
    echo -e "${SUCCESS}✓ OK    Cask metadata looks admin-likely: ${cask}${RESET}"
  else
    echo -e "${WARN}⚠ WARN  Cask metadata does not look admin-required; consider moving to user_casks: ${cask}${RESET}"
    classification_warnings+=("admin_casks:${cask}")
  fi

  echo -e "${ACTION}ℹ INFO  Dry-run admin-likely cask install: ${cask}...${RESET}"
  output="$(brew install --cask --dry-run "$cask" 2>&1)"
  exit_status=$?
  print_command_output "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}✓ OK    Admin-likely cask dry-run passed: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ERROR}✖ ERROR Admin-likely cask dry-run failed: ${cask}${RESET}"
  failed_admin_casks+=("$cask")

  if looks_like_admin_failure "$output"; then
    admin_privilege_failures+=("admin_casks:${cask}")
  fi

  return "$exit_status"
}

print_items() {
  local color="$1"
  shift

  for item in "$@"; do
    echo -e "${color}  - ${item}${RESET}"
  done
}

format_duration() {
  local total_seconds="$1"
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  if [[ "$hours" -gt 0 ]]; then
    printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
  elif [[ "$minutes" -gt 0 ]]; then
    printf "%dm %ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}

print_elapsed_time() {
  local elapsed_seconds=$((SECONDS - SCRIPT_START_SECONDS))

  echo -e "${INFO}ℹ INFO  Duration: $(format_duration "$elapsed_seconds")${RESET}"
}

print_classification_suggestions() {
  local warning
  local bucket
  local package

  for warning in "$@"; do
    bucket="${warning%%:*}"
    package="${warning#*:}"

    case "$bucket" in
      user_casks)
        echo -e "${WARN}  - ${package}: currently in user_casks, but metadata looks admin-required. Move to admin_casks.${RESET}"
        ;;
      admin_casks)
        echo -e "${WARN}  - ${package}: currently in admin_casks, but metadata looks user-space friendly. Consider moving to user_casks.${RESET}"
        ;;
      *)
        echo -e "${WARN}  - ${warning}${RESET}"
        ;;
    esac
  done
}

print_install_summary() {
  local status_label="SUCCESS"
  local status_icon="✔"
  local status_color="${SUCCESS}"
  local elapsed_seconds=$((SECONDS - SCRIPT_START_SECONDS))
  local total_failures=$(( ${#failed_formulae[@]} + ${#failed_user_casks[@]} + ${#failed_admin_casks[@]} ))
  local total_signals=$(( ${#admin_privilege_failures[@]} + ${#classification_warnings[@]} + ${#skipped_formulae[@]} + homebrew_warning_count ))

  if (( total_failures > 0 )); then
    status_label="COMPLETED WITH ISSUES"
    status_icon="⚠"
    status_color="${WARN}"
  fi

  echo
  echo -e "${SECTION}Final Status Report${RESET}"
  echo -e "${SECTION}──────────────────────────────────────────────────────────────────────────────${RESET}"
  printf '  %-24s %s\n' "Script" "Environment Setup (macOS)"
  printf '  %-24s %s\n' "Mode" "${RUN_MODE}"
  printf "  %-24s ${status_color}%s %s${RESET}\n" "Status" "${status_icon}" "${status_label}"
  echo -e "${SECTION}──────────────────────────────────────────────────────────────────────────────${RESET}"
  printf '  %-24s %d\n' "Formula entries" "${#formulae[@]}"
  printf '  %-24s %d\n' "User cask entries" "${#user_casks[@]}"
  printf '  %-24s %d\n' "Admin cask entries" "${#admin_casks[@]}"
  printf '  %-24s %d\n' "Failure count" "${total_failures}"
  printf '  %-24s %d\n' "Warning/signal count" "${total_signals}"
  printf '  %-24s %s\n' "Duration" "$(format_duration "$elapsed_seconds")"
  echo -e "${SECTION}──────────────────────────────────────────────────────────────────────────────${RESET}"

  if (( total_failures == 0 )); then
    echo -e "${SUCCESS}No install/classification failures recorded.${RESET}"
  else
    echo -e "${ERROR}Failures${RESET}"
    if [[ "${#failed_formulae[@]}" -gt 0 ]]; then
      echo -e "${ERROR}Formulae:${RESET}"
      print_items "$ERROR" "${failed_formulae[@]}"
    fi
    if [[ "${#failed_user_casks[@]}" -gt 0 ]]; then
      echo -e "${ERROR}User-space casks:${RESET}"
      print_items "$ERROR" "${failed_user_casks[@]}"
    fi
    if [[ "${#failed_admin_casks[@]}" -gt 0 ]]; then
      echo -e "${ERROR}Admin-likely casks:${RESET}"
      print_items "$ERROR" "${failed_admin_casks[@]}"
    fi
  fi

  if [[ "${#admin_privilege_failures[@]}" -gt 0 ]]; then
    echo
    echo -e "${WARN}Admin/permission signals${RESET}"
    print_items "$WARN" "${admin_privilege_failures[@]}"
  fi

  if [[ "${#skipped_formulae[@]}" -gt 0 ]]; then
    echo
    echo -e "${WARN}Skipped formulae${RESET}"
    print_items "$WARN" "${skipped_formulae[@]}"
  fi

  if (( homebrew_warning_count > 0 )); then
    echo
    echo -e "${WARN}Homebrew warnings observed: ${homebrew_warning_count}${RESET}"
  fi

  if [[ "${#classification_warnings[@]}" -gt 0 ]]; then
    echo
    echo -e "${WARN}Suggested package moves${RESET}"
    print_classification_suggestions "${classification_warnings[@]}"
  fi

  echo
  echo -e "${SECTION}Next Steps${RESET}"
  if (( total_failures > 0 )); then
    echo "  Review failed installs above and rerun the matching mode."
  elif (( total_signals > 0 )); then
    echo "  Review warning/signal entries above for optional cleanup."
  else
    echo "  No follow-up action required."
  fi
}

# Function to set environment variables
set_env_vars() {
  echo -e "${SECTION}◆ PHASE Start setting ENV VARs${RESET}"
  if [[ -z "${JAVA_HOME}" ]]; then
    echo -e "${INFO}ℹ INFO  Adding JAVA_HOME env variable to .zshrc...${RESET}"
    echo "# brew_install_apps.sh - Appending JAVA_HOME env var" >>~/.zshrc
    echo "export JAVA_HOME=$(/usr/libexec/java_home)" >>~/.zshrc
  else
    echo -e "${INFO}ℹ INFO  JAVA_HOME is already set to: ${JAVA_HOME}${RESET}"
  fi

  echo -e "${ACTION}ℹ INFO  Source .zshrc...${RESET}"
  echo 'export PATH="$HOME/.jenv/bin:$PATH"' >>~/.zshrc
  echo 'eval "$(jenv init -)"' >>~/.zshrc

  source "$HOME/.zshrc"
}

print_brew_versions() {
  local package_type="$1"
  shift

  local bulk_output
  if [[ "$package_type" == "cask" ]]; then
    bulk_output="$(brew list --cask --versions 2>&1)"
  else
    bulk_output="$(brew list --formula --versions 2>&1)"
  fi

  local line
  local cleaned_output=''
  while IFS= read -r line; do
    if [[ "$line" == Warning:* ]]; then
      echo -e "${WARN}⚠ WARN  ${line#Warning: }${RESET}"
      continue
    fi

    [[ -z "$line" ]] && continue
    cleaned_output+="${line}"$'\n'
  done <<< "$bulk_output"

  local package
  local found_line
  for package in "$@"; do
    found_line=''
    while IFS= read -r line; do
      if [[ "$line" == "${package} "* ]]; then
        found_line="$line"
        break
      fi
    done <<< "$cleaned_output"

    if [[ -n "$found_line" ]]; then
      printf '%s\n' "$found_line"
    else
      echo -e "${WARN}  - ${package}: not installed${RESET}"
    fi
  done
}

alias_exists_in_zshrc() {
  local alias_name="$1"
  local zshrc="$HOME/.zshrc"

  [[ -f "$zshrc" ]] || return 1

  awk -v alias_name="$alias_name" '
    /^[[:space:]]*#/ { next }
    $1 == "alias" && $2 ~ ("^" alias_name "=") { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$zshrc"
}

add_alias_if_missing() {
  local alias_name="$1"
  local alias_value="$2"
  local zshrc="$HOME/.zshrc"

  touch "$zshrc"

  if alias_exists_in_zshrc "$alias_name"; then
    echo -e "${INFO}ℹ INFO  Alias ${alias_name} already exists in ~/.zshrc; leaving it unchanged.${RESET}"
    return 0
  fi

  echo -e "${INFO}ℹ INFO  Adding alias ${alias_name}='${alias_value}' to ~/.zshrc...${RESET}"
  echo "alias ${alias_name}='${alias_value}'" >> "$zshrc"
}

configure_non_admin_aliases() {
  if command_exists trash; then
    add_alias_if_missing "rm" "trash"
  else
    echo -e "${WARN}⚠ WARN  trash is not available; skipping rm alias.${RESET}"
  fi

  if command_exists bat; then
    add_alias_if_missing "cat" "bat"
  else
    echo -e "${WARN}⚠ WARN  bat is not available; skipping cat alias.${RESET}"
  fi
}

# Function to verify non-admin installations
verify_non_admin_installations() {
  echo -e "${SECTION}◆ PHASE Start verification${RESET}"
  echo -e "${INFO}ℹ INFO  Installed formulae managed by --non-admin-only...${RESET}"
  print_brew_versions "formula" "${formulae[@]}"

  echo -e "${INFO}ℹ INFO  Installed user-space casks managed by --non-admin-only...${RESET}"
  print_brew_versions "cask" "${user_casks[@]}"

  echo -e "${INFO}ℹ INFO  Verify Python...${RESET}"
  local python_313_bin
  python_313_bin="$(brew --prefix python@3.13 2>/dev/null)/bin/python3.13"

  if [[ -x "$python_313_bin" ]]; then
    echo "$python_313_bin"
    "$python_313_bin" -V
  else
    echo -e "${WARN}⚠ WARN  python@3.13 executable not found.${RESET}"
  fi

  echo -e "${INFO}ℹ INFO  Verify Maven...${RESET}"
  if command_exists mvn; then
    which -a mvn
    echo -e "${SUCCESS}✓ OK    Maven command is available.${RESET}"
  else
    echo -e "${WARN}⚠ WARN  mvn not found in PATH.${RESET}"
  fi

  configure_non_admin_aliases
}

# Function to verify admin-likely installations
verify_admin_installations() {
  echo -e "${SECTION}◆ PHASE Start verification${RESET}"
  echo -e "${INFO}ℹ INFO  Installed casks managed by --admin-only...${RESET}"
  print_brew_versions "cask" "${admin_casks[@]}"

  echo -e "${INFO}ℹ INFO  Verify Java...${RESET}"
  if command_exists java; then
    java -version
  else
    echo -e "${WARN}⚠ WARN  java not found in PATH.${RESET}"
  fi

  echo -e "${INFO}ℹ INFO  Verify .NET...${RESET}"
  if command_exists dotnet; then
    dotnet --version
  else
    echo -e "${WARN}⚠ WARN  dotnet not found in PATH.${RESET}"
  fi

  echo -e "${INFO}ℹ INFO  Verify Git Credential Manager...${RESET}"
  if command_exists git-credential-manager; then
    git-credential-manager --version
  else
    echo -e "${WARN}⚠ WARN  git-credential-manager not found in PATH.${RESET}"
  fi
}

configure_direnv_hook() {
  if command_exists direnv; then
    if ! grep -qxF 'eval "$(direnv hook zsh)"' "$HOME/.zshrc" 2>/dev/null; then
      echo -e "${INFO}ℹ INFO  Adding direnv hook to ~/.zshrc...${RESET}"
      echo "# direnv: load environment variables per-directory" >> "$HOME/.zshrc"
      echo 'eval "$(direnv hook zsh)"' >> "$HOME/.zshrc"
    else
      echo -e "${INFO}ℹ INFO  direnv hook already present in ~/.zshrc${RESET}"
    fi
  else
    echo -e "${WARN}⚠ WARN  direnv not installed; skipping ~/.zshrc hook setup.${RESET}"
  fi
}

configure_pure_prompt() {
  if ! command_exists brew || [[ ! -d "$(brew --prefix)/share/zsh/site-functions" ]]; then
    echo -e "${WARN}⚠ WARN  pure not found in Homebrew site-functions; skipping ~/.zshrc prompt setup.${RESET}"
    return
  fi

  if grep -qxF 'prompt pure' "$HOME/.zshrc" 2>/dev/null; then
    echo -e "${INFO}ℹ INFO  pure prompt already configured in ~/.zshrc; leaving it unchanged.${RESET}"
    return
  fi

  echo -e "${INFO}ℹ INFO  Configuring pure prompt in ~/.zshrc...${RESET}"
  {
    echo ""
    echo "# pure prompt (sindresorhus/pure — installed via brew)"
    echo 'fpath+=("$(brew --prefix)/share/zsh/site-functions")'
    echo "autoload -U promptinit; promptinit"
    echo "prompt pure"
  } >> "$HOME/.zshrc"
}

finish_with_summary() {
  log_phase "SUMMARY" "Compiling final run report"
  print_install_summary

  if [[ "${#failed_formulae[@]}" -gt 0 || "${#failed_user_casks[@]}" -gt 0 || "${#failed_admin_casks[@]}" -gt 0 ]]; then
    echo -e "${ERROR}✖ ERROR Run completed with failures. Review the summary above.${RESET}"
    exit 1
  fi

  echo -e "${SUCCESS}✓ OK    setup_env completed successfully.${RESET}"
}

run_classify_only() {
  log_phase "DISCOVER" "Starting package classification"
  ensure_homebrew_available
  quiet_homebrew_hints

  log_phase "INSTALL" "Classifying formulae"
  for formula in "${formulae[@]}"; do
    classify_formula "$formula"
  done

  log_phase "INSTALL" "Classifying user-space casks"
  for cask in "${user_casks[@]}"; do
    classify_user_cask "$cask"
  done

  log_phase "INSTALL" "Classifying admin-likely casks"
  for cask in "${admin_casks[@]}"; do
    classify_admin_cask "$cask"
  done

  finish_with_summary
}

run_non_admin_only() {
  log_phase "DISCOVER" "Preparing non-admin installation"
  echo -e "${INFO}ℹ INFO  Creating ~/.hushlogin to disable login banner.${RESET}"
  touch ~/.hushlogin

  log_phase "INSTALL" "Installing formulae and user-space casks"
  ensure_homebrew_available

  echo -e "${ACTION}ℹ INFO  Updating Homebrew...${RESET}"
  brew update
  quiet_homebrew_hints
  ensure_agent_sessions_tap
  load_installed_formula_cache

  echo -e "${SECTION}◆ PHASE Installing formulae first...${RESET}"
  for formula in "${formulae[@]}"; do
    install_formula "$formula"
  done

  echo -e "${SECTION}◆ PHASE Installing user-space casks into ~/Applications...${RESET}"
  for cask in "${user_casks[@]}"; do
    install_user_cask "$cask"
  done

  echo -e "${ACTION}ℹ INFO  Cleaning up Homebrew...${RESET}"
  local cleanup_output
  cleanup_output="$(brew cleanup 2>&1)"
  print_command_output "$cleanup_output"

  configure_direnv_hook
  configure_pure_prompt
  log_phase "VERIFY" "Verifying non-admin installations"
  verify_non_admin_installations
  finish_with_summary
}

run_admin_only() {
  log_phase "DISCOVER" "Preparing admin-likely installation"
  ensure_homebrew_available

  echo -e "${ACTION}ℹ INFO  Updating Homebrew...${RESET}"
  brew update
  quiet_homebrew_hints

  log_phase "INSTALL" "Installing admin-likely casks"
  for cask in "${admin_casks[@]}"; do
    install_admin_cask "$cask"
  done

  echo -e "${ACTION}ℹ INFO  Cleaning up Homebrew...${RESET}"
  local cleanup_output
  cleanup_output="$(brew cleanup 2>&1)"
  print_command_output "$cleanup_output"

  log_phase "VERIFY" "Verifying admin-likely installations"
  verify_admin_installations
  finish_with_summary
}

# Main script execution
case "$RUN_MODE" in
  --classify-only)
    run_classify_only
    ;;
  --non-admin-only)
    run_non_admin_only
    ;;
  --admin-only)
    run_admin_only
    ;;
esac
