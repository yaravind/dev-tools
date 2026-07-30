#!/bin/zsh

# Shared CLI branding for dev-tools / Engineer Bootstrap Kit.

ebk_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ebk_theme_from_rgb() {
  local red="$1" green="$2" blue="$3"

  if [[ "$red" =~ '^[0-9]+$' && "$green" =~ '^[0-9]+$' && "$blue" =~ '^[0-9]+$' ]]; then
    if (( (red * 299 + green * 587 + blue * 114) / 1000 < 32768 )); then
      printf 'dark\n'
    else
      printf 'light\n'
    fi
    return 0
  fi

  return 1
}

ebk_detect_apple_terminal_theme() {
  local rgb red green blue

  [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]] || return 1
  ebk_command_exists osascript || return 1

  rgb="$(osascript -e 'tell application id "com.apple.Terminal" to if (count of windows) > 0 then get background color of selected tab of front window' 2>/dev/null)" || return 1
  rgb="${rgb// /}"
  red="${rgb%%,*}"
  rgb="${rgb#*,}"
  green="${rgb%%,*}"
  blue="${rgb##*,}"

  ebk_theme_from_rgb "$red" "$green" "$blue"
}

ebk_detect_theme() {
  local requested="${1:-${EBK_THEME:-auto}}"
  requested="${requested:l}"

  case "$requested" in
    dark|light)
      printf '%s\n' "$requested"
      return 0
      ;;
  esac

  if [[ -n "${COLORFGBG:-}" ]]; then
    local bg="${COLORFGBG##*;}"
    if [[ "$bg" =~ '^[0-9]+$' ]]; then
      if (( bg <= 7 )); then
        printf 'dark\n'
      else
        printf 'light\n'
      fi
      return 0
    fi
  fi

  if ebk_detect_apple_terminal_theme; then
    return 0
  fi

  if ebk_command_exists defaults; then
    if defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
      printf 'dark\n'
      return 0
    fi
    printf 'light\n'
    return 0
  fi

  printf 'dark\n'
}

ebk_set_palette() {
  local theme="${1:-dark}"
  EBK_THEME_SELECTED="$theme"

  if [[ -n "${NO_COLOR:-}" || ( ! -t 1 && "${EBK_FORCE_COLOR:-0}" != "1" ) ]]; then
    EBK_PRIMARY=''
    EBK_ACCENT=''
    EBK_TEXT=''
    EBK_MUTED=''
    EBK_BOLD=''
    EBK_PHASE_COLOR=''
    EBK_INFO_COLOR=''
    EBK_OK_COLOR=''
    EBK_WARN_COLOR=''
    EBK_ERROR_COLOR=''
    EBK_DEBUG_COLOR=''
    EBK_RESET=''
    return
  fi

  if [[ "$theme" == "light" ]]; then
    EBK_PRIMARY=$(printf '\033[0;35m')   # royal purple
    EBK_ACCENT=$(printf '\033[0;32m')    # mint-green approximation
    EBK_TEXT=''
    EBK_MUTED=$(printf '\033[0;90m')
    EBK_BOLD=$(printf '\033[1m')
    EBK_PHASE_COLOR="$EBK_PRIMARY"
    EBK_INFO_COLOR=$(printf '\033[0;34m')
    EBK_OK_COLOR="$EBK_ACCENT"
    EBK_WARN_COLOR=$(printf '\033[0;33m')
    EBK_ERROR_COLOR=$(printf '\033[0;31m')
    EBK_DEBUG_COLOR="$EBK_MUTED"
    EBK_RESET=$(printf '\033[0m')
  else
    EBK_PRIMARY=$(printf '\033[1;35m')   # bright royal purple
    EBK_ACCENT=$(printf '\033[1;32m')    # bright mint-green approximation
    EBK_TEXT=''
    EBK_MUTED=$(printf '\033[0;36m')
    EBK_BOLD=$(printf '\033[1m')
    EBK_PHASE_COLOR="$EBK_PRIMARY"
    EBK_INFO_COLOR=$(printf '\033[1;36m')
    EBK_OK_COLOR="$EBK_ACCENT"
    EBK_WARN_COLOR=$(printf '\033[1;33m')
    EBK_ERROR_COLOR=$(printf '\033[1;31m')
    EBK_DEBUG_COLOR="$EBK_MUTED"
    EBK_RESET=$(printf '\033[0m')
  fi
}

