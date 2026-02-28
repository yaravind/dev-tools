# taskbar_setup.ps1 - Windows Taskbar pin/unpin based on config
#
# Usage (run as Administrator):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\taskbar_setup.ps1
#   .\scripts\taskbar_setup.ps1 -ConfigPath .\config\taskbar_apps.txt -Yes

param(
    [string]$ConfigPath,
    [switch]$Yes
)

$scriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    Split-Path -Parent $PSCommandPath
}

if (-not $scriptDir) {
    Write-Host "ERROR: Could not resolve script directory." -ForegroundColor Red
    exit 1
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $scriptDir "..\config\taskbar_apps.txt"
}

$ConfigPath = (Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue)
if (-not $ConfigPath) {
    Write-Host "ERROR: Config file not found." -ForegroundColor Red
    exit 1
}
$ConfigPath = $ConfigPath.Path

$TaskbarPinnedDir = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
$BackupDir = Join-Path $env:TEMP ("taskbar_backup_{0}" -f (Get-Date -Format "yyyyMMddHHmmss"))

function Write-Step {
    param([string]$Message)
    Write-Host "===> $Message" -ForegroundColor Magenta
}

function Write-Info {
    param([string]$Message)
    Write-Host "===> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "===> $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "===> $Message" -ForegroundColor Yellow
}

function Assert-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
        exit 1
    }
}

function Backup-TaskbarPins {
    Write-Info "Backing up Taskbar pins to $BackupDir"
    try {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        if (Test-Path $TaskbarPinnedDir) {
            Copy-Item -Path (Join-Path $TaskbarPinnedDir "*") -Destination $BackupDir -Recurse -Force -ErrorAction Stop
        }
    } catch {
        Write-Host "ERROR: Failed to backup Taskbar pins. $_" -ForegroundColor Red
        exit 1
    }
}

function Restore-TaskbarPins {
    Write-Warn "Rolling back Taskbar pins from $BackupDir"
    try {
        if (-not (Test-Path $BackupDir)) {
            Write-Warn "No backup found. Manual recovery may be required."
            return
        }
        if (-not (Test-Path $TaskbarPinnedDir)) {
            New-Item -ItemType Directory -Path $TaskbarPinnedDir -Force | Out-Null
        }
        Get-ChildItem -Path $TaskbarPinnedDir -Filter "*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $BackupDir "*") -Destination $TaskbarPinnedDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Host "ERROR: Failed to restore Taskbar pins. $_" -ForegroundColor Red
    }
}

function Normalize-Entry {
    param([string]$Line)
    $value = $Line.Trim()
    if ($value.StartsWith("\"") -and $value.EndsWith("\"")) {
        $value = $value.Trim('"')
    }
    return [Environment]::ExpandEnvironmentVariables($value)
}

function Is-CommentOrEmpty {
    param([string]$Line)
    if (-not $Line) { return $true }
    $trimmed = $Line.Trim()
    if (-not $trimmed) { return $true }
    return $trimmed.StartsWith("//") -or $trimmed.StartsWith("#")
}

function Create-Shortcut {
    param(
        [string]$TargetPath,
        [string]$Arguments,
        [string]$ShortcutPath,
        [string]$WorkingDirectory,
        [string]$IconLocation
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    if ($Arguments) { $shortcut.Arguments = $Arguments }
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    if ($IconLocation) { $shortcut.IconLocation = $IconLocation }
    $shortcut.Save()
}

function Get-ShortcutTarget {
    param([string]$ShortcutPath)
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        return @{ TargetPath = $shortcut.TargetPath; Arguments = $shortcut.Arguments; Name = (Split-Path $ShortcutPath -LeafBase) }
    } catch {
        return $null
    }
}

