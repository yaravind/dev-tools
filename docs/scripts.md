---
title: Scripts
permalink: /scripts/
---

# Scripts

This file documents the repository's helper scripts and what they do. For usage details, run the individual scripts with `-Help` (Windows PowerShell scripts) or check the comments at the top of each script.

The launchpads default to the full profile; repository cloning is opt-in, and Codex restore is opt-in. The macOS Dock setup defaults to skipping changes unless explicitly approved. Git and JetBrains setup prompts retain their displayed defaults. jenv suggests the currently selected version and accepts another selection.

Final launchpad confirmation defaults to `y` on both platforms. The macOS per-step admin approval also defaults to `y`; edit it to `n` to skip that admin-scoped step. This does not bypass sudo authentication.

Both launchpad summaries include a `Time (s)` column and overall execution time, in seconds with five decimal places. Per-task time includes preparation, prompts, and execution (or dry-run planning); tasks never reached show `-`. Each task log records the same duration. Overall time covers the task execution phase, including skipped attempts and between-task overhead, but excludes initial profile selection and final confirmation.

After successful installation phases, launchpad refreshes its own tool environment before starting subsequent tasks. macOS resolves the Homebrew prefix and adds its binary directories; Windows merges persisted machine/user PATH entries with existing session entries and refreshes persisted JAVA_HOME. Refresh failures are reported as task failures.

Launchpad treats log creation/write errors and child-start/output-capture errors as failures, not successful installs. Child exit codes are retained separately from infrastructure errors. Task timing is finalized on failure; Windows finalizes the overall summary in `finally`, and macOS prints an interrupted-run summary on SIGINT/SIGTERM (exit 130/143). Forced process termination cannot guarantee a final summary.

Both platforms stop after core setup failures, including minimal Java installation. `--continue-on-error` / `-ContinueOnError` remain accepted for compatibility but do not override critical failures; non-critical failures continue by default. Declared prerequisites must succeed (or be planned in dry-run mode). Unmet prerequisites produce a separate `blocked` status, reason, and count; blocked tasks are not executed or timed and make the run unsuccessful. Tasks unrelated to a non-critical failure can still run.

Invalid profile and yes/no answers reprompt; EOF or canceled input stops preparation with a nonzero exit instead of choosing a broad profile or looping. `--yes` / `-Yes` skip only the final launchpad confirmation, not profile selection, child-script confirmations, or admin approval. They are not unattended-install flags. Use an explicit profile for redirected runs; cloning requires an explicit destination to opt in without an interactive terminal. Supplying a Codex backup selects restore on either platform, but does not bypass its destructive-operation confirmation. Windows admin-scoped tasks fail before child execution when approval cannot be requested and the launchpad is not elevated.

Each invocation exclusively reserves its log directory before displaying the run plan: macOS uses a timestamp/PID plus a random suffix, and Windows uses a timestamp/PID plus a GUID. Concurrent runs cannot reuse a task-log directory. Allocation failure stops before task execution; canceling the final confirmation may leave an empty reserved directory.

Windows child output uses one append-mode UTF-8 writer per invocation instead of opening the log for every line. Lines are flushed immediately, rendering is initialized once, and the writer is disposed even on failure. The previous color environment is restored after each child.

Selected task commands are resolved once before the plan is displayed, including generated backup paths. The same executable and argument arrays are used for execution and logs; displayed commands use zsh escaping or PowerShell single-quoted literals with the call operator. Command text is never evaluated to execute a task.

In interactive terminals, these prompts prefill the default as editable text after the prompt. Press Enter to accept it, or edit it using Backspace/Delete and the arrow keys (Home/End move within the value). The Dock prompt prefills `skip`. Redirected input continues to accept a blank line for the default.

On macOS, editable prompts use the terminal directly even when launchpad pipes child-script output into its logs. Prompt editing is not captured in those logs; script results are still logged.

The macOS jenv version prompt accepts `s` or `skip` to keep the global version unchanged while continuing plugin setup and verification. Final shim refresh retries a busy rehash lock; persistent locks require explicit approval before `jenv rehash --force`. Only approve recovery when no other jenv rehash is running. Unresolved rehash errors fail the task instead of reporting success.

