# Requires -Version 5.1

function Write-Step($msg) {
    Write-Host "===> $msg" -ForegroundColor Magenta
}
function Write-Info($msg) {
    Write-Host "===> $msg" -ForegroundColor Cyan
}
function Write-Ok($msg) {
    Write-Host "===> $msg" -ForegroundColor Green
}
function Write-Warn($msg) {
    Write-Host "===> $msg" -ForegroundColor Yellow
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path $scriptDir '../../config/taskbar_apps.txt'

Write-Step "Enumerating current Taskbar pinned apps..."

# Get all pinned taskbar items (using Win32 API via Shell.Application)
$shell = New-Object -ComObject Shell.Application
$taskbarFolder = $shell.Namespace(0x1F3F) # Taskbar pinned folder
$pinnedItems = @()
if ($taskbarFolder) {
    foreach ($item in $taskbarFolder.Items()) {
        $pinnedItems += $item.Path
    }
} else {
    Write-Info "Could not access Taskbar pinned folder via Shell.Application. Falling back to TaskBar shortcuts directory."
    # Read pinned items directly from the TaskBar shortcuts directory
    $taskbarDir = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    if (Test-Path $taskbarDir) {
        $wshShell = New-Object -ComObject WScript.Shell
        foreach ($shortcut in (Get-ChildItem -Path $taskbarDir -Filter "*.lnk" -ErrorAction SilentlyContinue)) {
            try {
                $lnk = $wshShell.CreateShortcut($shortcut.FullName)
                if ($lnk.TargetPath) {
                    $pinnedItems += $lnk.TargetPath
                } else {
                    $pinnedItems += $shortcut.BaseName
                }
            } catch {
                $pinnedItems += $shortcut.BaseName
            }
        }
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wshShell) | Out-Null
    } else {
        Write-Warn "Could not find TaskBar shortcuts directory: $taskbarDir"
    }
}

Write-Step "Writing pinned apps to $configPath ..."

@(
    '# Taskbar apps list (Windows)',
    '# - One entry per line',
    '# - Lines starting with "--" remove pinned items',
    '# - Blank lines and comments are ignored',
    '# - "SPACER" is not supported on Windows Taskbar (will be skipped)',
    '# - Use AUMID entries for Microsoft Store apps: AUMID:Microsoft.WindowsTerminal_8wekyb3d8bbwe!App',
    ''
) | Set-Content -Path $configPath

foreach ($app in $pinnedItems) {
    if ($app) {
        Add-Content -Path $configPath -Value $app
    }
}

Write-Ok "Done. Pinned Taskbar apps exported to $configPath"

