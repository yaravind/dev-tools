#!/bin/zsh

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$(printf '\033[0;31m')
  GREEN=$(printf '\033[0;32m')
  YELLOW=$(printf '\033[1;33m')
  CYAN=$(printf '\033[0;36m')
  MAGENTA=$(printf '\033[0;35m')
  RESET=$(printf '\033[0m')
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  MAGENTA=''
  RESET=''
fi

log_step() {
  printf '\n%s===> %s%s\n' "$MAGENTA" "$1" "$RESET"
}

log_info() {
  printf '%sINFO: %s%s\n' "$CYAN" "$1" "$RESET"
}

log_ok() {
  printf '%sOK: %s%s\n' "$GREEN" "$1" "$RESET"
}

log_warn() {
  printf '%sWARN: %s%s\n' "$YELLOW" "$1" "$RESET"
}

log_error() {
  printf '%sERROR: %s%s\n' "$RED" "$1" "$RESET" >&2
}

fail_count=0

record_failure() {
  log_error "$1"
  fail_count=$((fail_count + 1))
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    record_failure "$1 is not installed or is not in PATH."
    return 1
  fi
}

ensure_jenv_init_in_zshrc() {
  local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
  local init_line='eval "$(jenv init -)"'

  if [[ -f "$zshrc" ]] && grep -Fq 'jenv init -' "$zshrc"; then
    log_ok "jenv init is already configured in $zshrc."
    return 0
  fi

  if {
    printf '\n# jenv: initialize shims and shell integration\n'
    printf '%s\n' "$init_line"
  } >> "$zshrc"; then
    log_ok "Added jenv init to $zshrc."
  else
    record_failure "Failed to add jenv init to $zshrc."
    return 1
  fi
}

initialize_jenv() {
  local init_script

  JENV_ROOT="${JENV_ROOT:-$(jenv root 2>/dev/null)}"
  if [[ -z "$JENV_ROOT" ]]; then
    record_failure "Unable to determine jenv root."
    return 1
  fi

  export JENV_ROOT
  case ":$PATH:" in
    *":$JENV_ROOT/shims:"*) ;;
    *) export PATH="$JENV_ROOT/shims:$PATH" ;;
  esac

  init_script="$(jenv init -)"
  if eval "$init_script" >/dev/null 2>&1; then
    log_ok "jenv initialized for this shell."
  else
    record_failure "Failed to initialize jenv for this shell."
    return 1
  fi
}

add_java_runtime() {
  local java_path="$1"
  local output

  if [[ ! -d "$java_path" ]]; then
    record_failure "JAVA_PATH ($java_path) does not exist or is not a directory."
    return 1
  fi

  log_info "Adding Java runtime: $java_path"
  if output=$(jenv add "$java_path" 2>&1); then
    log_ok "jenv add completed for $java_path."
  else
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    record_failure "Failed to add $java_path to jenv."
    return 1
  fi
}

select_global_version() {
  local global_ver

  while true; do
    printf '\n%sINFO: Choose the version (from above) to set as global version: %s' "$CYAN" "$RESET"
    if ! read global_ver; then
      record_failure "No global Java version was provided."
      return 1
    fi

    if [[ -z "$global_ver" ]]; then
      log_warn "No version entered."
      continue
    fi

    if jenv versions --bare | grep -Fxq -- "$global_ver"; then
      break
    fi

    log_warn "Version '$global_ver' is not managed by jenv. Choose one from the list above."
  done

  if jenv global "$global_ver"; then
    log_ok "Set global Java version to $global_ver."
  else
    record_failure "Failed to set global Java version to $global_ver."
    return 1
  fi

  jenv rehash
  hash -r
}

enable_jenv_plugin() {
  local plugin="$1"
  local output

  if ! jenv commands | grep -Fxq 'enable-plugin'; then
    record_failure "jenv enable-plugin is unavailable. Check jenv installation and shell initialization."
    return 1
  fi

  if output=$(jenv enable-plugin "$plugin" 2>&1); then
    log_ok "Enabled jenv plugin: $plugin."
  else
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    record_failure "Failed to enable jenv plugin: $plugin."
    return 1
  fi
}

verify_jenv_state() {
  log_step "Verifying jenv installation"
  jenv doctor || record_failure "jenv doctor reported issues."

  log_step "Verifying selected Java"
  log_info "jenv version: $(jenv version)"
  log_info "java resolved by jenv: $(jenv which java)"
  java -version || record_failure "java -version failed."

  JAVA_HOME="$(jenv javahome 2>/dev/null)"
  if [[ -n "$JAVA_HOME" ]]; then
    export JAVA_HOME
    log_ok "JAVA_HOME=$JAVA_HOME"
  else
    record_failure "jenv javahome did not return a JAVA_HOME value."
  fi
}

main() {
  require_command jenv
  require_command xmllint
  [[ -x /usr/libexec/java_home ]] || record_failure "/usr/libexec/java_home is not available."

  if [[ "$fail_count" -gt 0 ]]; then
    exit 1
  fi

  log_step "Initializing jenv"
  initialize_jenv || exit 1
  ensure_jenv_init_in_zshrc

  log_step "Adding installed Java runtimes"
  local xml_output
  if ! xml_output=$(/usr/libexec/java_home --xml 2>&1); then
    printf '%s\n' "$xml_output" >&2
    record_failure "Failed to list installed Java runtimes."
    exit 1
  fi

  local java_paths_output
  if ! java_paths_output=$(printf '%s' "$xml_output" | xmllint --xpath '//array/dict/key[text()="JVMHomePath"]/following-sibling::string[1]/text()' - 2>&1); then
    printf '%s\n' "$java_paths_output" >&2
    record_failure "Failed to parse installed Java runtime paths."
    exit 1
  fi

  local java_paths
  java_paths=(${=java_paths_output})
  if [[ "${#java_paths[@]}" -eq 0 ]]; then
    record_failure "No installed Java runtimes were found."
    exit 1
  fi

  local java_path
  for java_path in "${java_paths[@]}"; do
    add_java_runtime "$java_path"
  done

  log_step "Available jenv versions"
  jenv versions

  select_global_version || exit 1

  log_step "Enabling jenv plugins"
  enable_jenv_plugin export
  enable_jenv_plugin maven

  verify_jenv_state

  if [[ "$fail_count" -gt 0 ]]; then
    log_error "Completed with $fail_count error(s)."
    exit 1
  fi

  log_ok "Awesome, all set."
}

main "$@"
