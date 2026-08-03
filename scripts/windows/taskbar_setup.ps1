# taskbar_setup.ps1 - Windows Taskbar pin/unpin based on config
#
# Usage (run as Administrator):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\windows\taskbar_setup.ps1
#   .\scripts\windows\taskbar_setup.ps1 -ConfigPath .\config\taskbar_apps.txt -Yes
#   .\scripts\windows\taskbar_setup.ps1 -DryRun

param(
    [string]$ConfigPath,
    [switch]$Yes,
    [switch]$DryRun
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$scriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    Split-Path -Parent $PSCommandPath
}

if (-not $scriptDir) {
    Write-EbkError "Could not resolve script directory."
    exit 1
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $scriptDir ".."
    $ConfigPath = Join-Path $ConfigPath ".."
    $ConfigPath = Join-Path $ConfigPath "config"
    $ConfigPath = Join-Path $ConfigPath "taskbar_apps.txt"
}

$resolvedConfig = Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue
if ($resolvedConfig) {
    $ConfigPath = $resolvedConfig.Path
} elseif (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-EbkError "Config file not found."
    exit 1
}

$taskbarBaseDir = if ($env:APPDATA) { $env:APPDATA } else { [IO.Path]::GetTempPath() }
$tempBaseDir = if ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() }
$TaskbarPinnedDir = Join-Path $taskbarBaseDir "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
$BackupDir = Join-Path $tempBaseDir ("taskbar_backup_{0}" -f (Get-Date -Format "yyyyMMddHHmmss"))

function Assert-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-EbkError "This script must be run as Administrator."
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
        Write-EbkError "Failed to backup Taskbar pins. $_"
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
        Write-EbkError "Failed to restore Taskbar pins. $_"
    }
}

function Normalize-Entry {
    param([string]$Line)
    $value = $Line.Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"')) {
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

function New-PinResult {
    param(
        [bool]$Success,
        [bool]$Failure,
        [string]$Message
    )

    return [pscustomobject]@{
        Success = $Success
        Failure = $Failure
        Message = $Message
    }
}

function Get-ShellFolderItem {
    param([string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved) {
        return $null
    }

    $folderPath = Split-Path -Parent $resolved.Path
    $leaf = Split-Path -Leaf $resolved.Path
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($folderPath)
    if (-not $folder) {
        return $null
    }

    return $folder.ParseName($leaf)
}

function Invoke-TaskbarPinVerb {
    param([string]$Path)

    $item = Get-ShellFolderItem -Path $Path
    if (-not $item) {
        return $false
    }

    try {
        $item.InvokeVerb("taskbarpin")
        return $true
    } catch {
        # Some Windows builds do not expose canonical verbs through InvokeVerb.
    }

    try {
        foreach ($verb in $item.Verbs()) {
            $verbName = ($verb.Name -replace "&", "").Trim()
            if ($verbName -match "(?i)pin.*taskbar") {
                $verb.DoIt()
                return $true
            }
        }
    } catch {
        Write-DebugLog "Could not enumerate Taskbar verbs for $Path. $_"
    }

    return $false
}

function Test-PinnedEntry {
    param(
        [string]$TargetPath,
        [string]$Arguments,
        [string]$Name
    )

    if (-not (Test-Path $TaskbarPinnedDir)) {
        return $false
    }

    $shortcuts = Get-ChildItem -Path $TaskbarPinnedDir -Filter "*.lnk" -ErrorAction SilentlyContinue
    foreach ($shortcutFile in $shortcuts) {
        $info = Get-ShortcutTarget -ShortcutPath $shortcutFile.FullName
        if (-not $info) { continue }

        if ($TargetPath -and $info.TargetPath -ieq $TargetPath) {
            return $true
        }
        if ($Arguments -and $info.Arguments -match [Regex]::Escape($Arguments)) {
            return $true
        }
        if ($Name -and $info.Name -ieq $Name) {
            return $true
        }
    }

    return $false
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

function Get-StartMenuRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    if ($env:ProgramData) {
        [void]$roots.Add((Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"))
    }
    if ($env:APPDATA) {
        [void]$roots.Add((Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"))
    }
    return $roots | Where-Object { Test-Path -LiteralPath $_ }
}

function Resolve-StartMenuShortcut {
    param([string]$Name)

    $needle = $Name.Trim()
    if (-not $needle.EndsWith(".lnk", [StringComparison]::OrdinalIgnoreCase)) {
        $needleWithExt = "$needle.lnk"
    } else {
        $needleWithExt = $needle
        $needle = [IO.Path]::GetFileNameWithoutExtension($needle)
    }

    $matches = New-Object System.Collections.Generic.List[object]
    $containsMatches = New-Object System.Collections.Generic.List[object]
    $hasWildcard = $needleWithExt.IndexOfAny([char[]]"*?") -ge 0
    foreach ($root in Get-StartMenuRoots) {
        Get-ChildItem -Path $root -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            if (
                $_.Name -ieq $needleWithExt -or
                $_.BaseName -ieq $needle -or
                ($hasWildcard -and ($_.Name -like $needleWithExt -or $_.BaseName -like $needle))
            ) {
                [void]$matches.Add($_)
            } elseif (-not $hasWildcard -and $_.BaseName -like "*$needle*") {
                [void]$containsMatches.Add($_)
            }
        }
    }

    if ($matches.Count -eq 0) {
        if ($containsMatches.Count -eq 0) {
            return $null
        }
        $matches = $containsMatches
    }

    return ($matches | Sort-Object FullName | Select-Object -First 1).FullName
}

function Get-AppInstallRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, $env:ProgramData)) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            [void]$roots.Add($root)
        }
    }
    return $roots
}