| Script Name                             | Description                                                                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/macos/setup_env.sh`            | Primary bootstrap script — installs and configures 30+ developer tools (JDK, Python, Rust, fonts, IDEs, shell utils) on macOS (Apple Silicon and Intel) |
| `scripts/macos/setup_env_min.sh`        | Minimal macOS bootstrap script for Git, JDK, Maven, VS Code, and IntelliJ IDEA                                                               |
| `scripts/macos/launchpad.sh`            | Interactive macOS launchpad that lets users choose setup profiles or tasks, resolves dependencies, runs scripts in order, and writes per-step logs |
| `scripts/macos/git_setup.sh`            | Configures global Git user credentials (name and email)                                                                                      |
| `scripts/macos/jenv_setup.sh`           | Discovers all installed JVMs and registers them with the `jenv` version manager                                                              |
| `scripts/macos/dock_setup.sh`           | Customizes the macOS Dock — sets icon size, removes defaults, and adds preferred apps from `config/dock_apps.txt`                            |
| `scripts/macos/gen_dock_apps.sh`        | Generates `config/dock_apps.txt` by reading the current Dock configuration                                                                    |
| `scripts/macos/default_apps_setup.sh`   | Sets macOS default apps for file types/URL schemes from `config/default_apps_macos.txt`, and can discover current UTI-to-extension handlers |
| `scripts/macos/vscode_setup.sh`         | Installs VS Code extensions from `config/vscode.txt` and applies managed VS Code settings from `config/vscode_settings.json`                  |
| `scripts/macos/zsh_plugins_setup.sh`    | Installs zsh plugins from `config/zsh_plugins.txt` using antidote, generates `~/.zsh_plugins.zsh`, and wires it into `~/.zshrc`               |
| `scripts/macos/intellij_setup.sh`       | Installs IntelliJ IDEA plugins from `config/intellij.txt` via IntelliJ CLI                                                                   |
| `scripts/macos/pycharm_setup.sh`        | Installs PyCharm plugins from `config/pycharm.txt` via PyCharm CLI                                                                            |
| `scripts/macos/conv-dot-to-png.sh`      | Converts `triples.dot` to a PNG image using Graphviz                                                                                          |
| `scripts/macos/colors.sh`               | Defines ANSI color code variables (sourced by other scripts)                                                                                 |
| `scripts/macos/backup_codex.sh`         | Backs up local `~/.codex` data to a specified target directory                                                                               |
| `scripts/macos/clone_github_repos.sh`   | Clones GitHub repositories listed in a file (`org/repo` format) into a destination directory                                                |
| `scripts/macos/pre_setup.sh`            | Prepares Homebrew setup for Apple Silicon and Intel (prefix detection, install, and shell profile wiring)                                   |
| `scripts/macos/restore_codex.sh`        | Restores a full `.codex` backup into `~/.codex` with a safety backup and rollback on failure                                                |
| `scripts/macos/run_tests.sh`            | Runs macOS script validation checks (syntax, optional ShellCheck, config presence, and minimal dry-run verification)                        |
| `scripts/macos/setup_env_min_rollback.sh` | Rolls back minimal macOS bootstrap installs and performs Homebrew cleanup                                                                   |
| `scripts/macos/test_setup_env_min.sh`   | Safe verification harness for minimal setup checks without installing any tools                                                              |
| `scripts/macos/verify_codex_restore.sh` | Read-only diagnostics to verify restored `.codex` data integrity and related app profile/cache signals                                      |
| `scripts/windows/setup_env.ps1`         | Primary bootstrap script — installs and configures tools using winget on Windows                                                            |
| `scripts/windows/setup_env_min.ps1`     | Minimal Windows bootstrap script for Git, JDK, Maven, VS Code, and IntelliJ IDEA                                                             |
| `scripts/windows/setup_env_min_rollback.ps1` | Rolls back minimal Windows bootstrap installs and user environment variables                                                            |
| `scripts/windows/launchpad.ps1`       | Interactive Windows launchpad that lets users choose setup profiles or tasks, resolves dependencies, runs scripts in order, and writes per-step logs |
| `scripts/windows/git_setup.ps1`         | Configures global Git identity, Git Credential Manager, and GitHub CLI account setup                                                         |
| `scripts/windows/jenv_setup.ps1`        | Discovers installed JDKs and registers them with JEnv-for-Windows                                                                            |
| `scripts/windows/maven_setup.ps1`       | Installs Apache Maven without relying on winget package availability                                                                         |
| `scripts/windows/vscode_setup.ps1`      | Installs VS Code extensions from `config/vscode.txt` and applies managed settings from `config/vscode_settings.json`                         |
| `scripts/windows/run_vscode_setup.ps1`  | Runs `vscode_setup.ps1` with `-Yes`                                                                                                          |
| `scripts/windows/intellij_setup.ps1`    | Installs IntelliJ IDEA plugins from `config/intellij.txt` via IntelliJ CLI                                                                    |
| `scripts/windows/pycharm_setup.ps1`     | Installs PyCharm plugins from `config/pycharm.txt` via PyCharm CLI                                                                             |
| `scripts/windows/clone_github_repos.ps1` | Clones GitHub repositories listed in a file (`org/repo` format) into a destination directory                                               |
| `scripts/windows/powershell_profile_setup.ps1` | Backs up and updates the user's PowerShell profile to source `config/Microsoft.PowerShell_profile.ps1`                              |
| `scripts/windows/run_taskbar_setup.ps1` | Pins/unpins Windows Taskbar apps from `config/taskbar_apps.txt`                                                                               |
| `scripts/windows/gen_taskbar_apps.ps1`  | Generates `config/taskbar_apps.txt` from current Windows Taskbar pinned shortcuts                                                             |
| `scripts/windows/backup_codex.ps1`      | Backs up local `.codex` data to a specified target directory                                                                                  |
| `scripts/windows/restore_codex.ps1`     | Restores a full `.codex` backup with a safety backup and rollback on failure                                                                 |
| `scripts/windows/verify_codex_restore.ps1` | Read-only diagnostics to verify restored `.codex` data integrity and related app profile/cache signals                                   |
| `scripts/windows/run_tests.ps1`         | Runs Windows script validation checks (syntax, config presence, and safe dry-run verification)                                               |


> Tip: For Windows PowerShell scripts, run them from an elevated PowerShell session and use `-Help` to see runtime options such as `-DryRun`, `-Interactive`, and `-Silent`.
