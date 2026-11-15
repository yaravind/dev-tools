#!/bin/zsh

# Interactive macOS setup launchpad for the Engineer Bootstrap Kit.

set -u
set -o pipefail
typeset -F SECONDS

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
SCRIPT_NAME="${0:A:t}"

source "${SCRIPT_DIR}/branding.sh"
ebk_print_banner "$SCRIPT_NAME"

DRY_RUN=0
CONTINUE_ON_ERROR=0
ASSUME_YES=0
PROFILE=""

RUN_PARENT="${REPO_ROOT}/.run/launchpad"
RUN_ROOT=""

typeset -a TASK_ORDER
typeset -A TASK_LABEL
typeset -A TASK_DESC
typeset -A TASK_DEPS
typeset -A TASK_ADMIN
typeset -A TASK_ADMIN_REASON
typeset -A TASK_SOFT_FAIL
typeset -A SELECTED
typeset -A INCLUDED_BY_DEP
typeset -A TASK_STATUS
typeset -A TASK_LOG
typeset -A TASK_EXIT
typeset -A TASK_DURATION
typeset -A TASK_CHILD_EXIT
typeset -A TASK_BLOCK_REASON
RUN_DURATION=""
CURRENT_TASK=""
typeset -F CURRENT_TASK_STARTED RUN_STARTED_AT

clone_destination=""
clone_repo_list=""
codex_backup_path=""
LAST_ERROR=""

print_usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [--profile NAME] [--dry-run] [--continue-on-error] [--yes]

Profiles:
  full             Homebrew, full tool install, shell, macOS, Java, IDEs
  minimal-java     Homebrew, Git, JDK 17, Maven, VS Code, IntelliJ CE, Git config, IDE plugins
  ide-only         VS Code, IntelliJ, and PyCharm plugin setup only
  personalize      Shell plugins, Dock, macOS settings, and default apps
  custom           Choose individual tasks interactively

Options:
  --dry-run, -n          Show the selected run plan without executing scripts
  --continue-on-error    Accepted for compatibility; non-critical tasks continue by default
  --yes, -y              Do not ask for final launchpad confirmation
  --clone-destination D  Required destination directory when clone_repos is selected
  --clone-repo-list F    Repo list file for clone_github_repos.sh
  --codex-backup D       Backup folder for restore_codex.sh
  --help, -h             Show this help

Admin handling:
  The launchpad never runs itself or child scripts with sudo. For admin-scoped
  tasks, it asks immediately before the task and runs sudo -v only if approved.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ -z "${2:-}" ]]; then
        log_error "--profile requires a value."
        exit 1
      fi
      PROFILE="$2"
      shift 2
      ;;
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --continue-on-error)
      CONTINUE_ON_ERROR=1
      shift
      ;;
    --yes|-y)
      ASSUME_YES=1
      shift
      ;;
    --clone-destination)
      if [[ -z "${2:-}" ]]; then
        log_error "--clone-destination requires a directory."
        exit 1
      fi
      clone_destination="${2/#\~/$HOME}"
      shift 2
      ;;
    --clone-repo-list)
      if [[ -z "${2:-}" ]]; then
        log_error "--clone-repo-list requires a file."
        exit 1
      fi
      clone_repo_list="${2/#\~/$HOME}"
      shift 2
      ;;
    --codex-backup)
      if [[ -z "${2:-}" ]]; then
        log_error "--codex-backup requires a directory."
        exit 1
      fi
      codex_backup_path="${2/#\~/$HOME}"
      shift 2
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      print_usage
      exit 1
      ;;
  esac
done

add_task() {
  local id="$1" label="$2" desc="$3" deps="${4:-}" admin="${5:-0}" admin_reason="${6:-}" soft_fail="${7:-0}"
  TASK_ORDER+=("$id")
  TASK_LABEL[$id]="$label"
  TASK_DESC[$id]="$desc"
  TASK_DEPS[$id]="$deps"
  TASK_ADMIN[$id]="$admin"
  TASK_ADMIN_REASON[$id]="$admin_reason"
  TASK_SOFT_FAIL[$id]="$soft_fail"
}