function Resolve-InstalledAppPath {
    param([string]$Name)

    $patterns = @()
    if ($Name -match "(?i)IntelliJ") {
        if ($Name -match "(?i)Community") {
            $patterns = @(
                "JetBrains\IntelliJ IDEA Community Edition*\bin\idea64.exe",
                "JetBrains\IntelliJ IDEA Community*\bin\idea64.exe"
            )
        } elseif ($Name -match "(?i)Ultimate") {
            $patterns = @(
                "JetBrains\IntelliJ IDEA Ultimate*\bin\idea64.exe",
                "JetBrains\IntelliJ IDEA\bin\idea64.exe",
                "JetBrains\IntelliJ IDEA*\bin\idea64.exe"
            )
        } else {
            $patterns = @("JetBrains\IntelliJ IDEA*\bin\idea64.exe")
        }
    } elseif ($Name -match "(?i)PyCharm") {
        if ($Name -match "(?i)Community") {
            $patterns = @(
                "JetBrains\PyCharm Community Edition*\bin\pycharm64.exe",
                "JetBrains\PyCharm Community*\bin\pycharm64.exe"
            )
        } elseif ($Name -match "(?i)Professional") {
            $patterns = @(
                "JetBrains\PyCharm Professional*\bin\pycharm64.exe",
                "JetBrains\PyCharm\bin\pycharm64.exe",
                "JetBrains\PyCharm*\bin\pycharm64.exe"
            )
        } else {
            $patterns = @("JetBrains\PyCharm*\bin\pycharm64.exe")
        }
    }

    if ($patterns.Count -eq 0) {
        return $null
    }

    $matches = New-Object System.Collections.Generic.List[object]
    foreach ($root in Get-AppInstallRoots) {
        foreach ($pattern in $patterns) {
            Get-ChildItem -Path (Join-Path $root $pattern) -ErrorAction SilentlyContinue | ForEach-Object {
                if ($Name -match "(?i)Ultimate|Professional" -and $_.FullName -match "(?i)Community") {
                    return
                }
                [void]$matches.Add($_)
            }
        }
    }

    if ($matches.Count -eq 0) {
        return $null
    }

    return ($matches | Sort-Object FullName | Select-Object -First 1).FullName
}

