#!/bin/zsh

# Interactive macOS setup launchpad for the Engineer Bootstrap Kit.

set -u
set -o pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
SCRIPT_NAME="${0:A:t}"

source "${SCRIPT_DIR}/branding.sh"
ebk_print_banner "$SCRIPT_NAME"

DRY_RUN=0
CONTINUE_ON_ERROR=0
ASSUME_YES=0
PROFILE=""

RUN_ROOT="${REPO_ROOT}/.run/launchpad/$(date +%Y%m%d-%H%M%S)"

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

clone_destination=""
clone_repo_list=""
codex_backup_path=""

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
  --continue-on-error    Continue after a selected script fails
  --yes, -y              Do not ask for final launchpad confirmation
  --clone-destination D  Destination for clone_github_repos.sh
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
  fi
  SELECTED[$id]=1
}

select_with_deps() {
  local id="$1"
  local dep
  local deps="${TASK_DEPS[$id]:-}"

  for dep in ${=deps}; do
    select_with_deps "$dep"
    if [[ -z "${SELECTED[$dep]:-}" ]]; then
      INCLUDED_BY_DEP[$dep]=1
      SELECTED[$dep]=1
    fi
  done

  select_task "$id" 0
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

prompt_profile() {
  local choice

  log_step "Choose setup profile"
  printf "  1. full         - Homebrew, full tools, shell, macOS, Java, IDEs\n"
  printf "  2. minimal-java - Git, JDK 17, Maven, VS Code, IntelliJ CE, Git config, IDE plugins\n"
  printf "  3. ide-only     - VS Code, IntelliJ, and PyCharm plugin setup only\n"
  printf "  4. personalize  - Shell plugins, Dock, macOS settings, default apps\n"
  printf "  5. custom       - Choose individual tasks\n"
  printf "\nSelect profile [1-5] (default: full): "
  read -r choice

  case "$choice" in
    ""|1|full)
      PROFILE="full"
      ;;
    2|minimal-java)
      PROFILE="minimal-java"
      ;;
    3|ide-only)
      PROFILE="ide-only"
      ;;
    4|personalize)
      PROFILE="personalize"
      ;;
    5|custom)
      PROFILE="custom"
      ;;
    *)
      log_warn "Unknown selection '$choice'; using full."
      PROFILE="full"
      ;;
  esac
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

  printf "\nEnter comma-separated numbers or ids (example: 1,3,vscode_setup): "
  read -r selection

  if [[ -z "$selection" ]]; then
    log_warn "No custom tasks selected."
    return 0
  fi

  selection="${selection//,/ }"
  for token in ${=selection}; do
    if [[ "$token" =~ '^[0-9]+$' ]]; then
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

  if [[ ! -t 0 ]]; then
    return 0
  fi

  if [[ -z "${SELECTED[restore_codex]:-}" ]]; then
    printf "\nRestore a Codex backup as part of this run? (y/N): "
    read -r answer
    if [[ "$answer" =~ '^[Yy]$' ]]; then
      select_with_deps "restore_codex"
    fi
  fi
}