function Remove-PinnedEntry {
    param(
        [string]$TargetPath,
        [string]$Arguments,
        [string]$Name
    )

    if (-not (Test-Path $TaskbarPinnedDir)) {
        return 0
    }

    $removed = 0
    $shortcuts = Get-ChildItem -Path $TaskbarPinnedDir -Filter "*.lnk" -ErrorAction SilentlyContinue
    foreach ($shortcutFile in $shortcuts) {
        $info = Get-ShortcutTarget -ShortcutPath $shortcutFile.FullName
        if (-not $info) { continue }

        $match = $false
        if ($TargetPath -and $info.TargetPath -ieq $TargetPath) { $match = $true }
        if (-not $match -and $Arguments -and $info.Arguments -match [Regex]::Escape($Arguments)) { $match = $true }
        if (-not $match -and $Name -and $info.Name -ieq $Name) { $match = $true }

        if ($match) {
            Remove-Item -Path $shortcutFile.FullName -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }

    return $removed
}

function Pin-PathToTaskbar {
    param([string]$AppPath)

    if (-not (Test-Path $AppPath)) {
        Write-Warn "WARN: $AppPath does not exist, skipping."
        return $false
    }

    if (-not (Test-Path $TaskbarPinnedDir)) {
        New-Item -ItemType Directory -Path $TaskbarPinnedDir -Force | Out-Null
    }

    $tempDir = Join-Path $env:TEMP "taskbar_pins"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    if ($AppPath.ToLower().EndsWith(".lnk")) {
        $dest = Join-Path $TaskbarPinnedDir (Split-Path $AppPath -Leaf)
        Copy-Item -Path $AppPath -Destination $dest -Force
        return $true
    }

    $name = [IO.Path]::GetFileNameWithoutExtension($AppPath)
    $shortcutPath = Join-Path $tempDir ("{0}.lnk" -f $name)
    Create-Shortcut -TargetPath $AppPath -Arguments "" -ShortcutPath $shortcutPath -WorkingDirectory (Split-Path $AppPath -Parent) -IconLocation $AppPath

    $destShortcut = Join-Path $TaskbarPinnedDir (Split-Path $shortcutPath -Leaf)
    Copy-Item -Path $shortcutPath -Destination $destShortcut -Force
    return $true
}

function Pin-AumidToTaskbar {
    param([string]$Aumid)

    if (-not (Test-Path $TaskbarPinnedDir)) {
        New-Item -ItemType Directory -Path $TaskbarPinnedDir -Force | Out-Null
    }

    $tempDir = Join-Path $env:TEMP "taskbar_pins"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $shortcutPath = Join-Path $tempDir ("{0}.lnk" -f ($Aumid -replace "[^A-Za-z0-9._-]", "_"))
    $args = "shell:AppsFolder\$Aumid"
    Create-Shortcut -TargetPath "explorer.exe" -Arguments $args -ShortcutPath $shortcutPath -WorkingDirectory "" -IconLocation ""

    $destShortcut = Join-Path $TaskbarPinnedDir (Split-Path $shortcutPath -Leaf)
    Copy-Item -Path $shortcutPath -Destination $destShortcut -Force
    return $true
}

function Restart-Explorer {
    Write-Info "Restarting Explorer to apply Taskbar changes..."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

function Parse-Config {
    param([string]$Path)

    $add = @()
    $remove = @()

    foreach ($line in Get-Content -Path $Path -ErrorAction Stop) {
        if (Is-CommentOrEmpty -Line $line) { continue }

        if ($line.Trim().StartsWith("--")) {
            $entry = Normalize-Entry -Line ($line.Trim().Substring(2).Trim())
            if ($entry) { $remove += $entry }
            continue
        }

        $entry = Normalize-Entry -Line $line
        if ($entry) { $add += $entry }
    }

    return @{ Add = $add; Remove = $remove }
}

# ==========================
# Main
# ==========================
Assert-Admin

Write-Step "Starting Taskbar setup (Windows)"
Write-Info "Reading config: $ConfigPath"

$parsed = Parse-Config -Path $ConfigPath

Write-Info "Items to add: $($parsed.Add.Count)"
Write-Info "Items to remove: $($parsed.Remove.Count)"

if (-not $Yes) {
    $proceed = Read-Host "Proceed? (y/n)"
    if ($proceed -notmatch "^[yY]$") {
        Write-Warn "Aborted by user. No changes made."
        exit 0
    }
}

Backup-TaskbarPins

$added = 0
$skipped = 0
$removed = 0

try {
    foreach ($entry in $parsed.Remove) {
        if ($entry -match "^(?i)SPACER$") {
            Write-Warn "SPACER is not supported on Windows Taskbar. Skipping remove entry."
            $skipped++
            continue
        }

        if ($entry.StartsWith("AUMID:", [StringComparison]::OrdinalIgnoreCase)) {
            $aumid = $entry.Substring(6)
            $removed += Remove-PinnedEntry -TargetPath "" -Arguments "shell:AppsFolder\$aumid" -Name ""
            continue
        }

        $path = $entry
        $name = [IO.Path]::GetFileNameWithoutExtension($path)
        $removed += Remove-PinnedEntry -TargetPath $path -Arguments "" -Name $name
    }

    foreach ($entry in $parsed.Add) {
        if ($entry -match "^(?i)SPACER$") {
            Write-Warn "SPACER is not supported on Windows Taskbar. Skipping."
            $skipped++
            continue
        }

        if ($entry.StartsWith("AUMID:", [StringComparison]::OrdinalIgnoreCase)) {
            $aumid = $entry.Substring(6)
            if (Pin-AumidToTaskbar -Aumid $aumid) { $added++ } else { $skipped++ }
            continue
        }

        if (Pin-PathToTaskbar -AppPath $entry) { $added++ } else { $skipped++ }
    }
} catch {
    Write-Host "ERROR: Taskbar update failed. $_" -ForegroundColor Red
    Restore-TaskbarPins
    exit 1
}

Restart-Explorer

Write-Ok "Added: $added"
Write-Ok "Removed: $removed"
Write-Warn "Skipped: $skipped"
Write-Ok "Taskbar setup complete."

