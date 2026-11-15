#!/bin/zsh

source "${0:A:h}/branding.sh"
source <(sed '/^source /d; /^ebk_print_banner /d; /^main "\$@"$/d' "${0:A:h}/jenv_setup.sh")

mock_mode=""
mock_input=""

ebk_read_default() { REPLY="$mock_input"; }
sleep() { return 0; }
jenv() {
  printf '%s\n' "$*" >> "$mock_log"
  case "$1" in
    versions) printf '11\n21\n' ;;
    version-name) printf '21\n' ;;
    global) return 0 ;;
    rehash)
      if [[ "$mock_mode" == "error" ]]; then
        printf 'Permission denied\n'
        return 1
      fi
      if [[ "$mock_mode" == "locked" && "$2" != "--force" ]]; then
        printf "jenv: cannot rehash: /mock/shims/.jenv-shim exists, try 'jenv rehash --force' to override\n"
        return 1
      fi
      if [[ "$mock_mode" == "transient" && "$(grep -c '^rehash' "$mock_log")" == "1" ]]; then
        printf "jenv: cannot rehash: /mock/shims/.jenv-shim exists\n"
        return 1
      fi
      return 0
      ;;
  esac
}

mock_log="$(mktemp)"
trap 'rm -f "$mock_log"' EXIT
for mock_input in s skip; do
  : > "$mock_log"
  select_global_version || exit 1
  if grep -q '^global' "$mock_log"; then
    log_error "Skip changed the global version."
    exit 1
  fi
done

mock_input="11"
select_global_version || exit 1
grep -q '^global 11$' "$mock_log" || exit 1

mock_mode="transient"
: > "$mock_log"
rehash_jenv || exit 1
[[ "$(grep -c '^rehash' "$mock_log")" == "2" ]] || exit 1

mock_mode="error"
: > "$mock_log"
fail_count=0
if rehash_jenv; then
  log_error "Unrelated rehash failure was ignored."
  exit 1
fi
[[ "$fail_count" == "1" ]] || exit 1
grep -q -- '--force' "$mock_log" && exit 1

mock_mode="locked"
mock_input="n"
fail_count=0
: > "$mock_log"
if rehash_jenv; then
  log_error "Persistent lock was ignored."
  exit 1
fi
[[ "$fail_count" == "1" ]] || exit 1
grep -q -- '--force' "$mock_log" && exit 1
log_ok "jenv skip and rehash regression checks passed."