register_tasks() {
  add_task "pre_setup" "Prepare Homebrew" \
    "Prepare Homebrew prefix, install Homebrew, and wire shell profile." \
    "" 1 "May need sudo to create or change ownership of the Homebrew prefix, especially /opt/homebrew on Apple Silicon."
  add_task "setup_env_classify" "Classify Homebrew packages" \
    "Dry-run Homebrew metadata classification for full setup packages." \
    "pre_setup"
  add_task "setup_env_non_admin" "Install non-admin tools" \
    "Install formulae and user-space casks from setup_env.sh." \
    "pre_setup"
  add_task "setup_env_admin" "Install admin-likely tools" \
    "Install admin-likely casks such as JDKs, dotnet-sdk, and credential manager." \
    "pre_setup" 1 "Installs casks that commonly use privileged installers, daemons, helpers, or system-wide locations."
  add_task "setup_env_min" "Install minimal Java tools" \
    "Install Git, Microsoft OpenJDK 17, Maven, VS Code, and IntelliJ IDEA Community." \
    "pre_setup"
  add_task "git_setup" "Configure Git" \
    "Set global Git user name, email, and macOS credential helper."
  add_task "clone_repos" "Clone GitHub repositories" \
    "Clone config/github-repos.txt entries, skipping existing directories." \
    "" 0 "" 1
  add_task "zsh_plugins" "Install Zsh plugins" \
    "Generate antidote plugin bundle and source it from ~/.zshrc."
  add_task "zshrc_setup" "Merge zshrc config" \
    "Remove duplicate lines from ~/.zshrc and source config/.zshrc from the repo." \
    "zsh_plugins"
  add_task "dock_setup" "Customize Dock" \
    "Apply Dock layout from config/dock_apps.txt."
  add_task "macos_user" "Configure macOS user settings" \
    "Run non-admin macOS defaults configurator."
  add_task "macos_admin" "Configure macOS admin settings" \
    "Run admin macOS settings configurator with sudo." \
    "" 1 "Runs macos_setup.sh --admin-only, which applies system-level settings with sudo."
  add_task "default_apps" "Set default apps" \
    "Apply LaunchServices mappings from config/default_apps_macos.txt."
  add_task "jenv_setup" "Configure jenv" \
    "Register installed JDKs with jenv and choose the global Java version."
  add_task "vscode_setup" "Set up VS Code" \
    "Install VS Code extensions and merge managed settings."
  add_task "intellij_setup" "Set up IntelliJ" \
    "Install IntelliJ plugins from config/intellij.txt."
  add_task "pycharm_setup" "Set up PyCharm" \
    "Install PyCharm plugins from config/pycharm.txt."
  add_task "restore_codex" "Restore Codex backup" \
    "Replace ~/.codex from a full backup with safety backup and rollback."
}

print_profile_details() {
  case "$PROFILE" in
    minimal-java)
      log_step "Profile details: minimal-java"
      printf "This profile runs the smallest Java/Spark-oriented setup path:\n"
      printf "  - Prepare Homebrew with pre_setup.sh\n"
      printf "  - Install Git\n"
      printf "  - Install Microsoft OpenJDK 17\n"
      printf "  - Install Maven without pulling an extra Java dependency\n"
      printf "  - Install Visual Studio Code\n"
      printf "  - Install IntelliJ IDEA Community Edition\n"
      printf "  - Configure global Git identity and credential helper\n"
      printf "  - Install VS Code extensions/settings from config/vscode.*\n"
      printf "  - Install IntelliJ plugins from config/intellij.txt\n\n"
      ;;
  esac
}

task_exists() {
  local wanted="$1" id
  for id in "${TASK_ORDER[@]}"; do
    [[ "$id" == "$wanted" ]] && return 0
  done
  return 1
}

select_task() {
  local id="$1" by_dep="${2:-0}"
  if ! task_exists "$id"; then
    log_error "Unknown task id: $id"
    return 1
  fi

  if [[ -z "${SELECTED[$id]:-}" && "$by_dep" -eq 1 ]]; then
    INCLUDED_BY_DEP[$id]=1
  elif [[ "$by_dep" -eq 0 ]]; then
    unset "INCLUDED_BY_DEP[$id]"
  fi
  SELECTED[$id]=1
}

select_with_deps() {
  local id="$1" by_dep="${2:-0}"
  local dep
  local deps="${TASK_DEPS[$id]:-}"

  for dep in ${=deps}; do
    select_with_deps "$dep" 1 || return 1
  done

  select_task "$id" "$by_dep"
}

select_profile_tasks() {
  local profile="$1"
  local id

  SELECTED=()
  INCLUDED_BY_DEP=()

  case "$profile" in
	full)
	  for id in \
	    pre_setup setup_env_non_admin setup_env_admin git_setup clone_repos \
	    zsh_plugins dock_setup default_apps jenv_setup \
	    vscode_setup intellij_setup pycharm_setup; do
	    select_with_deps "$id"
	  done
      ;;
    minimal-java)
      for id in pre_setup setup_env_min git_setup vscode_setup intellij_setup; do
        select_with_deps "$id"
      done
      ;;
    ide-only)
      for id in vscode_setup intellij_setup pycharm_setup; do
        select_with_deps "$id"
      done
      ;;
    personalize)
      for id in zsh_plugins dock_setup macos_user default_apps; do
        select_with_deps "$id"
      done
      ;;
    custom)
      prompt_custom_tasks
      ;;
    *)
      log_error "Unknown profile: $profile"
      print_usage
      exit 1
      ;;
  esac
}

read_launchpad_default() {
  ebk_read_default "$1" "$2" || {
    log_error "Input ended or was canceled; launchpad will not continue."
    return 1
  }
}

read_launchpad_line() {
  printf '%s' "$1"
  IFS= read -r REPLY || {
    log_error "Input ended or was canceled; launchpad will not continue."
    return 1
  }
}

read_launchpad_confirmation() {
  local prompt="$1" default_value="$2"
  while true; do
    read_launchpad_default "$prompt" "$default_value" || return 1
    case "${REPLY:l}" in
      y|yes) REPLY=y; return 0 ;;
      n|no) REPLY=n; return 0 ;;
      *) log_warn "Enter y or n." ;;
    esac
  done
}