prompt_task_values() {
  local clone_answer

  if [[ -n "${SELECTED[clone_repos]:-}" && -t 0 ]]; then
    log_step "Clone GitHub repositories"
    printf "Clone repositories from config/github-repos.txt? (Y/n): "
    read -r clone_answer
    if [[ "$clone_answer" =~ '^[Nn]$' ]]; then
      unset 'SELECTED[clone_repos]'
      unset 'INCLUDED_BY_DEP[clone_repos]'
    elif [[ -z "$clone_destination" ]]; then
      printf "Directory to clone into [default: current directory]: "
      read -r clone_destination
      clone_destination="${clone_destination/#\~/$HOME}"
    fi
  fi

  if [[ -n "${SELECTED[restore_codex]:-}" && -z "$codex_backup_path" && ! -t 0 ]]; then
    log_error "Codex restore needs --codex-backup when stdin is not interactive."
    exit 1
  fi

  if [[ -n "${SELECTED[restore_codex]:-}" ]]; then
    while [[ -z "$codex_backup_path" ]]; do
      printf "\nCodex backup folder to restore from: "
      read -r codex_backup_path
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
      if [[ -n "$clone_destination" ]]; then
        cmd=(zsh "${SCRIPT_DIR}/clone_github_repos.sh" "$repo_list_arg" "$clone_destination")
      else
        cmd=(zsh "${SCRIPT_DIR}/clone_github_repos.sh" "$repo_list_arg")
      fi
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
      cmd=(bash "${SCRIPT_DIR}/vscode_setup.sh")
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

task_requires_admin() {
  local id="$1"
  [[ "${TASK_ADMIN[$id]:-0}" == "1" ]]
}

task_allows_issues() {
  local id="$1"
  [[ "${TASK_SOFT_FAIL[$id]:-0}" == "1" ]]
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
    log_error "Cannot request admin approval for ${TASK_LABEL[$id]} because stdin is not interactive."
    log_error "Run this task from an interactive terminal."
    return 1
  fi

  printf "Enable admin privileges for this step only? (y/N): "
  read -r answer
  if [[ ! "$answer" =~ '^[Yy]$' ]]; then
    log_warn "Skipping ${TASK_LABEL[$id]} without admin privileges."
    TASK_STATUS[$id]="skipped"
    return 2
  fi

  if sudo -v; then
    log_ok "Admin privileges enabled for this step."
    return 0
  fi

  log_error "Admin authentication failed for ${TASK_LABEL[$id]}."
  return 1
}

require_command() {
  local command_name="$1"
  local task_label="$2"
  if ! command_exists "$command_name"; then
    log_error "${task_label} requires '${command_name}' in PATH."
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
        log_error "Dock config not found: ${REPO_ROOT}/config/dock_apps.txt"
        return 1
      }
      ;;
    default_apps)
      require_command duti "${TASK_LABEL[$id]}" || return 1
      [[ -f "${REPO_ROOT}/config/default_apps_macos.txt" ]] || {
        log_error "Default apps config not found: ${REPO_ROOT}/config/default_apps_macos.txt"
        return 1
      }
      ;;
    jenv_setup)
      require_command jenv "${TASK_LABEL[$id]}" || return 1
      require_command xmllint "${TASK_LABEL[$id]}" || return 1
      [[ -x /usr/libexec/java_home ]] || {
        log_error "jenv setup requires /usr/libexec/java_home."
        return 1
      }
      ;;
    vscode_setup)
      require_command code "${TASK_LABEL[$id]}" || return 1
      require_command python3 "${TASK_LABEL[$id]}" || return 1
      ;;
    restore_codex)
      if [[ -z "$codex_backup_path" || ! -d "$codex_backup_path" ]]; then
        log_error "Codex backup folder not found: ${codex_backup_path}"
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

print_plan() {
  local id
  local index=1

  log_step "Run plan"
  print_profile_details
  printf "Profile: %s\n" "$PROFILE"
  printf "Mode: %s\n" "$([[ "$DRY_RUN" -eq 1 ]] && printf dry-run || printf execute)"
  printf "Continue on error: %s\n" "$([[ "$CONTINUE_ON_ERROR" -eq 1 ]] && printf yes || printf no)"
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

  printf "\nProceed with this launchpad run? (y/N): "
  read -r answer
  [[ "$answer" =~ '^[Yy]$' ]]
}

