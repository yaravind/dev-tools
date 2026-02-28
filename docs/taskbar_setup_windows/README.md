# Windows Taskbar Setup

This folder contains a minimal Windows Taskbar setup script that pins and unpins apps based on a config file.

## Files

- `scripts/taskbar_setup.ps1`: main Taskbar setup script
- `scripts/run_taskbar_setup.ps1`: tiny runner that bypasses the execution policy and runs the setup
- `config/taskbar_apps.txt`: list of apps to pin/unpin

## Usage

Open PowerShell as Administrator, then run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\taskbar_setup.ps1
```

Or use the runner:

```powershell
.\scripts\run_taskbar_setup.ps1
```

## Config format (`config/taskbar_apps.txt`)

- One entry per line.
- Lines starting with `--` are removed (unpinned).
- Blank lines and lines starting with `#` or `//` are ignored.
- `SPACER` is skipped (Windows Taskbar does not support spacers).
- Use `AUMID:<id>` for Microsoft Store apps.

Example:

```text
%LocalAppData%\Programs\Microsoft VS Code\Code.exe
AUMID:Microsoft.WindowsTerminal_8wekyb3d8bbwe!App
--%ProgramFiles%\Microsoft\Edge\Application\msedge.exe
```

## Notes

- The script backs up existing Taskbar pins before applying changes.
- Explorer is restarted at the end to apply updates.
- Pinning behavior can vary between Windows versions; adjust paths as needed.