prompt_profile() {
  local choice

  log_step "Choose setup profile"
  printf "  1. full         - Homebrew, full tools, shell, macOS, Java, IDEs\n"
  printf "  2. minimal-java - Git, JDK 17, Maven, VS Code, IntelliJ CE, Git config, IDE plugins\n"
  printf "  3. ide-only     - VS Code, IntelliJ, and PyCharm plugin setup only\n"
  printf "  4. personalize  - Shell plugins, Dock, macOS settings, default apps\n"
  printf "  5. custom       - Choose individual tasks\n"
  while true; do
    read_launchpad_default $'\nSelect profile [1-5] (default: 1 - full): ' "1" || return 1
    choice="${REPLY:l}"

    case "$choice" in
      ""|1|full) PROFILE="full" ;;
      2|minimal-java) PROFILE="minimal-java" ;;
      3|ide-only) PROFILE="ide-only" ;;
      4|personalize) PROFILE="personalize" ;;
      5|custom) PROFILE="custom" ;;
      *)
        log_warn "Unknown selection '$choice'; choose a profile from 1 to 5."
        continue
        ;;
    esac
    return 0
  done
}

prompt_custom_tasks() {
  local i=1
  local id
  local selection
  local token

  log_step "Choose tasks"
  for id in "${TASK_ORDER[@]}"; do
    printf "  %2d. %-22s %s\n" "$i" "$id" "${TASK_LABEL[$id]}"
    ((i++))
  done

  read_launchpad_line $'\nEnter comma-separated numbers or ids (example: 1,3,vscode_setup): ' || return 1
  selection="$REPLY"

  if [[ -z "$selection" ]]; then
    log_warn "No custom tasks selected."
    return 0
  fi

  selection="${selection//,/ }"
  for token in ${=selection}; do
    if [[ "$token" =~ '^[0-9]+$' ]]; then
      if (( ${#token} > 9 )); then
        log_warn "Ignoring invalid task number: $token"
        continue
      fi
      token="$((10#$token))"
      if (( token < 1 || token > ${#TASK_ORDER[@]} )); then
        log_warn "Ignoring invalid task number: $token"
        continue
      fi
      id="${TASK_ORDER[$token]}"
    else
      id="$token"
    fi

    if task_exists "$id"; then
      select_with_deps "$id"
    else
      log_warn "Ignoring unknown task id: $id"
    fi
  done
}

prompt_optional_tasks() {
  local answer

  if [[ -n "$codex_backup_path" && -z "${SELECTED[restore_codex]:-}" ]]; then
    select_with_deps restore_codex || return 1
  fi
  if [[ ! -t 0 ]]; then
    return 0
  fi

  if [[ -z "${SELECTED[restore_codex]:-}" ]]; then
    read_launchpad_confirmation $'\nRestore a Codex backup as part of this run? (y/N): ' "n" || return 1
    answer="$REPLY"
    if [[ "$answer" =~ '^[Yy]$' ]]; then
      select_with_deps "restore_codex"
    fi
  fi
}

prompt_task_values() {
  local clone_answer

  if [[ -n "${SELECTED[clone_repos]:-}" && ! -t 0 && -z "$clone_destination" ]]; then
    unset 'SELECTED[clone_repos]' 'INCLUDED_BY_DEP[clone_repos]'
    log_info "Repository cloning not selected; provide --clone-destination to opt in with redirected input."
  fi
  if [[ -n "${SELECTED[clone_repos]:-}" && -t 0 ]]; then
    log_step "Clone GitHub repositories"
    read_launchpad_confirmation "Clone repositories from config/github-repos.txt? (y/N): " "n" || return 1
    clone_answer="$REPLY"
    case "${clone_answer:l}" in
      y|yes)
        while [[ -z "$clone_destination" ]]; do
          read_launchpad_line "Directory to clone into (required): " || return 1
          clone_destination="$REPLY"
          clone_destination="${clone_destination/#\~/$HOME}"
          if [[ -z "$clone_destination" ]]; then
            log_warn "A clone destination is required when clone_repos is selected."
          fi
        done
        ;;
      ""|n|no)
        unset 'SELECTED[clone_repos]'
        unset 'INCLUDED_BY_DEP[clone_repos]'
        ;;
    esac
  fi

  if [[ -n "${SELECTED[clone_repos]:-}" && -z "$clone_destination" ]]; then
    log_error "clone_repos needs --clone-destination."
    return 1
  fi

  if [[ -n "${SELECTED[restore_codex]:-}" && -z "$codex_backup_path" && ! -t 0 ]]; then
    log_error "Codex restore needs --codex-backup when stdin is not interactive."
    return 1
  fi

  if [[ -n "${SELECTED[restore_codex]:-}" ]]; then
    while [[ -z "$codex_backup_path" ]]; do
      read_launchpad_line $'\nCodex backup folder to restore from: ' || return 1
      codex_backup_path="$REPLY"
      codex_backup_path="${codex_backup_path/#\~/$HOME}"
      if [[ -z "$codex_backup_path" ]]; then
        log_warn "A backup path is required for Codex restore."
      fi
    done
  fi
}

build_command() {
  local id="$1"
  cmd=()

  case "$id" in
    pre_setup)
      cmd=(zsh "${SCRIPT_DIR}/pre_setup.sh")
      ;;
    setup_env_classify)
      cmd=(zsh "${SCRIPT_DIR}/setup_env.sh" --classify-only)
      ;;
    setup_env_non_admin)
      cmd=(zsh "${SCRIPT_DIR}/setup_env.sh" --non-admin-only)
      ;;
    setup_env_admin)
      cmd=(zsh "${SCRIPT_DIR}/setup_env.sh" --admin-only)
      ;;
    setup_env_min)
      cmd=(zsh "${SCRIPT_DIR}/setup_env_min.sh")
      ;;
    git_setup)
      cmd=(zsh "${SCRIPT_DIR}/git_setup.sh")
      ;;
    clone_repos)
      local repo_list_arg="${clone_repo_list:-${REPO_ROOT}/config/github-repos.txt}"
      cmd=(zsh "${SCRIPT_DIR}/clone_github_repos.sh" "$repo_list_arg" "$clone_destination")
      ;;
    zsh_plugins)
      cmd=(zsh "${SCRIPT_DIR}/zsh_plugins_setup.sh")
      ;;
    zshrc_setup)
      cmd=(zsh "${SCRIPT_DIR}/zshrc_setup.sh")
      ;;
    dock_setup)
      cmd=(zsh "${SCRIPT_DIR}/dock_setup.sh")
      ;;
    macos_user)
      cmd=(zsh "${SCRIPT_DIR}/macos_setup.sh" --non-admin-only)
      ;;
    macos_admin)
      cmd=(zsh "${SCRIPT_DIR}/macos_setup.sh" --admin-only)
      ;;
    default_apps)
      cmd=(zsh "${SCRIPT_DIR}/default_apps_setup.sh" --apply)
      ;;
    jenv_setup)
      cmd=(zsh "${SCRIPT_DIR}/jenv_setup.sh")
      ;;
    vscode_setup)
      cmd=(zsh "${SCRIPT_DIR}/vscode_setup.sh")
      ;;
    intellij_setup)
      cmd=(zsh "${SCRIPT_DIR}/intellij_setup.sh")
      ;;
    pycharm_setup)
      cmd=(zsh "${SCRIPT_DIR}/pycharm_setup.sh")
      ;;
    restore_codex)
      cmd=(zsh "${SCRIPT_DIR}/restore_codex.sh" "$codex_backup_path")
      ;;
    *)
      return 1
      ;;
  esac
}

