# Copilot Instructions

## Repository Overview

This repository contains shell scripts and configuration files to bootstrap a productive macOS developer environment on Apple Silicon (M1/M2/M3/M4). The goal is to go from a fresh machine to a fully-configured environment with a single command.

## Project Structure

| File/Script | Purpose |
|---|---|
| `setup_env.sh` | Primary bootstrap script — installs 30+ tools via Homebrew (formulae and casks) |
| `git_setup.sh` | Configures global Git user credentials (name and email) |
| `jenv_setup.sh` | Discovers all installed JVMs and registers them with `jenv` |
| `dock_setup.sh` | Customizes the macOS Dock (icon size, apps, folders) with rollback support |
| `gen_dock_apps.sh` | Generates `dock_apps.txt` from the current Dock configuration |
| `vscode_setup.sh` | Installs VS Code extensions listed in `vscode.txt` |
| `conv-dot-to-png.sh` | Converts `triples.dot` to PNG using Graphviz |
| `colors.sh` | Defines ANSI color-code variables (ANSI escape codes and zsh prompt sequences) |
| `.zshrc` / `.bashrc` | Shell configuration files with aliases and environment setup |
| `dock_apps.txt` | List of full app paths to add/remove from the macOS Dock |
| `vscode.txt` | List of VS Code extension IDs to install |
| `lnav_format_python.json` | Custom `lnav` log format definition for the Python `logging` module pattern |
| `triples.dot` | Graphviz source file for a knowledge-graph diagram |
| `triples.png` | Rendered PNG output of `triples.dot` |
| `vscode-info.md` | Prompt templates used to generate VS Code extension documentation |
| `notes.md` | Reference notes covering Linux/macOS shell commands and concepts |
| `DETAILS.md` | Extended documentation: script details, Git aliases, package management tips |

## Coding Conventions

### Shell Scripts

- All scripts target **zsh** (`#!/bin/zsh`) except where Bash compatibility is required for Homebrew.
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
- Skip empty lines and comment lines when reading list files such as `vscode.txt` or `dock_apps.txt`.
- Keep scripts idempotent where possible (check before install/configure).
- Provide a rollback mechanism for destructive operations (see `dock_setup.sh` for an example using a plist backup).

### Configuration Files

- `vscode.txt`: one VS Code extension ID per line; inline comments after `#` are stripped by `vscode_setup.sh` at install time.
- `dock_apps.txt`: one **full application path** per line (e.g. `/Applications/Google\ Chrome.app`); lines prefixed with `--` instruct `dock_setup.sh` to **remove** that app from the Dock; use `SPACER` (case-insensitive) to insert a Dock spacer; blank lines are ignored.

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
