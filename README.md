# Developer Tools

> **One command to bootstrap a productive macOS environment for software and data engineers — from a fresh machine to fully equipped in minutes.**

Setting up a new machine is tedious. Hunting down the right tools, configuring shells, managing Java versions, wiring up your IDE — it takes hours and rarely produces consistent results. This project captures battle-tested scripts and configs so you can reproduce a complete, opinionated developer environment on Apple Silicon (M1/M2/M3/M4) in one run.

## Features

| Benefit | Detail |
|---|---|
| ⚡ **Fast bootstrap** | Install and configure 30+ tools with a single command |
| 🔁 **Reproducible** | Identical setup across every machine, every time |
| 🧰 **Curated toolset** | Hand-picked CLI utilities, JVM toolchain, Python/Rust, LLM tools, and modern IDEs |
| 🔧 **Shell-ready** | Pre-wired `.zshrc` with aliases, helpers, and prompt tweaks that survive reboots |
| 📊 **Data & ML friendly** | Includes `uv`, `mamba`, `conda`, Python, cloud CLIs, and `ollama` for local LLMs out of the box |

> "On a UNIX system, everything is a file; if something is not a file, it is a process." ― Machtelt Garrels,
> Introduction To Linux: A Hands-On Guide

---

## Setup Instructions

> ***Warning***
> 1. The script is tested on Apple M2/M3/M4 Pro (should also work on M1) and zsh shell.
> 2. Type `bash` and hit enter. If you see the error "Bash is required to interpret this script", change to `bash` shell
     as Homebrew install script uses bash.
> 3. If you haven't already installed Xcode Command Line Tools, you'll see a message that **The Xcode Command Line Tools
     will be installed.**

Check the output below to see if the Command Line Tools are installed:

```console
    ==> Searching online for the Command Line Tools
    ==> /usr/bin/sudo /usr/bin/touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    ==> Installing Command Line Tools for Xcode-15.3
    ==> /usr/bin/sudo /usr/sbin/softwareupdate -i Command\ Line\ Tools\ for\ Xcode-15.3
    Software Update Tool

    Finding available software

    Downloading Command Line Tools for Xcode
    Downloaded Command Line Tools for Xcode
    Installing Command Line Tools for Xcode

    Done with Command Line Tools for Xcode
```

### Steps

1. If your Mac is **managed (work or school)** then try to get an admin account and switch user. For e.g. if the admin
   account is `Koadmin` then `su Koadmin` and enter the password for that account with higher privileges
2. Install [Homebrew](https://brew.sh/) (**Pre-requisite**)
3. Clone this repo: `git clone https://github.com/yaravind/dev-tools.git` or download as zip (**Pre-requisite**)
4. cd <kbd>dev-tools</kbd>
5. Make `setup_env.sh` executable: <kbd>chmod +x setup_env.sh jenv_setup.sh git_setup.sh gen_dock_apps.sh
   dock_setup.sh</kbd>
6. Run: <kbd>./setup_env.sh</kbd>
7. Copy `.zshrc` (or `.bashrc` based on your shell) to home directory: <kbd>cp .zshrc ~/</kbd> and run <kbd>source ~
   /.zshrc</kbd>
8. Run <kbd>./jenv_setup.sh</kbd> to add JDK
9. Run <kbd>./git_setup.sh</kbd> to setup Git Credentials
10. Run <kbd>./dock_setup.sh</kbd> to setup macOS Dock

> ***Warning (on macOS)***
>
> Your terminal does not have App Management permissions, so Homebrew will delete and reinstall the app.
> This may result in some configurations (like notification settings or location in the Dock/Launchpad) being lost.
> To fix this, go to System Settings > Privacy & Security > App Management and add or enable your terminal.

---

## Scripts

| Script Name | Description |
|---|---|
| `setup_env.sh` | Primary bootstrap script — installs and configures 30+ developer tools (JDK, Python, Rust, fonts, IDEs, shell utils) on macOS Apple Silicon |
| `git_setup.sh` | Configures global Git user credentials (name and email) |
| `jenv_setup.sh` | Discovers all installed JVMs and registers them with the `jenv` version manager |
| `dock_setup.sh` | Customizes the macOS Dock — sets icon size, removes defaults, and adds preferred apps from `dock_apps.txt` |
| `gen_dock_apps.sh` | Generates `dock_apps.txt` by reading the current Dock configuration |
| `vscode_setup.sh` | Installs VS Code extensions listed in `vscode.txt` |
| `conv-dot-to-png.sh` | Converts `triples.dot` to a PNG image using Graphviz |
| `colors.sh` | Defines ANSI color code variables (sourced by other scripts) |

---

For Git aliases, package management tips, IntelliJ integration, and more, see [DETAILS.md](DETAILS.md).
