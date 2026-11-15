#!/bin/zsh

source "${0:A:h}/branding.sh"
source <(sed '/^source /d; /^ebk_print_banner /d; /^main "\$@"$/d' "${0:A:h}/launchpad.sh")

test_root="$(mktemp -d)"
trap 'rm -f "$test_root/bin/brew" "$test_root/bin/new-tool"; rmdir "$test_root/bin" "$test_root"' EXIT
mkdir "$test_root/bin"
printf '#!/bin/zsh\nprint -r -- "%s"\n' "$test_root" > "$test_root/bin/brew"
printf '#!/bin/zsh\nexit 0\n' > "$test_root/bin/new-tool"
chmod +x "$test_root/bin/brew" "$test_root/bin/new-tool"
register_tasks
original_path="$PATH"
brew() { "$test_root/bin/brew" "$@"; }
# command -v returns the function name, which resolves to the fake brew.
refresh_install_environment pre_setup || exit 1
command_exists new-tool || exit 1
[[ "$HOMEBREW_PREFIX" == "$test_root" && "$PATH" == *"$original_path"* ]] || exit 1
refresh_install_environment pre_setup || exit 1
matches=("${(@M)path:#$test_root/bin}")
[[ "${#matches}" == 1 ]] || exit 1
brew() { return 1; }
if refresh_install_environment pre_setup; then
  log_error "Expected an environment refresh failure."
  exit 1
fi
refresh_install_environment git_setup || exit 1
log_ok "Launchpad environment regression checks passed."