run_task() {
  local id="$1"
  local log_file="${RUN_ROOT}/${id}.log"
  local started_at="$SECONDS"
  local rc

  build_command "$id" || {
    TASK_STATUS[$id]="failed"
    return 1
  }

  TASK_LOG[$id]="$log_file"

  log_step "Running ${TASK_LABEL[$id]}"
  log_info "Log: ${log_file}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    TASK_STATUS[$id]="planned"
    printf "[dry-run] "
    print_command "$id"
    return 0
  fi

  authorize_admin_for_task "$id"
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    return 0
  elif [[ "$rc" -ne 0 ]]; then
    TASK_STATUS[$id]="failed"
    return "$rc"
  fi

  if ! check_task_ready "$id"; then
    TASK_STATUS[$id]="failed"
    return 1
  fi

  mkdir -p "$RUN_ROOT" || return 1
  {
    printf 'Task: %s\n' "$id"
    printf 'Started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Command: '
    print_command "$id"
    printf '\n'
  } > "$log_file"

  "${cmd[@]}" 2>&1 | tee -a "$log_file"
  rc=${pipestatus[1]}

  {
    printf '\nFinished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Duration seconds: %d\n' $((SECONDS - started_at))
    printf 'Exit code: %d\n' "$rc"
  } >> "$log_file"

  if [[ "$rc" -eq 0 ]]; then
    TASK_STATUS[$id]="success"
    log_ok "${TASK_LABEL[$id]} completed."
  elif task_allows_issues "$id"; then
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

  if [[ "$(selected_task_count)" -eq 0 ]]; then
    log_warn "No tasks selected. Nothing to run."
    return 0
  fi

  for id in "${TASK_ORDER[@]}"; do
    [[ -n "${SELECTED[$id]:-}" ]] || continue
    run_task "$id"
    rc=$?
    if [[ "$rc" -ne 0 && "$CONTINUE_ON_ERROR" -ne 1 ]]; then
      log_error "Stopping after failure. Re-run with --continue-on-error to keep going."
      return "$rc"
    fi
  done
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

  log_step "Launchpad summary"
  for id in "${TASK_ORDER[@]}"; do
    [[ -n "${SELECTED[$id]:-}" ]] || continue
    task_state="${TASK_STATUS[$id]:-not-run}"
    case "$task_state" in
      success) ((success_count++)) ;;
      failed) ((failed_count++)) ;;
      issues) ((issues_count++)) ;;
      planned) ((planned_count++)) ;;
      skipped) ((skipped_count++)) ;;
      *) ((pending_count++)) ;;
    esac
    printf "  %-24s %s" "$id" "$task_state"
    [[ -n "${TASK_LOG[$id]:-}" ]] && printf "  %s" "${TASK_LOG[$id]}"
    printf "\n"
  done

  printf "\n"
  printf "  Success: %d\n" "$success_count"
  printf "  Issues:  %d\n" "$issues_count"
  printf "  Failed:  %d\n" "$failed_count"
  printf "  Planned: %d\n" "$planned_count"
  printf "  Skipped: %d\n" "$skipped_count"
  printf "  Not run: %d\n" "$pending_count"
  printf "  Logs:    %s\n" "$RUN_ROOT"

  if (( issues_count > 0 )); then
    printf "\n"
    log_warn "Tasks completed with issues"
    for id in "${TASK_ORDER[@]}"; do
      [[ "${TASK_STATUS[$id]:-}" == "issues" ]] || continue
      printf "  - %s: review %s\n" "${TASK_LABEL[$id]}" "${TASK_LOG[$id]}"
    done
  fi

  if (( failed_count > 0 )); then
    printf "\n"
    log_error "Tasks failed"
    for id in "${TASK_ORDER[@]}"; do
      [[ "${TASK_STATUS[$id]:-}" == "failed" ]] || continue
      printf "  - %s: review %s\n" "${TASK_LABEL[$id]}" "${TASK_LOG[$id]}"
    done
  fi
}

main() {
  register_tasks

  if [[ -z "$PROFILE" ]]; then
    prompt_profile
  fi

  select_profile_tasks "$PROFILE"
  prompt_optional_tasks
  prompt_task_values
  print_plan

  if ! confirm_plan; then
    log_warn "Launchpad run canceled."
    exit 0
  fi

  run_selected_tasks
  local rc=$?
  print_summary
  return "$rc"
}

main "$@"