print_command() {
  local id="$1"
  build_command "$id" || return 1
  printf '%q ' "${cmd[@]}"
  printf '\n'
}

command_text() {
  local id="$1"
  build_command "$id" || return 1
  printf '%q ' "${cmd[@]}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

refresh_install_environment() {
  local id="$1" brew_bin="" prefix candidate
  case "$id" in
    pre_setup|setup_env_non_admin|setup_env_admin|setup_env_min) ;;
    *) return 0 ;;
  esac

  if command_exists brew; then
    brew_bin="$(command -v brew)"
  else
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [[ -x "$candidate" ]]; then
        brew_bin="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$brew_bin" ]] || ! prefix="$("$brew_bin" --prefix)" || [[ ! -d "$prefix/bin" ]]; then
    record_failure_reason "Cannot refresh the launchpad Homebrew environment after ${TASK_LABEL[$id]}."
    return 1
  fi
  export HOMEBREW_PREFIX="$prefix"
  path=("$prefix/bin" "$prefix/sbin" "${path[@]}")
  typeset -gU path
  rehash
  log_info "Refreshed the launchpad Homebrew environment."
}

task_requires_admin() {
  local id="$1"
  [[ "${TASK_ADMIN[$id]:-0}" == "1" ]]
}

task_allows_issues() {
  local id="$1"
  [[ "${TASK_SOFT_FAIL[$id]:-0}" == "1" ]]
}

task_is_critical() {
  local id="$1"
  case "$id" in
    pre_setup|setup_env_classify|setup_env_non_admin|setup_env_admin|setup_env_min)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

check_task_dependencies() {
  local id="$1" dep state
  local deps="${TASK_DEPS[$id]:-}"
  for dep in ${=deps}; do
    state="${TASK_STATUS[$dep]:-not-run}"
    if [[ "$state" == success || ( "$DRY_RUN" -eq 1 && "$state" == planned ) ]]; then
      continue
    fi
    TASK_STATUS[$id]="blocked"
    TASK_EXIT[$id]="-"
    TASK_BLOCK_REASON[$id]="Prerequisite $dep is $state."
    log_warn "${TASK_LABEL[$id]} blocked: ${TASK_BLOCK_REASON[$id]}"
    return 1
  done
  return 0
}

mark_unrun_dependants() {
  local id
  for id in "${TASK_ORDER[@]}"; do
    [[ -n "${SELECTED[$id]:-}" && -z "${TASK_STATUS[$id]:-}" ]] || continue
    check_task_dependencies "$id" || true
  done
}

record_failure_reason() {
  LAST_ERROR="$1"
  log_error "$LAST_ERROR"
}

authorize_admin_for_task() {
  local id="$1"
  local answer

  task_requires_admin "$id" || return 0

  log_warn "${TASK_LABEL[$id]} is admin-scoped."
  if [[ -n "${TASK_ADMIN_REASON[$id]:-}" ]]; then
    log_info "${TASK_ADMIN_REASON[$id]}"
  fi

  if [[ ! -t 0 ]]; then
    record_failure_reason "Cannot request admin approval for ${TASK_LABEL[$id]} because stdin is not interactive."
    log_error "Run this task from an interactive terminal."
    return 1
  fi

  read_launchpad_confirmation "Enable admin privileges for this step only? (Y/n): " "y" || {
    record_failure_reason "Admin approval input ended or was canceled."
    return 1
  }
  answer="$REPLY"
  if [[ ! "$answer" =~ '^[Yy]$' ]]; then
    log_warn "Skipping ${TASK_LABEL[$id]} without admin privileges."
    TASK_STATUS[$id]="skipped"
    return 2
  fi

  if sudo -v; then
    log_ok "Admin privileges enabled for this step."
    return 0
  fi

  record_failure_reason "Admin authentication failed for ${TASK_LABEL[$id]}."
  return 1
}

