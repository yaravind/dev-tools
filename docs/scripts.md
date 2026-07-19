---
title: Scripts
permalink: /scripts/
---

# Scripts

This file documents the repository's helper scripts and what they do. For usage details, run the individual scripts with `-Help` (Windows PowerShell scripts) or check the comments at the top of each script.

| Script Name                             | Description                                                                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/macos/setup_env.sh`            | Primary bootstrap script — installs and configures 30+ developer tools (JDK, Python, Rust, fonts, IDEs, shell utils) on macOS Apple Silicon |
| `scripts/macos/setup_env_min.sh`        | Minimal macOS bootstrap script for Git, JDK, Maven, VS Code, and IntelliJ IDEA                                                               |
| `scripts/macos/git_setup.sh`            | Configures global Git user credentials (name and email)                                                                                      |
| `scripts/macos/jenv_setup.sh`           | Discovers all installed JVMs and registers them with the `jenv` version manager                                                              |
| `scripts/macos/dock_setup.sh`           | Customizes the macOS Dock — sets icon size, removes defaults, and adds preferred apps from `config/dock_apps.txt`                            |
| `scripts/macos/gen_dock_apps.sh`        | Generates `config/dock_apps.txt` by reading the current Dock configuration                                                                    |
| `scripts/macos/vscode_setup.sh`         | Installs VS Code extensions from `config/vscode.txt` and applies managed VS Code settings from `config/vscode_settings.json`                  |
| `scripts/macos/intellij_setup.sh`       | Installs IntelliJ IDEA plugins from `config/intellij.txt` via IntelliJ CLI                                                                   |
| `scripts/macos/pycharm_setup.sh`        | Installs PyCharm plugins from `config/pycharm.txt` via PyCharm CLI                                                                            |
| `scripts/macos/conv-dot-to-png.sh`      | Converts `triples.dot` to a PNG image using Graphviz                                                                                          |
| `scripts/macos/colors.sh`               | Defines ANSI color code variables (sourced by other scripts)                                                                                 |
| `scripts/macos/backup_codex.sh`         | Backs up local `~/.codex` data to a specified target directory                                                                               |
| `scripts/macos/clone_github_repos.sh`   | Clones GitHub repositories listed in a file (`org/repo` format) into a destination directory                                                |
| `scripts/macos/pre_setup.sh`            | Prepares Apple Silicon Homebrew setup (`/opt/homebrew` ownership, install, and shell profile wiring)                                        |
| `scripts/macos/restore_codex.sh`        | Restores a full `.codex` backup into `~/.codex` with a safety backup and rollback on failure                                                |
| `scripts/macos/run_tests.sh`            | Runs macOS script validation checks (syntax, optional ShellCheck, config presence, and minimal dry-run verification)                        |
| `scripts/macos/setup_env_min_rollback.sh` | Rolls back minimal macOS bootstrap installs and performs Homebrew cleanup                                                                   |
| `scripts/macos/test_setup_env_min.sh`   | Safe verification harness for minimal setup checks without installing any tools                                                              |
| `scripts/macos/verify_codex_restore.sh` | Read-only diagnostics to verify restored `.codex` data integrity and related app profile/cache signals                                      |
| `scripts/windows/setup_env.ps1`         | Primary bootstrap script — installs and configures tools using winget on Windows                                                            |
| `scripts/windows/setup_env_min.ps1`     | Minimal Windows bootstrap script for Git, JDK, Maven, VS Code, and IntelliJ IDEA                                                             |
| `scripts/windows/run_vscode_setup.ps1`  | Installs VS Code extensions listed in `config/vscode.txt` (runs `vscode_setup.ps1` with `-Yes`)                                               |
| `scripts/windows/intellij_setup.ps1`    | Installs IntelliJ IDEA plugins from `config/intellij.txt` via IntelliJ CLI                                                                    |
| `scripts/windows/pycharm_setup.ps1`     | Installs PyCharm plugins from `config/pycharm.txt` via PyCharm CLI                                                                             |
| `scripts/windows/run_taskbar_setup.ps1` | Pins/unpins Windows Taskbar apps from `config/taskbar_apps.txt`                                                                               |


> Tip: For Windows PowerShell scripts, run them from an elevated PowerShell session and use `-Help` to see runtime options such as `-DryRun`, `-Interactive`, and `-Silent`.
