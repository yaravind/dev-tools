# Copilot Instructions

## Repository Overview

This repository contains shell scripts and configuration files to bootstrap a productive macOS developer environment on Apple Silicon (M1/M2/M3/M4). The goal is to go from a fresh machine to a fully-configured environment with a single command.

## Project Structure

| File/Script | Purpose |
|---|---|
| `setup_env.sh` | Primary bootstrap script — installs 30+ tools via Homebrew (formulae and casks) |
| `git_setup.sh` | Configures global Git user credentials (name and email) |
| `jenv_setup.sh` | Discovers all installed JVMs and registers them with `jenv` |
| `dock_setup.sh` | Customizes the macOS Dock (icon size, apps, folders) |
| `gen_dock_apps.sh` | Generates `dock_apps.txt` from the current Dock configuration |
| `vscode_setup.sh` | Installs VS Code extensions listed in `vscode.txt` |
| `conv-dot-to-png.sh` | Converts `triples.dot` to PNG using Graphviz |
| `colors.sh` | Defines ANSI color-code variables sourced by other scripts |
| `.zshrc` / `.bashrc` | Shell configuration files with aliases and environment setup |
| `dock_apps.txt` | List of app names to add to the macOS Dock |
| `vscode.txt` | List of VS Code extension IDs to install |

## Coding Conventions

### Shell Scripts

- All scripts target **zsh** (`#!/bin/zsh`) except where Bash compatibility is required for Homebrew.
- Source `colors.sh` at the top of every script that needs colored output: `source colors.sh`.
- Use the ANSI color variables defined in `colors.sh` for all terminal output:
  - `$RED` — errors
  - `$GOLD` / `$YELLOW` — warnings
  - `$GREEN` — success
  - `$CYAN` / `$BLUE` — informational steps
  - `$UMAGENTA` — section headers / important steps
  - `$RESET` — reset color after each message
- Print messages with `echo -e` or `printf`. **Do not** embed variables directly in `printf` format strings — use `printf '..%s..' "$foo"` instead.
- Prefix every log line with `===>` for consistency with the existing scripts.
- Wrap tool availability checks in a `command_exists()` helper (`command -v "$1" >/dev/null 2>&1`).
- Skip empty lines and comment lines (prefixed with `#`) when reading list files such as `vscode.txt` or `dock_apps.txt`.
- Keep scripts idempotent where possible (check before install/configure).

### Configuration Files

- `vscode.txt`: one extension ID per line; inline comments are allowed after a `#`.
- `dock_apps.txt`: one application name per line; comment lines start with `--`; use `SPACER` for Dock spacers.

## Platform

- **OS**: macOS (Apple Silicon — M1/M2/M3/M4)
- **Shell**: zsh (default on macOS Catalina+)
- **Package manager**: [Homebrew](https://brew.sh/) — use `brew install` for CLI tools and `brew install --cask` for GUI apps.
- Scripts are **not** intended to run on Linux or Intel Macs without modification.

## Key Dependencies

- Homebrew must be installed before running any script.
- `dockutil` is required by `dock_setup.sh`.
- `jenv` is required by `jenv_setup.sh`.
- `graphviz` is required by `conv-dot-to-png.sh`.
- VS Code (`code` CLI) must be on `$PATH` for `vscode_setup.sh`.
