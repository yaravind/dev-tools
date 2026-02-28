# Copilot Instructions

## Repo quick facts
- Purpose: cross-platform bootstrap for macOS (zsh) and Windows (PowerShell) using Homebrew/winget.
- Layout: scripts/macos/, scripts/windows/, config/, docs/, assets/, .github/workflows/.

## macOS (zsh) conventions
- Shebang `#!/bin/zsh`; use `command_exists(){ command -v "$1" >/dev/null 2>&1; }`.
- Log prefix `===>`; colors from scripts/macos/colors.sh or inline (`$RED/$YELLOW/$GREEN/$CYAN/$MAGENTA/$NC`).
- Use printf with args (`printf '===> %s\n' "$msg"`), skip blank/comment lines when reading config lists.
- Idempotent installs; rollback for destructive ops (see dock_setup.sh plist backup).
- Resolve config paths relative to script dir: `${0:A:h}/../config/`.

## Windows (PowerShell) conventions
- Target PS 5.1+; require admin; `Set-ExecutionPolicy Bypass -Scope Process -Force`.
- Logging helpers: Write-Step (Magenta), Write-Info (Cyan), Write-Ok (Green), Write-Warn (Yellow); errors with `Write-Host "ERROR: ..." -ForegroundColor Red`.
- `Test-CommandExists` helper; `winget install --id "$Id" --exact --accept-source-agreements --accept-package-agreements --silent`; treat exit code -1978335189 as already installed.
- Persist env vars with `[Environment]::SetEnvironmentVariable(name, value, "User")`.

## Config files
- config/vscode.txt: one VS Code extension ID per line; ignore blanks/comments.
- config/dock_apps.txt: full app path per line; `--` prefix removes; `SPACER` inserts spacer; ignore blanks.

## Tests and CI
- Local: `zsh scripts/macos/run_tests.sh`; `pwsh scripts/windows/run_tests.ps1`.
- Lint: ShellCheck for `.sh`; PSScriptAnalyzer for `.ps1` (add to CI when available).
- CI workflow: .github/workflows/script-tests.yml should run macOS and Windows harnesses (and ShellCheck when configured).