require_command() {
  local command_name="$1"
  local task_label="$2"
  if ! command_exists "$command_name"; then
    record_failure_reason "${task_label} requires '${command_name}' in PATH."
    return 1
  fi
  return 0
}

check_task_ready() {
  local id="$1"

  case "$id" in
    pre_setup)
      require_command curl "${TASK_LABEL[$id]}" || return 1
      ;;
    git_setup|clone_repos)
      require_command git "${TASK_LABEL[$id]}" || return 1
      ;;
    zsh_plugins)
      require_command brew "${TASK_LABEL[$id]}" || return 1
      ;;
    dock_setup)
      require_command dockutil "${TASK_LABEL[$id]}" || return 1
      [[ -f "${REPO_ROOT}/config/dock_apps.txt" ]] || {
        record_failure_reason "Dock config not found: ${REPO_ROOT}/config/dock_apps.txt"
        return 1
      }
      ;;
    default_apps)
      require_command duti "${TASK_LABEL[$id]}" || return 1
      [[ -f "${REPO_ROOT}/config/default_apps_macos.txt" ]] || {
        record_failure_reason "Default apps config not found: ${REPO_ROOT}/config/default_apps_macos.txt"
        return 1
      }
      ;;
    jenv_setup)
      require_command jenv "${TASK_LABEL[$id]}" || return 1
      require_command xmllint "${TASK_LABEL[$id]}" || return 1
      [[ -x /usr/libexec/java_home ]] || {
        record_failure_reason "jenv setup requires /usr/libexec/java_home."
        return 1
      }
      ;;
    vscode_setup)
      require_command code "${TASK_LABEL[$id]}" || return 1
      require_command python3 "${TASK_LABEL[$id]}" || return 1
      ;;
    restore_codex)
      if [[ -z "$codex_backup_path" || ! -d "$codex_backup_path" ]]; then
        record_failure_reason "Codex backup folder not found: ${codex_backup_path}"
        return 1
      fi
      ;;
  esac

  return 0
}

selected_task_count() {
  local count=0
  local id
  for id in "${TASK_ORDER[@]}"; do
    [[ -n "${SELECTED[$id]:-}" ]] && ((count++))
  done
  printf '%d\n' "$count"
}

initialize_run_directory() {
  RUN_ROOT=""
  if ! mkdir -p "$RUN_PARENT"; then
    log_error "Cannot create launchpad log parent: $RUN_PARENT"
    return 1
  fi
  if ! RUN_ROOT="$(mktemp -d "${RUN_PARENT}/$(date +%Y%m%d-%H%M%S)-$$.XXXXXX")"; then
    log_error "Cannot reserve a unique launchpad log directory under $RUN_PARENT."
    return 1
  fi
}

print_plan() {
  local id
  local index=1

  log_step "Run plan"
  print_profile_details
  printf "Profile: %s\n" "$PROFILE"
  printf "Mode: %s\n" "$([[ "$DRY_RUN" -eq 1 ]] && printf dry-run || printf execute)"
  printf "Failure policy: continue after non-critical failures; stop after core setup failures; block unmet prerequisites\n"
  printf "Logs: %s\n\n" "$RUN_ROOT"

  for id in "${TASK_ORDER[@]}"; do
    [[ -n "${SELECTED[$id]:-}" ]] || continue
    printf "%2d. %s" "$index" "${TASK_LABEL[$id]}"
    if task_requires_admin "$id"; then
      printf " %s[admin]%s" "$EBK_WARN_COLOR" "$EBK_RESET"
    fi
    if task_allows_issues "$id"; then
      printf " %s[continues-on-issues]%s" "$EBK_WARN_COLOR" "$EBK_RESET"
    fi
    if [[ -n "${INCLUDED_BY_DEP[$id]:-}" ]]; then
      printf " (dependency)"
    fi
    printf "\n"
    printf "    %s\n" "${TASK_DESC[$id]}"
    if task_requires_admin "$id" && [[ -n "${TASK_ADMIN_REASON[$id]:-}" ]]; then
      printf "    %sadmin: %s%s\n" "$EBK_WARN_COLOR" "${TASK_ADMIN_REASON[$id]}" "$EBK_RESET"
    fi
    if task_allows_issues "$id"; then
      printf "    %sissues: Nonzero exit is recorded and the launchpad continues.%s\n" "$EBK_WARN_COLOR" "$EBK_RESET"
    fi
    printf "    command: %s%s%s\n" "$EBK_MUTED" "$(command_text "$id")" "$EBK_RESET"
    ((index++))
  done
}