ebk_ensure_palette() {
  if [[ -z "${EBK_THEME_SELECTED:-}" ]]; then
    ebk_set_palette "$(ebk_detect_theme)"
  fi
}

ebk_log_phase() {
  ebk_ensure_palette
  printf '\n%s◆ PHASE %s%s\n' "$EBK_PHASE_COLOR" "$EBK_RESET" "$1"
}

ebk_log_info() {
  ebk_ensure_palette
  printf '%sℹ INFO  %s%s\n' "$EBK_INFO_COLOR" "$EBK_RESET" "$1"
}

ebk_log_ok() {
  ebk_ensure_palette
  printf '%s✓ OK    %s%s\n' "$EBK_OK_COLOR" "$EBK_RESET" "$1"
}

ebk_log_warn() {
  ebk_ensure_palette
  printf '%s⚠ WARN  %s%s\n' "$EBK_WARN_COLOR" "$EBK_RESET" "$1"
}

ebk_log_error() {
  ebk_ensure_palette
  printf '%s✖ ERROR %s%s\n' "$EBK_ERROR_COLOR" "$EBK_RESET" "$1" >&2
}

ebk_log_debug() {
  [[ "${EBK_DEBUG:-0}" == "1" ]] || return 0
  ebk_ensure_palette
  printf '%s• DEBUG %s%s\n' "$EBK_DEBUG_COLOR" "$EBK_RESET" "$1"
}

log_phase() { ebk_log_phase "$1"; }
log_step() { ebk_log_phase "$1"; }
log_info() { ebk_log_info "$1"; }
log_ok() { ebk_log_ok "$1"; }
log_warn() { ebk_log_warn "$1"; }
log_error() { ebk_log_error "$1"; }
log_debug() { ebk_log_debug "$1"; }

ebk_print_box_line() {
  local box_width="$1"
  local line="$2"
  local color="$3"
  local weight="$4"
  local pad
  pad=$(( box_width - ${#line} ))
  (( pad < 0 )) && pad=0

  printf '%s| %s%s%s%*s %s|%s\n' \
    "$EBK_PRIMARY" "$color" "$weight" "$line" "$pad" '' "$EBK_PRIMARY" "$EBK_RESET"
}

ebk_print_banner() {
  local script_name="${1:-${0:t}}"
  local box_width=60
  local tagline='Works after coffee.'
  local theme
  theme="$(ebk_detect_theme)"
  ebk_set_palette "$theme"

  printf '%s+--------------------------------------------------------------+%s\n' "$EBK_PRIMARY" "$EBK_RESET"
  ebk_print_box_line "$box_width" '     _                 _              _     ' "$EBK_ACCENT" ''
  ebk_print_box_line "$box_width" '  __| | _____   __    | |_ ___   ___ | |___ ' "$EBK_ACCENT" ''
  ebk_print_box_line "$box_width" ' / _` |/ _ \ \ / /____| __/ _ \ / _ \| / __|' "$EBK_ACCENT" ''
  ebk_print_box_line "$box_width" '| (_| |  __/\ V /_____| || (_) | (_) | \__ \' "$EBK_ACCENT" ''
  ebk_print_box_line "$box_width" ' \__,_|\___| \_/       \__\___/ \___/|_|___/' "$EBK_ACCENT" ''
  ebk_print_box_line "$box_width" "$tagline" "$EBK_TEXT" "$EBK_BOLD"
  printf '%s+--------------------------------------------------------------+%s\n' "$EBK_PRIMARY" "$EBK_RESET"
  printf '%sℹ INFO  %s%s (%s mode)%s\n' \
    "$EBK_INFO_COLOR" "$EBK_RESET" "$script_name" "$theme" "$EBK_RESET"
}