function Pin-StartMenuShortcutToTaskbar {
    param([string]$Name)

    $shortcutPath = Resolve-StartMenuShortcut -Name $Name
    if (-not $shortcutPath) {
        $installedPath = Resolve-InstalledAppPath -Name $Name
        if ($installedPath) {
            Write-Info "Start Menu shortcut not found: $Name"
            Write-Info "Resolved installed app path instead: $installedPath"
            return Pin-PathToTaskbar -AppPath $installedPath
        }

        return New-PinResult -Success $false -Failure $false -Message "Start Menu shortcut not found: $Name"
    }

    return Pin-PathToTaskbar -AppPath $shortcutPath
}

function Pin-PathToTaskbar {
    param([string]$AppPath)

    if (-not (Test-Path $AppPath)) {
        return New-PinResult -Success $false -Failure $false -Message "$AppPath does not exist, skipping."
    }

    if (-not (Test-Path $TaskbarPinnedDir)) {
        New-Item -ItemType Directory -Path $TaskbarPinnedDir -Force | Out-Null
    }

    $tempDir = Join-Path $env:TEMP "taskbar_pins"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $pinSource = $AppPath
    $targetPath = $AppPath
    $arguments = ""
    $name = [IO.Path]::GetFileNameWithoutExtension($AppPath)

    if ($AppPath.ToLower().EndsWith(".lnk")) {
        $info = Get-ShortcutTarget -ShortcutPath $AppPath
        if ($info) {
            $targetPath = $info.TargetPath
            $arguments = $info.Arguments
            $name = $info.Name
        }
    } else {
        $shortcutPath = Join-Path $tempDir ("{0}.lnk" -f $name)
        Create-Shortcut -TargetPath $AppPath -Arguments "" -ShortcutPath $shortcutPath -WorkingDirectory (Split-Path $AppPath -Parent) -IconLocation $AppPath
        $pinSource = $shortcutPath
    }

    if (Test-PinnedEntry -TargetPath $targetPath -Arguments $arguments -Name $name) {
        return New-PinResult -Success $true -Failure $false -Message "Already pinned: $name"
    }

    if (-not (Invoke-TaskbarPinVerb -Path $pinSource)) {
        return New-PinResult -Success $false -Failure $true -Message "Windows did not expose a Taskbar pin verb for $AppPath. This Windows build may block programmatic Taskbar pinning."
    }

    Start-Sleep -Milliseconds 750
    if (Test-PinnedEntry -TargetPath $targetPath -Arguments $arguments -Name $name) {
        return New-PinResult -Success $true -Failure $false -Message "Pinned: $name"
    }

    return New-PinResult -Success $false -Failure $true -Message "Taskbar pin command ran, but Windows did not report a pinned shortcut for $AppPath."
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

    if (Test-PinnedEntry -TargetPath "explorer.exe" -Arguments $args -Name "") {
        return New-PinResult -Success $true -Failure $false -Message "Already pinned: $Aumid"
    }

    if (-not (Invoke-TaskbarPinVerb -Path $shortcutPath)) {
        return New-PinResult -Success $false -Failure $true -Message "Windows did not expose a Taskbar pin verb for AUMID:$Aumid."
    }

    Start-Sleep -Milliseconds 750
    if (Test-PinnedEntry -TargetPath "explorer.exe" -Arguments $args -Name "") {
        return New-PinResult -Success $true -Failure $false -Message "Pinned: $Aumid"
    }

    return New-PinResult -Success $false -Failure $true -Message "Taskbar pin command ran, but Windows did not report a pinned shortcut for AUMID:$Aumid."
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
Write-Step "Starting Taskbar setup (Windows)"
Write-Info "Reading config: $ConfigPath"

$parsed = Parse-Config -Path $ConfigPath
$entriesToAdd = @($parsed["Add"])
$entriesToRemove = @($parsed["Remove"])

Write-Info "Items to add: $($entriesToAdd.Count)"
Write-Info "Items to remove: $($entriesToRemove.Count)"

if ($DryRun) {
    Write-Warn "DryRun enabled. No changes will be made."
    Write-Step "DryRun preview"
    foreach ($entry in $entriesToRemove) {
        Write-Info "Would remove: $entry"
    }
    foreach ($entry in $entriesToAdd) {
        Write-Info "Would add: $entry"
        if ($entry.StartsWith("STARTMENU:", [StringComparison]::OrdinalIgnoreCase)) {
            $shortcutName = $entry.Substring(10)
            $shortcutPath = Resolve-StartMenuShortcut -Name $shortcutName
            if ($shortcutPath) {
                Write-Info "Resolved Start Menu shortcut: $shortcutPath"
            } else {
                $installedPath = Resolve-InstalledAppPath -Name $shortcutName
                if ($installedPath) {
                    Write-Info "Start Menu shortcut not found in dry-run: $shortcutName"
                    Write-Info "Resolved installed app path instead: $installedPath"
                } else {
                    Write-Warn "Start Menu shortcut not found in dry-run: $shortcutName"
                }
            }
        }
    }
    exit 0
}

Assert-Admin

Backup-TaskbarPins

$added = 0
$skipped = 0
$removed = 0
$failed = 0

try {
    foreach ($entry in $entriesToRemove) {
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

        if ($entry.StartsWith("STARTMENU:", [StringComparison]::OrdinalIgnoreCase)) {
            $shortcutName = $entry.Substring(10)
            $shortcutPath = Resolve-StartMenuShortcut -Name $shortcutName
            if ($shortcutPath) {
                $removed += Remove-PinnedEntry -TargetPath $shortcutPath -Arguments "" -Name ([IO.Path]::GetFileNameWithoutExtension($shortcutPath))
            } else {
                $removed += Remove-PinnedEntry -TargetPath "" -Arguments "" -Name $shortcutName
            }
            continue
        }

        $path = $entry
        $name = [IO.Path]::GetFileNameWithoutExtension($path)
        $removed += Remove-PinnedEntry -TargetPath $path -Arguments "" -Name $name
    }

    foreach ($entry in $entriesToAdd) {
        if ($entry -match "^(?i)SPACER$") {
            Write-Warn "SPACER is not supported on Windows Taskbar. Skipping."
            $skipped++
            continue
        }

        if ($entry.StartsWith("AUMID:", [StringComparison]::OrdinalIgnoreCase)) {
            $aumid = $entry.Substring(6)
            $result = Pin-AumidToTaskbar -Aumid $aumid
            if ($result.Success) {
                Write-Ok $result.Message
                $added++
            } elseif ($result.Failure) {
                Write-EbkError $result.Message
                $failed++
            } else {
                Write-Warn $result.Message
                $skipped++
            }
            continue
        }

        if ($entry.StartsWith("STARTMENU:", [StringComparison]::OrdinalIgnoreCase)) {
            $shortcutName = $entry.Substring(10)
            $result = Pin-StartMenuShortcutToTaskbar -Name $shortcutName
            if ($result.Success) {
                Write-Ok $result.Message
                $added++
            } elseif ($result.Failure) {
                Write-EbkError $result.Message
                $failed++
            } else {
                Write-Warn $result.Message
                $skipped++
            }
            continue
        }

        $result = Pin-PathToTaskbar -AppPath $entry
        if ($result.Success) {
            Write-Ok $result.Message
            $added++
        } elseif ($result.Failure) {
            Write-EbkError $result.Message
            $failed++
        } else {
            Write-Warn $result.Message
            $skipped++
        }
    }
} catch {
    Write-EbkError "Taskbar update failed. $_"
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-EbkError $_.InvocationInfo.PositionMessage
    }
    if ($_.ScriptStackTrace) {
        Write-EbkError "Stack trace: $($_.ScriptStackTrace)"
    }
    Restore-TaskbarPins
    exit 1
}

Restart-Explorer

Write-Ok "Added: $added"
Write-Ok "Removed: $removed"
Write-Warn "Skipped: $skipped"
if ($failed -gt 0) {
    Write-EbkError "Failed: $failed"
    Write-EbkError "Taskbar setup could not pin every requested app. See the errors above for the Windows reason/fix."
    exit 1
}

if ($entriesToAdd.Count -gt 0 -and $added -eq 0) {
    Write-EbkError "Failed: 0"
    Write-EbkError "No requested Taskbar entries were pinned. Verify the apps are installed and the config names match Start Menu shortcuts or known install paths."
    exit 1
}

Write-Ok "Failed: $failed"
Write-Ok "Taskbar setup complete."
