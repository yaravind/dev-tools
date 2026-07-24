# Copilot Instructions

## Repo quick facts
- Purpose: cross-platform bootstrap for macOS (zsh) and Windows (PowerShell) using Homebrew/winget.
- Layout: scripts/macos/, scripts/windows/, config/, docs/, assets/, .github/workflows/.

## Branding and logging defaults (locked)
- Keep repository identity as **dev-tools** (do not rename commands/URLs).
- Primary tagline is **"Works on my machine. And yours."**
- Visual direction is **Premium + Polished** with **Royal Purple + Mint Green** accents that work in dark/light terminals.
- Keep the shared boxed ASCII `dev-tools` banner in `scripts/macos/branding.sh`, `scripts/macos/branding_bash.sh`, and `scripts/windows/branding.ps1`, and print it once per script invocation.
- Runtime logs use Option 2 symbols and levels: `◆ PHASE`, `ℹ INFO`, `✓ OK`, `⚠ WARN`, `✖ ERROR` (optional `• DEBUG` with `EBK_DEBUG=1`).
- Do not reintroduce legacy `===>`/`==>` runtime prefixes.
- Normalize external `Warning:` lines to `⚠ WARN` where feasible.
- Keep structured final reports (status/counts/duration) consistent across macOS and Windows setup/install scripts.
- GitHub Pages branding should stay aligned with CLI branding (see `_config.yml` and `_includes/head-custom.html`).
- For performance-sensitive setup paths, prefer bulk package-state queries/caches over repeated per-item package manager calls.

## macOS (zsh) conventions
- Shebang `#!/bin/zsh`; use `command_exists(){ command -v "$1" >/dev/null 2>&1; }`.
- Use shared branding log helpers from `scripts/macos/branding.sh` / `scripts/macos/branding_bash.sh` for log format and colors.
- Skip blank/comment lines when reading config lists.
- Idempotent installs; rollback for destructive ops (see dock_setup.sh plist backup).
- Resolve config paths relative to script dir: `${0:A:h}/../config/`.

## Windows (PowerShell) conventions
- Target PS 5.1+; require admin; `Set-ExecutionPolicy Bypass -Scope Process -Force`.
- Use shared branding log helpers from `scripts/windows/branding.ps1` (`Write-EbkPhase`, `Write-EbkInfo`, `Write-EbkOk`, `Write-EbkWarn`, `Write-EbkError`).
- `Test-CommandExists` helper; `winget install --id "$Id" --exact --accept-source-agreements --accept-package-agreements --silent`; treat exit code -1978335189 as already installed.
- Persist env vars with `[Environment]::SetEnvironmentVariable(name, value, "User")`.

## Config files
- config/vscode.txt: one VS Code extension ID per line; ignore blanks/comments.
- config/dock_apps.txt: full app path per line; `--` prefix removes; `SPACER` inserts spacer; ignore blanks.
- config/intellij.txt: IntelliJ IDEA plugin IDs, one per line. Each line must be prefixed with `community:` or `ultimate:`. Community mode installs only `community:` entries; ultimate mode installs both.
- config/pycharm.txt: PyCharm plugin IDs, one per line. Each line must be prefixed with `community:` or `professional:`. Community mode installs only `community:` entries; professional mode installs both.

## JetBrains CLI conventions (intellij_setup.sh, pycharm_setup.sh)
- Always resolve the **native app binary** (`/Applications/IntelliJ IDEA.app/Contents/MacOS/idea`, `/Applications/PyCharm.app/Contents/MacOS/pycharm`). Never use the Homebrew wrapper (`idea`, `charm`) for `installPlugins` — the `open -na` wrapper does not reliably return exit codes or install output.
- `installPlugins` output is very noisy (JVM deprecation warnings, IntelliJ internal `WARN` logs, `ClassNotFoundException` stack traces). These are harmless startup-time exceptions from the running plugin environment, not script errors. Filter them from displayed output using `grep -Ev` on: timestamp-prefixed `WARN` lines, `    at ` stack frames, `java.`/`kotlin.` exception headers, `Caused by:`, and `WARNING:`.
- Always inspect the **raw** (unfiltered) output for outcome detection: `already installed`, `unknown plugins`, and exit code.
- Three install outcomes to handle: `already installed` (return 2 / skip), `unknown plugins` (return 3 / warn — plugin ID not in Marketplace), generic failure (return 1 / error).
- `intellij.indexing.shared` is an internal platform module, not a Marketplace plugin — it cannot be installed via `installPlugins` and should not be in config.
- Both scripts support interactive mode selection printed at startup (before any other work); default is the higher-tier mode (`--ultimate` / `--professional`).

## zsh pitfalls
- `status` is a **reserved read-only variable** in zsh. Never use it as a local variable to capture exit codes. Use `install_exit_code` or any other name instead.

## Fork ribbon (site-wide)
- A small "Fork me" ribbon is injected site-wide from `_includes/head-custom.html`.
- It uses `site.social.github` (owner/repo) or `site.github` in `_config.yml` to build the GitHub URL.
- New pages automatically receive the ribbon without editing layouts. To disable the ribbon for a single page, add the following to the page's front matter:

```yaml
fork_ribbon: false
```

And then in `_includes/head-custom.html` you can check `page.fork_ribbon` and skip injection if set to `false`.

## Tests and CI
- Local: `zsh scripts/macos/run_tests.sh`; `pwsh scripts/windows/run_tests.ps1`.
- Lint: ShellCheck for `.sh`; PSScriptAnalyzer for `.ps1` (add to CI when available).
- CI workflow: .github/workflows/script-tests.yml should run macOS and Windows harnesses (and ShellCheck when configured).
