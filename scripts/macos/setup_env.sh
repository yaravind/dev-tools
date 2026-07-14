#!/bin/zsh

# This script is designed to automate the installation and configuration of some
# commonly used developer tools on macOS M1/M2 chip

# Import colors codes for text
source "${0:A:h}/colors.sh"

# Semantic log colors. Keep messages readable by meaning, not by raw color.
INFO="${CYAN}"
ACTION="${BLUE}"
SUCCESS="${GREEN}"
WARN="${YELLOW}"
ERROR="${RED}"
SECTION="${BMAGENTA}"
MUTED="${BBLACK}"
SCRIPT_NAME="${0:A:t}"

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
        echo -e "${ERROR}===> Specify only one mode.${RESET}"
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
      echo -e "${ERROR}===> Unknown argument: ${arg}${RESET}"
      print_usage
      exit 1
      ;;
  esac
done

if [[ -z "$RUN_MODE" ]]; then
  echo -e "${ERROR}===> Missing required mode.${RESET}"
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
  "maven"        # Apache Maven build tool
)

# Casks expected to install as user-space GUI apps. These are installed into
# ~/Applications to avoid writing into system-wide /Applications.
user_casks=(
  #"appcleaner"                # Allows you to thoroughly uninstall unwanted apps.
  "intellij-idea"             # Use intellij-idea for Ultimate Edition
  "pycharm"                   # Use pycharm for Ultimate Edition
  "visual-studio-code"        # VS Code
  "copilot-cli"               # Brings the power of Copilot coding agent directly to your terminal
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
  printf "${SECTION}===> DryRun: Planned actions (no changes will be made)${RESET}\n"
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

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to make sure Homebrew was prepared by pre_setup.sh
ensure_homebrew_available() {
  if ! command_exists brew && [[ -x /opt/homebrew/bin/brew ]]; then
    echo -e "${ACTION}===> Loading Homebrew from /opt/homebrew into this shell...${RESET}"
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  fi

  if ! command_exists brew; then
    echo -e "${ERROR}===> Homebrew not found. Run pre_setup.sh first, then re-run setup_env.sh.${RESET}"
    exit 1
  fi

  if [[ -d /opt/homebrew && "$(stat -f '%Su' /opt/homebrew)" != "$USER" ]]; then
    echo -e "${WARN}===> /opt/homebrew is not owned by ${USER}; Homebrew installs may fail with permission errors.${RESET}"
  fi
}

quiet_homebrew_hints() {
  export HOMEBREW_NO_AUTO_UPDATE=1
  export HOMEBREW_NO_ENV_HINTS=1
  export HOMEBREW_NO_INSTALL_CLEANUP=1
}

precheck_formula_metadata() {
  local formula="$1"
  echo -e "${INFO}===> Checking Homebrew metadata for formula: ${formula}...${RESET}"

  if brew info --json=v2 "$formula" >/dev/null 2>&1; then
    return 0
  fi

  echo -e "${ERROR}===> Missing or unreadable Homebrew metadata for formula: ${formula}${RESET}"
  return 1
}

precheck_cask_metadata() {
  local cask="$1"
  echo -e "${INFO}===> Checking Homebrew metadata for cask: ${cask}...${RESET}"

  if brew info --json=v2 --cask "$cask" >/dev/null 2>&1; then
    return 0
  fi

  echo -e "${ERROR}===> Missing or unreadable Homebrew metadata for cask: ${cask}${RESET}"
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

  brew list --formula "$formula" 2>/dev/null | grep -qxF "$path"
}

dotnet_command_conflicts_with_formula() {
  local dotnet_path="/opt/homebrew/bin/dotnet"

  [[ -e "$dotnet_path" || -L "$dotnet_path" ]] || return 1
  homebrew_formula_owns_path "dotnet" "$dotnet_path" && return 1

  return 0
}

should_skip_formula_install() {
  local formula="$1"

  if [[ "$formula" == "powershell" ]] && dotnet_command_conflicts_with_formula; then
    echo -e "${WARN}===> Skipping powershell: /opt/homebrew/bin/dotnet exists but is not owned by the Homebrew dotnet formula.${RESET}"
    echo -e "${WARN}===> Choose either Homebrew formula dotnet + powershell, or the admin dotnet-sdk cask without automated PowerShell.${RESET}"
    skipped_formulae+=("powershell: dotnet command conflict")
    return 0
  fi

  return 1
}

install_formula() {
  local formula="$1"
  local output
  local exit_status

  if ! precheck_formula_metadata "$formula"; then
    failed_formulae+=("$formula")
    return 1
  fi

  if brew list --formula "$formula" >/dev/null 2>&1; then
    echo -e "${SUCCESS}===> Formula already installed: ${formula}${RESET}"
    return 0
  fi

  if should_skip_formula_install "$formula"; then
    return 0
  fi

  echo -e "${ACTION}===> Installing formula: ${formula}...${RESET}"

  output="$(brew install "$formula" 2>&1)"
  exit_status=$?
  printf '%s\n' "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}===> Installed formula: ${formula}${RESET}"
    return 0
  fi

  echo -e "${ERROR}===> Failed to install formula: ${formula}${RESET}"
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

  if cask_metadata_looks_admin_required "$cask"; then
    echo -e "${WARN}===> Cask metadata looks admin-likely; attempting user-space install before reclassifying: ${cask}${RESET}"
  fi

  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo -e "${SUCCESS}===> Cask already installed: ${cask}${RESET}"
    return 0
  fi

  mkdir -p "$HOME/Applications"

  echo -e "${ACTION}===> Installing user-space cask: ${cask}...${RESET}"
  output="$(brew install --cask --appdir="$HOME/Applications" "$cask" 2>&1)"
  exit_status=$?
  printf '%s\n' "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}===> Installed user-space cask: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ERROR}===> Failed to install user-space cask: ${cask}${RESET}"
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
    echo -e "${WARN}===> Cask metadata does not look admin-required; consider moving to user_casks: ${cask}${RESET}"
    classification_warnings+=("admin_casks:${cask}")
  fi

  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo -e "${SUCCESS}===> Cask already installed: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ACTION}===> Installing admin-likely cask: ${cask}...${RESET}"
  output="$(brew install --cask "$cask" 2>&1)"
  exit_status=$?
  printf '%s\n' "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}===> Installed admin-likely cask: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ERROR}===> Failed to install admin-likely cask: ${cask}${RESET}"
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

  echo -e "${ACTION}===> Dry-run formula install: ${formula}...${RESET}"

  output="$(brew install --dry-run "$formula" 2>&1)"
  exit_status=$?
  printf '%s\n' "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}===> Formula dry-run passed: ${formula}${RESET}"
    return 0
  fi

  echo -e "${ERROR}===> Formula dry-run failed: ${formula}${RESET}"
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
    echo -e "${WARN}===> Cask metadata looks admin-required; consider moving out of user_casks: ${cask}${RESET}"
    classification_warnings+=("user_casks:${cask}")
  else
    echo -e "${SUCCESS}===> Cask metadata looks user-space friendly: ${cask}${RESET}"
  fi

  echo -e "${ACTION}===> Dry-run user-space cask install: ${cask}...${RESET}"
  output="$(brew install --cask --dry-run --appdir="$HOME/Applications" "$cask" 2>&1)"
  exit_status=$?
  printf '%s\n' "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}===> User-space cask dry-run passed: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ERROR}===> User-space cask dry-run failed: ${cask}${RESET}"
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
    echo -e "${SUCCESS}===> Cask metadata looks admin-likely: ${cask}${RESET}"
  else
    echo -e "${WARN}===> Cask metadata does not look admin-required; consider moving to user_casks: ${cask}${RESET}"
    classification_warnings+=("admin_casks:${cask}")
  fi

  echo -e "${ACTION}===> Dry-run admin-likely cask install: ${cask}...${RESET}"
  output="$(brew install --cask --dry-run "$cask" 2>&1)"
  exit_status=$?
  printf '%s\n' "$output"

  if [[ "$exit_status" -eq 0 ]]; then
    echo -e "${SUCCESS}===> Admin-likely cask dry-run passed: ${cask}${RESET}"
    return 0
  fi

  echo -e "${ERROR}===> Admin-likely cask dry-run failed: ${cask}${RESET}"
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

  echo -e "${INFO}Total duration: $(format_duration "$elapsed_seconds")${RESET}"
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
  echo
  echo -e "${SECTION}========================================${RESET}"
  echo -e "${SECTION} Run Summary${RESET}"
  echo -e "${SECTION}========================================${RESET}"

  if [[ "${#failed_formulae[@]}" -eq 0 && "${#failed_user_casks[@]}" -eq 0 && "${#failed_admin_casks[@]}" -eq 0 ]]; then
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

  if [[ "${#classification_warnings[@]}" -gt 0 ]]; then
    echo
    echo -e "${WARN}Suggested package moves${RESET}"
    print_classification_suggestions "${classification_warnings[@]}"
  fi

  if [[ "${#admin_privilege_failures[@]}" -eq 0 && "${#classification_warnings[@]}" -eq 0 ]]; then
    echo -e "${SUCCESS}No admin-permission signals or bucket changes suggested.${RESET}"
  fi

  echo -e "${SECTION}========================================${RESET}"
}

# Function to set environment variables
set_env_vars() {
  echo -e "${SECTION}===> Start setting ENV VARs${RESET}"
  if [[ -z "${JAVA_HOME}" ]]; then
    echo -e "${INFO}===> Adding JAVA_HOME env variable to .zshrc...${RESET}"
    echo "# brew_install_apps.sh - Appending JAVA_HOME env var" >>~/.zshrc
    echo "export JAVA_HOME=$(/usr/libexec/java_home)" >>~/.zshrc
  else
    echo -e "${INFO}===> JAVA_HOME is already set to: ${JAVA_HOME}${RESET}"
  fi

  echo -e "${ACTION}===> Source .zshrc...${RESET}"
  echo 'export PATH="$HOME/.jenv/bin:$PATH"' >>~/.zshrc
  echo 'eval "$(jenv init -)"' >>~/.zshrc

  source "$HOME/.zshrc"
}

print_brew_versions() {
  local package_type="$1"
  shift

  local package

  for package in "$@"; do
    if [[ "$package_type" == "cask" ]]; then
      if brew list --cask --versions "$package" >/dev/null 2>&1; then
        brew list --cask --versions "$package"
      else
        echo -e "${WARN}  - ${package}: not installed${RESET}"
      fi
    else
      if brew list --formula --versions "$package" >/dev/null 2>&1; then
        brew list --formula --versions "$package"
      else
        echo -e "${WARN}  - ${package}: not installed${RESET}"
      fi
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
    echo -e "${INFO}===> Alias ${alias_name} already exists in ~/.zshrc; leaving it unchanged.${RESET}"
    return 0
  fi

  echo -e "${INFO}===> Adding alias ${alias_name}='${alias_value}' to ~/.zshrc...${RESET}"
  echo "alias ${alias_name}='${alias_value}'" >> "$zshrc"
}

configure_non_admin_aliases() {
  if command_exists trash; then
    add_alias_if_missing "rm" "trash"
  else
    echo -e "${WARN}===> trash is not available; skipping rm alias.${RESET}"
  fi

  if command_exists bat; then
    add_alias_if_missing "cat" "bat"
  else
    echo -e "${WARN}===> bat is not available; skipping cat alias.${RESET}"
  fi
}

# Function to verify non-admin installations
verify_non_admin_installations() {
  echo -e "${SECTION}===> Start verification${RESET}"
  echo -e "${INFO}===> Installed formulae managed by --non-admin-only...${RESET}"
  print_brew_versions "formula" "${formulae[@]}"

  echo -e "${INFO}===> Installed user-space casks managed by --non-admin-only...${RESET}"
  print_brew_versions "cask" "${user_casks[@]}"

  echo -e "${INFO}===> Verify Python...${RESET}"
  local python_313_bin
  python_313_bin="$(brew --prefix python@3.13 2>/dev/null)/bin/python3.13"

  if [[ -x "$python_313_bin" ]]; then
    echo "$python_313_bin"
    "$python_313_bin" -V
  else
    echo -e "${WARN}===> python@3.13 executable not found.${RESET}"
  fi

  echo -e "${INFO}===> Verify Maven...${RESET}"
  if command_exists mvn; then
    which -a mvn
    echo -e "${SUCCESS}===> Maven command is available.${RESET}"
  else
    echo -e "${WARN}===> mvn not found in PATH.${RESET}"
  fi

  configure_non_admin_aliases
}

# Function to verify admin-likely installations
verify_admin_installations() {
  echo -e "${SECTION}===> Start verification${RESET}"
  echo -e "${INFO}===> Installed casks managed by --admin-only...${RESET}"
  print_brew_versions "cask" "${admin_casks[@]}"

  echo -e "${INFO}===> Verify Java...${RESET}"
  if command_exists java; then
    java -version
  else
    echo -e "${WARN}===> java not found in PATH.${RESET}"
  fi

  echo -e "${INFO}===> Verify .NET...${RESET}"
  if command_exists dotnet; then
    dotnet --version
  else
    echo -e "${WARN}===> dotnet not found in PATH.${RESET}"
  fi

  echo -e "${INFO}===> Verify Git Credential Manager...${RESET}"
  if command_exists git-credential-manager; then
    git-credential-manager --version
  else
    echo -e "${WARN}===> git-credential-manager not found in PATH.${RESET}"
  fi
}

configure_direnv_hook() {
  if command_exists direnv; then
    if ! grep -qxF 'eval "$(direnv hook zsh)"' "$HOME/.zshrc" 2>/dev/null; then
      echo -e "${INFO}===> Adding direnv hook to ~/.zshrc...${RESET}"
      echo "# direnv: load environment variables per-directory" >> "$HOME/.zshrc"
      echo 'eval "$(direnv hook zsh)"' >> "$HOME/.zshrc"
    else
      echo -e "${INFO}===> direnv hook already present in ~/.zshrc${RESET}"
    fi
  else
    echo -e "${WARN}===> direnv not installed; skipping ~/.zshrc hook setup.${RESET}"
  fi
}

finish_with_summary() {
  print_install_summary
  print_elapsed_time

  if [[ "${#failed_formulae[@]}" -gt 0 || "${#failed_user_casks[@]}" -gt 0 || "${#failed_admin_casks[@]}" -gt 0 ]]; then
    echo -e "${ERROR}===> Run completed with failures. Review the summary above.${RESET}"
    exit 1
  fi

  printf "\n\n👌 Awesome, all set.\n"
}

run_classify_only() {
  echo -e "${SECTION}===> Start classification.${RESET}"
  ensure_homebrew_available
  quiet_homebrew_hints

  echo -e "${SECTION}===> Classifying formulae...${RESET}"
  for formula in "${formulae[@]}"; do
    classify_formula "$formula"
  done

  echo -e "${SECTION}===> Classifying user-space casks...${RESET}"
  for cask in "${user_casks[@]}"; do
    classify_user_cask "$cask"
  done

  echo -e "${SECTION}===> Classifying admin-likely casks...${RESET}"
  for cask in "${admin_casks[@]}"; do
    classify_admin_cask "$cask"
  done

  finish_with_summary
}

run_non_admin_only() {
  echo -e "${INFO}===> Creating ~/.hushlogin to disable login banner.${RESET}"
  touch ~/.hushlogin

  echo -e "${SECTION}===> Start non-admin installation.${RESET}"
  ensure_homebrew_available

  echo -e "${ACTION}===> Updating Homebrew...${RESET}"
  brew update
  quiet_homebrew_hints

  echo -e "${SECTION}===> Installing formulae first...${RESET}"
  for formula in "${formulae[@]}"; do
    install_formula "$formula"
  done

  echo -e "${SECTION}===> Installing user-space casks into ~/Applications...${RESET}"
  for cask in "${user_casks[@]}"; do
    install_user_cask "$cask"
  done

  echo -e "${ACTION}===> Cleaning up Homebrew...${RESET}"
  brew cleanup

  configure_direnv_hook
  verify_non_admin_installations
  finish_with_summary
}

run_admin_only() {
  echo -e "${SECTION}===> Start admin-likely installation.${RESET}"
  ensure_homebrew_available

  echo -e "${ACTION}===> Updating Homebrew...${RESET}"
  brew update
  quiet_homebrew_hints

  echo -e "${SECTION}===> Installing admin-likely casks...${RESET}"
  for cask in "${admin_casks[@]}"; do
    install_admin_cask "$cask"
  done

  echo -e "${ACTION}===> Cleaning up Homebrew...${RESET}"
  brew cleanup

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
