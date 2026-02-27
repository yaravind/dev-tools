# Copilot Instructions

## Repository Overview

This repository contains scripts and configuration files to bootstrap a productive developer environment on **macOS (Apple Silicon)** and **Windows 10/11**. The goal is to go from a fresh machine to a fully-configured environment with a single command.

## Project Structure

```
dev-tools/
├── scripts/          # All executable scripts (macOS .sh and Windows .ps1)
├── config/           # Configuration files consumed by scripts
├── docs/             # Reference documentation and notes
├── assets/           # Images and other static assets
├── DETAILS.md        # Extended documentation: script details, Git aliases, package management tips
└── README.md         # Setup instructions for both platforms
```

### Scripts (`scripts/`)

| Script | Platform | Purpose |
|---|---|---|
| `setup_env.sh` | macOS | Primary bootstrap script — installs 30+ tools via Homebrew (formulae and casks) |
| `setup_env.ps1` | Windows | Primary bootstrap script — installs tools via `winget` (CLI tools and GUI apps) |
| `git_setup.sh` | macOS | Configures global Git user credentials (name and email) |
| `jenv_setup.sh` | macOS | Discovers all installed JVMs and registers them with `jenv` |
| `jenv_setup.ps1` | Windows | Discovers all installed JDKs and registers them with [JEnv-for-Windows](https://github.com/FelixSelter/JEnv-for-Windows) |
| `dock_setup.sh` | macOS | Customizes the macOS Dock (icon size, apps, folders) with rollback support |
| `gen_dock_apps.sh` | macOS | Generates `config/dock_apps.txt` from the current Dock configuration |
| `vscode_setup.sh` | macOS | Installs VS Code extensions listed in `config/vscode.txt` |
| `conv-dot-to-png.sh` | macOS | Converts `assets/triples.dot` to PNG using Graphviz |
| `colors.sh` | macOS | Defines ANSI color-code variables (ANSI escape codes and zsh prompt sequences) |

### Configuration (`config/`)

| File | Purpose |
|---|---|
| `config/.zshrc` | zsh configuration with aliases and environment setup |
| `config/.bashrc` | bash configuration with aliases and environment setup |
| `config/dock_apps.txt` | List of full app paths to add/remove from the macOS Dock |
| `config/vscode.txt` | List of VS Code extension IDs to install |
| `config/lnav_format_python.json` | Custom `lnav` log format definition for the Python `logging` module pattern |

### Documentation (`docs/`)

| File | Purpose |
|---|---|
| `docs/vscode-info.md` | Prompt templates used to generate VS Code extension documentation |
| `docs/notes.md` | Reference notes covering Linux/macOS shell commands and concepts |

### Assets (`assets/`)

| File | Purpose |
|---|---|
| `assets/triples.dot` | Graphviz source file for a knowledge-graph diagram |
| `assets/triples.png` | Rendered PNG output of `triples.dot` |

## Coding Conventions

### Shell Scripts (macOS — zsh)

- All macOS scripts target **zsh** (`#!/bin/zsh`) except where Bash compatibility is required for Homebrew.
- `colors.sh` defines ANSI escape code variables for use with `echo -e` / `printf`. Source it when needed: `source colors.sh`.
- Some scripts (e.g. `vscode_setup.sh`, `dock_setup.sh`) define their own inline color variables instead of sourcing `colors.sh`. Use `$NC` (No Color) as the reset variable when defining colors inline in that style.
- Color semantics used across scripts:
  - `$RED` — errors
  - `$GOLD` / `$YELLOW` — warnings / skipped items
  - `$GREEN` — success
  - `$CYAN` / `$BLUE` — informational steps / commands being run
  - `$MAGENTA` / `$UMAGENTA` — section headers / important steps
  - `$RESET` / `$NC` — reset color after each message
- Print messages with `echo -e` or `printf`. **Do not** embed variables directly in `printf` format strings — use `printf '..%s..' "$foo"` instead.
- Prefix every log line with `===>` or `==>` for consistency with the existing scripts.
- Wrap tool availability checks in a `command_exists()` helper (`command -v "$1" >/dev/null 2>&1`) or use `command -v tool &>/dev/null` inline.
- Skip empty lines and comment lines when reading list files such as `config/vscode.txt` or `config/dock_apps.txt`.
- Keep scripts idempotent where possible (check before install/configure).
- Provide a rollback mechanism for destructive operations (see `dock_setup.sh` for an example using a plist backup).
- Scripts reference config files relative to their own location using `${0:A:h}/../config/`.

### PowerShell Scripts (Windows)

- All Windows scripts target **PowerShell 5.1+** (PowerShell 7+ recommended).
- Use the shared helper functions defined in each script for consistent output:
  - `Write-Step` (Magenta) — major section headers
  - `Write-Info` (Cyan) — informational steps / commands being run
  - `Write-Ok` (Green) — success messages
  - `Write-Warn` (Yellow) — warnings / skipped items
  - Use `Write-Host "ERROR: ..." -ForegroundColor Red` directly for error messages
- Prefix every log line with `===>` for consistency with the macOS shell scripts.
- Use `Test-CommandExists` helper (`$null -ne (Get-Command $Command -ErrorAction SilentlyContinue)`) to check tool availability.
- Use `winget install --id "$Id" --exact --accept-source-agreements --accept-package-agreements --silent` for package installation.
- Handle `winget` exit code `-1978335189` (already installed) as a non-error skip condition.
- Keep scripts idempotent — check before install/configure.
- Use `[Environment]::SetEnvironmentVariable(name, value, "User")` to persist environment variables.
- Scripts must be run **as Administrator** with `Set-ExecutionPolicy Bypass -Scope Process -Force`.

### Configuration Files

- `config/vscode.txt`: one VS Code extension ID per line; blank lines are ignored.
- `config/dock_apps.txt`: one **full application path** per line (e.g. `/Applications/Google Chrome.app`); lines prefixed with `--` instruct `dock_setup.sh` to **remove** that app from the Dock; use `SPACER` (case-insensitive) to insert a Dock spacer; blank lines are ignored.

## Platform

### macOS
- **OS**: macOS (Apple Silicon — M1/M2/M3/M4)
- **Shell**: zsh (default on macOS Catalina+)
- **Package manager**: [Homebrew](https://brew.sh/) — use `brew install` for CLI tools and `brew install --cask` for GUI apps.

### Windows
- **OS**: Windows 10 (version 1809+) or Windows 11
- **Shell**: PowerShell 5.1+ (PowerShell 7+ recommended)
- **Package manager**: [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) — use `winget install --id <Id> --exact` for both CLI tools and GUI apps.

## Key Dependencies

### macOS
- Homebrew must be installed before running any script.
- `dockutil` is required by `dock_setup.sh`.
- `jenv` is required by `jenv_setup.sh`.
- `graphviz` is required by `conv-dot-to-png.sh`.
- VS Code (`code` CLI) must be on `$PATH` for `vscode_setup.sh`.

### Windows
- `winget` (App Installer) must be available before running any script.
- PowerShell must be run as Administrator.
- [JEnv-for-Windows](https://github.com/FelixSelter/JEnv-for-Windows) is installed automatically by `setup_env.ps1` and `jenv_setup.ps1`.
