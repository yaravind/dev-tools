# Windows VS Code Extension Setup

This script installs VS Code extensions listed in `config/vscode.txt`.

## Files

- `scripts/vscode_setup.ps1`: main setup script
- `scripts/run_vscode_setup.ps1`: tiny runner that bypasses the execution policy and runs the setup
- `config/vscode.txt`: extension IDs (one per line)

## Usage

Run PowerShell as Administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\vscode_setup.ps1
```

Or use the runner:

```powershell
.\scripts\run_vscode_setup.ps1
```

## Dry run

```powershell
.\scripts\vscode_setup.ps1 -DryRun
```

`-WhatIf` is accepted as an alias for `-DryRun`.

## Notes

- Blank lines and comment lines (`#` or `//`) are ignored.
- The script skips extensions that are already installed.
- Ensure the `code` CLI is available on PATH (VS Code: Command Palette → “Shell Command: Install 'code' command in PATH”).