confirm_plan() {
  local answer

  if [[ "$ASSUME_YES" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  read_launchpad_confirmation $'\nProceed with this launchpad run? (Y/n): ' "y" || return 2
  answer="$REPLY"
  [[ "$answer" =~ '^[Yy]$' ]]
}

strip_ansi_for_log() {
  perl -pe 's/\e\][^\a]*(?:\a|\e\\)//g; s/\e\[[0-?]*[ -\/]*[@-~]//g'
}

capture_task_output() {
  perl -e '
    open my $log, ">>", $ARGV[0] or die "Cannot open task log: $!\n";
    $| = 1;
    my $pending = "";
    my $write_log = sub {
      my ($line) = @_;
      $line =~ s/\e\][^\a]*(?:\a|\e\\)//g;
      $line =~ s/\e\[[0-?]*[ -\/]*[@-~]//g;
      print $log $line or die "Cannot write task log: $!\n";
    };
    while (1) {
      my $read = sysread STDIN, my $chunk, 8192;
      defined $read or die "Cannot read task output: $!\n";
      last if $read == 0;
      print STDOUT $chunk or die "Cannot display task output: $!\n";
      $pending .= $chunk;
      while ($pending =~ s/^(.*?\n)//s) { $write_log->($1); }
    }
    $write_log->($pending) if length $pending;
    close $log or die "Cannot close task log: $!\n";
  ' "$1"
}

fail_task() {
  local id="$1" message="$2" rc="${3:-1}"
  TASK_STATUS[$id]="failed"
  TASK_EXIT[$id]="$rc"
  record_failure_reason "$message"
  if [[ -n "${TASK_LOG[$id]:-}" && -f "${TASK_LOG[$id]}" ]]; then
    printf 'Launchpad status: failed\nError: %s\n' "$message" >> "${TASK_LOG[$id]}" ||
      log_error "Could not record failure in ${TASK_LOG[$id]}."
  fi
}

handle_run_signal() {
  local rc="$1"
  trap - INT TERM EXIT
  if [[ -n "$CURRENT_TASK" ]]; then
    printf -v "TASK_DURATION[$CURRENT_TASK]" '%.5f' "$((SECONDS - CURRENT_TASK_STARTED))"
    fail_task "$CURRENT_TASK" "Launchpad task interrupted or aborted." "$rc"
    if [[ -n "${TASK_LOG[$CURRENT_TASK]:-}" && -f "${TASK_LOG[$CURRENT_TASK]}" ]]; then
      printf 'Duration seconds: %s\n' "${TASK_DURATION[$CURRENT_TASK]}" >> "${TASK_LOG[$CURRENT_TASK]}" ||
        log_error "Cannot finalize interrupted task log."
    fi
  fi
  printf -v RUN_DURATION '%.5f' "$((SECONDS - RUN_STARTED_AT))"
  print_summary
  exit "$rc"
}

run_task() {
  local id="$1"
  local -F started_at="$SECONDS"
  local rc

  CURRENT_TASK="$id"
  CURRENT_TASK_STARTED="$started_at"
  LAST_ERROR=""
  unset "TASK_CHILD_EXIT[$id]" "TASK_LOG[$id]"
  TASK_STATUS[$id]="running"
  TASK_EXIT[$id]="-"
  run_task_impl "$id"
  rc=$?
  if [[ "$rc" -ne 0 && "${TASK_STATUS[$id]:-}" != "failed" ]]; then
    local failure_rc="${TASK_CHILD_EXIT[$id]:-$rc}"
    (( failure_rc == 0 )) && failure_rc=1
    fail_task "$id" "${LAST_ERROR:-Task preparation or logging failed for ${TASK_LABEL[$id]}.}" "$failure_rc"
    rc="$failure_rc"
  fi
  printf -v "TASK_DURATION[$id]" '%.5f' "$((SECONDS - started_at))"
  if [[ -n "${TASK_LOG[$id]:-}" && -f "${TASK_LOG[$id]}" ]]; then
    if ! printf 'Duration seconds: %s\n' "${TASK_DURATION[$id]}" >> "${TASK_LOG[$id]}"; then
      rc="${TASK_CHILD_EXIT[$id]:-1}"
      (( rc == 0 )) && rc=1
      fail_task "$id" "Cannot finalize task log: ${TASK_LOG[$id]}" "$rc"
    fi
  fi
  CURRENT_TASK=""
  return "$rc"
}

run_task_impl() {
  local id="$1"
  local log_file="${RUN_ROOT}/${id}.log"
  local rc
  local -a pipeline_codes

  build_command "$id" || {
    fail_task "$id" "Cannot construct command for ${TASK_LABEL[$id]}."
    return 1
  }

  TASK_LOG[$id]="$log_file"

  log_step "Running ${TASK_LABEL[$id]}"
  log_info "Log file: ${log_file}"

  mkdir -p "$RUN_ROOT" || {
    fail_task "$id" "Cannot create log directory: $RUN_ROOT"
    return 1
  }
  {
    printf 'Launchpad task log\n'
    printf 'Task id: %s\n' "$id"
    printf 'Task label: %s\n' "${TASK_LABEL[$id]}"
    printf 'Started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Command: '
    print_command "$id"
    printf 'Log file: %s\n' "$log_file"
    printf '\n'
  } > "$log_file" || {
    fail_task "$id" "Cannot create task log: $log_file"
    return 1
  }

  if [[ "$DRY_RUN" -eq 1 ]]; then
    TASK_STATUS[$id]="planned"
    TASK_EXIT[$id]="-"
    printf "[dry-run] "
    print_command "$id"
    {
      printf 'Launchpad status: planned dry-run\n'
      printf 'Finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
      printf 'Exit code: planned\n'
    } >> "$log_file" || return 1
    return 0
  fi

  LAST_ERROR=""
  authorize_admin_for_task "$id"
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    {
      printf 'Launchpad status: skipped\n'
      printf 'Reason: admin privileges were not approved for this step.\n'
      printf 'Finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
      printf 'Exit code: skipped\n'
    } >> "$log_file" || return 1
    TASK_EXIT[$id]="-"
    return 0
  elif [[ "$rc" -ne 0 ]]; then
    TASK_STATUS[$id]="failed"
    TASK_EXIT[$id]="$rc"
    {
      printf 'Launchpad status: failed before script execution\n'
      [[ -n "$LAST_ERROR" ]] && printf 'Error: %s\n' "$LAST_ERROR"
      printf 'Finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
      printf 'Exit code: %d\n' "$rc"
    } >> "$log_file" || return 1
    return "$rc"
  fi

  if ! check_task_ready "$id"; then
    TASK_STATUS[$id]="failed"
    TASK_EXIT[$id]=1
    {
      printf 'Launchpad status: failed readiness check\n'
      [[ -n "$LAST_ERROR" ]] && printf 'Error: %s\n' "$LAST_ERROR"
      printf 'Finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
      printf 'Exit code: 1\n'
    } >> "$log_file" || return 1
    return 1
  fi

  EBK_FORCE_COLOR=1 "${cmd[@]}" 2>&1 | capture_task_output "$log_file"
  pipeline_codes=("${pipestatus[@]}")
  rc="${pipeline_codes[1]}"
  TASK_CHILD_EXIT[$id]="$rc"
  TASK_EXIT[$id]="$rc"
  if [[ "${pipeline_codes[2]}" -ne 0 ]]; then
    (( rc == 0 )) && rc=1
    fail_task "$id" "Task output capture failed; child exit code: ${TASK_CHILD_EXIT[$id]}." "$rc"
    return "$rc"
  fi

  {
    printf '\nFinished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Exit code: %d\n' "$rc"
  } >> "$log_file" || return 1

  if [[ "$id" == "dock_setup" && "$rc" -eq 75 ]]; then
    TASK_STATUS[$id]="skipped"
    {
      printf 'Launchpad status: skipped\n'
      printf 'Reason: user skipped the Dock changes after reviewing the plan.\n'
    } >> "$log_file" || return 1
    log_warn "${TASK_LABEL[$id]} skipped by user."
    return 0
  fi

  if [[ "$rc" -eq 0 ]]; then
    if ! refresh_install_environment "$id"; then
      TASK_STATUS[$id]="failed"
      TASK_EXIT[$id]=1
      printf 'Launchpad status: failed environment refresh\nError: %s\n' "$LAST_ERROR" >> "$log_file" ||
        log_error "Cannot write environment refresh failure to $log_file."
      return 1
    fi
    TASK_STATUS[$id]="success"
    log_ok "${TASK_LABEL[$id]} completed."
  elif task_allows_issues "$id"; then
    TASK_STATUS[$id]="issues"
    log_warn "${TASK_LABEL[$id]} completed with issues. Continuing; review ${log_file}."
    return 0
  elif [[ "$id" == "intellij_setup" || "$id" == "pycharm_setup" ]] &&
       grep -Eq 'Status[[:space:]]+.*COMPLETED WITH ISSUES' "$log_file" &&
       grep -Eq 'Failed installs[[:space:]]+0' "$log_file"; then
    TASK_STATUS[$id]="issues"
    log_warn "${TASK_LABEL[$id]} completed with issues. Continuing; review ${log_file}."
    return 0
  else
    TASK_STATUS[$id]="failed"
    log_error "${TASK_LABEL[$id]} failed with exit code ${rc}."
  fi

  return "$rc"
}

run_selected_tasks() {
  local id
  local rc
  local overall_rc=0

  if [[ "$(selected_task_count)" -eq 0 ]]; then
    log_warn "No tasks selected. Nothing to run."
    return 0
  fi

  for id in "${TASK_ORDER[@]}"; do
    [[ -n "${SELECTED[$id]:-}" ]] || continue
    if ! check_task_dependencies "$id"; then
      [[ "$overall_rc" -eq 0 ]] && overall_rc=1
      continue
    fi
    run_task "$id"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      [[ "$overall_rc" -eq 0 ]] && overall_rc="$rc"
      if task_is_critical "$id"; then
        log_error "Critical task failed; stopping because ${TASK_LABEL[$id]} runs core setup."
        mark_unrun_dependants
        return "$rc"
      fi
      log_warn "Recorded failure for ${TASK_LABEL[$id]}; continuing with the remaining selected tasks."
    fi
  done

  return "$overall_rc"
}

print_log_error_excerpt() {
  local log_file="$1"
  local count=0
  local line

  if [[ -z "$log_file" || ! -f "$log_file" ]]; then
    printf "      No log file was created for this task.\n"
    return 0
  fi

  while IFS= read -r line; do
    printf "      %s\n" "$line"
    ((count++))
    ((count >= 8)) && break
  done < <(
    perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g' "$log_file" | awk '
      {
        lower = tolower($0)
        if ($0 ~ /✖ ERROR/ ||
            lower ~ /(^|[[:space:]])fatal:/ ||
            lower ~ /(^|[[:space:]])error:/ ||
            lower ~ /unknown plugins/ ||
            lower ~ /completed with issues/ ||
            lower ~ /failed installs/ ||
            lower ~ /traceback/ ||
            lower ~ /exception/ ||
            lower ~ /status[[:space:]]+.*failed/ ||
            lower ~ /launchpad status: failed/ ||
            $0 ~ /[[:alnum:]_.]+Error:/) {
          print
        }
      }
    '
  )

  if ((count == 0)); then
    printf "      No error-looking lines found; last log lines:\n"
    tail -n 8 "$log_file" | sed 's/^/      /'
  fi
}

print_problem_details() {
  local id
  local state
  local shown=0

  for id in "${TASK_ORDER[@]}"; do
    state="${TASK_STATUS[$id]:-}"
    [[ "$state" == "failed" || "$state" == "issues" || "$state" == "blocked" ]] || continue
    if ((shown == 0)); then
      printf "\n"
      log_warn "Captured problem details"
      shown=1
    fi
    printf "  - %s (%s, exit %s)\n" "${TASK_LABEL[$id]}" "$state" "${TASK_EXIT[$id]:--}"
    if [[ "$state" == blocked ]]; then
      printf "    Reason: %s\n" "${TASK_BLOCK_REASON[$id]}"
      continue
    fi
    printf "    Log file: %s\n" "${TASK_LOG[$id]:-not-created}"
    print_log_error_excerpt "${TASK_LOG[$id]:-}"
  done
}

print_summary_table_header() {
  printf "  %-24s %-10s %-6s %12s %s\n" "Task" "Status" "Exit" "Time (s)" "Log file"
  printf "  %-24s %-10s %-6s %12s %s\n" "------------------------" "----------" "------" "------------" "--------"
}

print_summary() {
  local id
  local task_state
  local success_count=0
  local failed_count=0
  local planned_count=0
  local skipped_count=0
  local issues_count=0
  local pending_count=0
  local blocked_count=0

  log_step "Launchpad summary"
  print_summary_table_header
  for id in "${TASK_ORDER[@]}"; do
    [[ -n "${SELECTED[$id]:-}" ]] || continue
    task_state="${TASK_STATUS[$id]:-not-run}"
    case "$task_state" in
      success) ((success_count++)) ;;
      failed) ((failed_count++)) ;;
      issues) ((issues_count++)) ;;
      planned) ((planned_count++)) ;;
      skipped) ((skipped_count++)) ;;
      blocked) ((blocked_count++)) ;;
      *) ((pending_count++)) ;;
    esac
    printf "  %-24s %-10s %-6s %12s %s\n" \
      "$id" \
      "$task_state" \
      "${TASK_EXIT[$id]:--}" \
      "${TASK_DURATION[$id]:--}" \
      "${TASK_LOG[$id]:--}"
  done

  printf "\n"
  printf "  Success: %d\n" "$success_count"
  printf "  Issues:  %d\n" "$issues_count"
  printf "  Failed:  %d\n" "$failed_count"
  printf "  Planned: %d\n" "$planned_count"
  printf "  Skipped: %d\n" "$skipped_count"
  printf "  Blocked: %d\n" "$blocked_count"
  printf "  Not run: %d\n" "$pending_count"
  printf "  Overall execution time (s): %s\n" "${RUN_DURATION:--}"
  printf "  Logs:    %s\n" "$RUN_ROOT"

  if (( issues_count > 0 )); then
    printf "\n"
    log_warn "Tasks completed with issues"
    for id in "${TASK_ORDER[@]}"; do
      [[ "${TASK_STATUS[$id]:-}" == "issues" ]] || continue
      printf "  - %s: review %s\n" "${TASK_LABEL[$id]}" "${TASK_LOG[$id]:-not-created}"
    done
  fi

  if (( failed_count > 0 )); then
    printf "\n"
    log_error "Tasks failed"
    for id in "${TASK_ORDER[@]}"; do
      [[ "${TASK_STATUS[$id]:-}" == "failed" ]] || continue
      printf "  - %s: review %s\n" "${TASK_LABEL[$id]}" "${TASK_LOG[$id]:-not-created}"
    done
  fi

  print_problem_details
}

main() {
  register_tasks

  if [[ -z "$PROFILE" ]]; then
    prompt_profile || return 1
  fi

  select_profile_tasks "$PROFILE" || return 1
  prompt_optional_tasks || return 1
  prompt_task_values || return 1
  initialize_run_directory || return 1
  print_plan || return 1

  confirm_plan
  local confirmation_rc=$?
  if [[ "$confirmation_rc" -eq 2 ]]; then
    return 1
  elif [[ "$confirmation_rc" -ne 0 ]]; then
    log_warn "Launchpad run canceled."
    exit 0
  fi

  RUN_STARTED_AT="$SECONDS"
  trap 'handle_run_signal 130' INT
  trap 'handle_run_signal 143' TERM
  trap 'handle_run_signal $?' EXIT
  run_selected_tasks
  local rc=$?
  trap - INT TERM EXIT
  printf -v RUN_DURATION '%.5f' "$((SECONDS - RUN_STARTED_AT))"
  print_summary
  return "$rc"
}

main "$@"
