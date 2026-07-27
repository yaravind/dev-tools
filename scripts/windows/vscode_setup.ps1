# vscode_setup.ps1 - Install VS Code extensions and managed settings on Windows
#
# Usage (run as Administrator if your VS Code install requires it):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\windows\vscode_setup.ps1
#   .\scripts\windows\vscode_setup.ps1 -Yes
#   .\scripts\windows\vscode_setup.ps1 -DryRun
#   .\scripts\windows\vscode_setup.ps1 -WhatIf

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$SettingsConfigPath,
    [string]$UserSettingsPath,
    [switch]$Yes,
    [Alias("WhatIf")]
    [switch]$DryRun
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$script:ScriptStart = Get-Date
$script:InstallCount = 0
$script:SkipCount = 0
$script:FailCount = 0
$script:DuplicateCount = 0
$script:InvalidCount = 0
$script:SettingsFailCount = 0
$script:RequestedCount = 0
$script:NetNewExtensions = New-Object System.Collections.Generic.List[string]

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Resolve-ScriptDir {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }
    if ($MyInvocation.MyCommand.Path) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }
    return (Split-Path -Parent $PSCommandPath)
}

function Resolve-RepoRoot {
    param([string]$ScriptDir)

    $resolved = Resolve-Path (Join-Path $ScriptDir "..\..") -ErrorAction SilentlyContinue
    if ($resolved) {
        return $resolved.Path
    }
    return (Split-Path -Parent (Split-Path -Parent $ScriptDir))
}

function Resolve-DefaultUserSettingsPath {
    if ($UserSettingsPath) {
        return $UserSettingsPath
    }
    if ($env:APPDATA) {
        return (Join-Path $env:APPDATA "Code\User\settings.json")
    }
    return (Join-Path $HOME "AppData\Roaming\Code\User\settings.json")
}

function Is-CommentOrEmpty {
    param([string]$Line)
    if (-not $Line) { return $true }
    $trimmed = $Line.Trim()
    if (-not $trimmed) { return $true }
    return $trimmed.StartsWith("#") -or $trimmed.StartsWith("//")
}

function Get-ConfigExtensions {
    param([string]$Path)

    $extensions = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

    foreach ($line in Get-Content -Path $Path -ErrorAction Stop) {
        if (Is-CommentOrEmpty -Line $line) { continue }

        $ext = $line.Trim()
        if (-not $ext) { continue }

        if ($ext -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.[A-Za-z0-9][A-Za-z0-9_.-]*(@[A-Za-z0-9_.-]+)?$') {
            Write-Warn "Ignoring invalid extension ID `"$ext`"."
            $script:InvalidCount++
            continue
        }

        $normalized = $ext.ToLowerInvariant()
        if ($seen.Contains($normalized)) {
            Write-Warn "Duplicate extension `"$normalized`" in config. Ignoring duplicate entry."
            $script:DuplicateCount++
            continue
        }

        [void]$seen.Add($normalized)
        [void]$extensions.Add($normalized)
    }

    return $extensions
}

function Get-InstalledExtensions {
    param([switch]$SkipCodeCheck)

    if (-not (Test-CommandExists "code")) {
        if ($SkipCodeCheck) {
            Write-Warn "VS Code CLI not found. Continuing due to -DryRun."
            return @()
        }

        Write-EbkError "VS Code CLI 'code' not found. Install VS Code and enable the 'code' command."
        exit 1
    }

    return @(code --list-extensions)
}

function Remove-JsoncSyntax {
    param([string]$Content)

    $result = New-Object System.Text.StringBuilder
    $inString = $false
    $inLineComment = $false
    $inBlockComment = $false
    $escaped = $false
    $i = 0

    while ($i -lt $Content.Length) {
        $ch = $Content[$i]
        $next = if (($i + 1) -lt $Content.Length) { $Content[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($ch -eq "`r" -or $ch -eq "`n") {
                $inLineComment = $false
                [void]$result.Append($ch)
            }
            $i++
            continue
        }

        if ($inBlockComment) {
            if ($ch -eq "*" -and $next -eq "/") {
                $inBlockComment = $false
                $i += 2
            } else {
                $i++
            }
            continue
        }

        if ($inString) {
            [void]$result.Append($ch)
            if ($escaped) {
                $escaped = $false
            } elseif ($ch -eq "\") {
                $escaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            $i++
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            [void]$result.Append($ch)
            $i++
            continue
        }

        if ($ch -eq "/" -and $next -eq "/") {
            $inLineComment = $true
            $i += 2
            continue
        }

        if ($ch -eq "/" -and $next -eq "*") {
            $inBlockComment = $true
            $i += 2
            continue
        }

        [void]$result.Append($ch)
        $i++
    }

    $withoutComments = $result.ToString()
    return [regex]::Replace($withoutComments, ',\s*([}\]])', '$1')
}

function Read-JsonObject {
    param([string]$Path)

    $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [ordered]@{}
    }

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $sanitized = Remove-JsoncSyntax -Content $raw
        $parsed = $sanitized | ConvertFrom-Json -ErrorAction Stop
    }

    if ($null -eq $parsed) {
        return [ordered]@{}
    }

    if ($parsed -isnot [pscustomobject]) {
        throw "$Path must contain a JSON object."
    }

    return $parsed
}

function ConvertTo-OrderedHashtable {
    param([pscustomobject]$Object)

    $table = [ordered]@{}
    foreach ($property in $Object.PSObject.Properties) {
        $table[$property.Name] = $property.Value
    }
    return $table
}

function Apply-ManagedSettings {
    param(
        [string]$ManagedSettingsPath,
        [string]$TargetSettingsPath
    )

    if (-not (Test-Path -LiteralPath $ManagedSettingsPath)) {
        Write-EbkError "Settings config not found: $ManagedSettingsPath"
        return $false
    }

    if ($DryRun) {
        Write-Info "DryRun: would merge managed settings into $TargetSettingsPath"
        return $true
    }

    $targetDir = Split-Path -Parent $TargetSettingsPath
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction Stop | Out-Null
    }

    if (-not (Test-Path -LiteralPath $TargetSettingsPath)) {
        "{}" | Set-Content -Path $TargetSettingsPath -Encoding UTF8 -ErrorAction Stop
    }

    $managed = Read-JsonObject -Path $ManagedSettingsPath
    $existing = Read-JsonObject -Path $TargetSettingsPath
    $merged = ConvertTo-OrderedHashtable -Object $existing

    foreach ($property in $managed.PSObject.Properties | Sort-Object Name) {
        Write-Info ("Managed setting: {0} = {1}" -f $property.Name, ($property.Value | ConvertTo-Json -Compress -Depth 100))
        $merged[$property.Name] = $property.Value
    }

    $merged | ConvertTo-Json -Depth 100 | Set-Content -Path $TargetSettingsPath -Encoding UTF8 -ErrorAction Stop
    return $true
}

function Format-Duration {
    param([TimeSpan]$Duration)

    if ($Duration.TotalHours -ge 1) {
        return ("{0}h {1}m {2}s" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds)
    }
    if ($Duration.TotalMinutes -ge 1) {
        return ("{0}m {1}s" -f [int]$Duration.TotalMinutes, $Duration.Seconds)
    }
    return ("{0}s" -f [int]$Duration.TotalSeconds)
}

function Print-StructuredReport {
    param([string]$StatusLabel)

    Write-Host ""
    Write-Host "Final Status Report" -ForegroundColor $script:EbPhase
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
    Write-Host ("  {0,-24} {1}" -f "Script", "VS Code Setup (Windows)")
    Write-Host ("  {0,-24} {1}" -f "Config", $ConfigPath)
    Write-Host ("  {0,-24} {1}" -f "Settings file", $SettingsConfigPath)
    Write-Host ("  {0,-24} {1}" -f "User settings", $UserSettingsPath)
    Write-Host ("  {0,-24} {1}" -f "Status", $StatusLabel)
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
    Write-Host ("  {0,-24} {1}" -f "Requested", $script:RequestedCount)
    Write-Host ("  {0,-24} {1}" -f "Attempted", $script:RequestedCount)
    Write-Host ("  {0,-24} {1}" -f "Installed (net new)", $script:InstallCount)
    Write-Host ("  {0,-24} {1}" -f "Already installed", $script:SkipCount)
    Write-Host ("  {0,-24} {1}" -f "Duplicates ignored", $script:DuplicateCount)
    Write-Host ("  {0,-24} {1}" -f "Invalid entries ignored", $script:InvalidCount)
    Write-Host ("  {0,-24} {1}" -f "Failed installs", $script:FailCount)
    Write-Host ("  {0,-24} {1}" -f "Settings merge failures", $script:SettingsFailCount)
    Write-Host ("  {0,-24} {1}" -f "Duration", (Format-Duration -Duration ((Get-Date) - $script:ScriptStart)))
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase

    Write-Host "Net New Extensions Installed" -ForegroundColor $script:EbPhase
    if ($script:NetNewExtensions.Count -eq 0) {
        Write-Host "  No net-new extensions were installed in this run."
    } else {
        foreach ($ext in $script:NetNewExtensions) {
            Write-Ok $ext
        }
    }

    Write-Host ""
    Write-Host "Next Steps" -ForegroundColor $script:EbPhase
    if ($script:FailCount -gt 0 -or $script:SettingsFailCount -gt 0 -or $script:InvalidCount -gt 0) {
        Write-Host "  Review failed installs/setting merges and fix invalid IDs in config/vscode.txt."
    } else {
        Write-Host "  No follow-up action required."
    }
}

$scriptDir = Resolve-ScriptDir
if (-not $scriptDir) {
    Write-EbkError "Could not resolve script directory."
    exit 1
}

$repoRoot = Resolve-RepoRoot -ScriptDir $scriptDir
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $repoRoot "config\vscode.txt"
}
if (-not $SettingsConfigPath) {
    $SettingsConfigPath = Join-Path $repoRoot "config\vscode_settings.json"
}
$UserSettingsPath = Resolve-DefaultUserSettingsPath

$resolvedConfig = Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue
if ($resolvedConfig) {
    $ConfigPath = $resolvedConfig.Path
} elseif (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-EbkError "Config file not found: $ConfigPath"
    exit 1
}

$resolvedSettingsConfig = Resolve-Path -Path $SettingsConfigPath -ErrorAction SilentlyContinue
if ($resolvedSettingsConfig) {
    $SettingsConfigPath = $resolvedSettingsConfig.Path
} elseif (-not (Test-Path -LiteralPath $SettingsConfigPath)) {
    Write-EbkError "Settings config file not found: $SettingsConfigPath"
    exit 1
}

Write-Step "DISCOVER Scanning local VS Code state and extension config"
Write-Info "Config file: $ConfigPath"
Write-Info "Settings file: $SettingsConfigPath"
Write-Info "User settings: $UserSettingsPath"

$installedList = Get-InstalledExtensions -SkipCodeCheck:$DryRun
$installedSet = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
foreach ($ext in $installedList) {
    if ($ext) { [void]$installedSet.Add($ext) }
}
Write-Info ("Installed VS Code extensions detected: {0}" -f $installedSet.Count)

$desired = Get-ConfigExtensions -Path $ConfigPath
$script:RequestedCount = $desired.Count
Write-Info ("Total extension IDs queued: {0}" -f $script:RequestedCount)

if (-not $Yes) {
    $proceed = Read-Host "Proceed with installation and settings merge? (y/n)"
    if ($proceed -notmatch "^[yY]$") {
        Write-Warn "Aborted by user. No changes made."
        exit 0
    }
}

Write-Step "INSTALL Installing queued VS Code extensions"
foreach ($ext in $desired) {
    if ($installedSet.Contains($ext)) {
        $script:SkipCount++
        continue
    }

    if ($DryRun) {
        Write-Info "DryRun: would install extension: $ext"
        $script:SkipCount++
        continue
    }

    Write-Info "Installing extension: $ext"
    code --install-extension $ext
    if ($LASTEXITCODE -eq 0) {
        if (Get-InstalledExtensions | Where-Object { $_ -ieq $ext }) {
            Write-Ok "Installed `"$ext`"."
            $script:InstallCount++
            [void]$installedSet.Add($ext)
            [void]$script:NetNewExtensions.Add($ext)
        } else {
            Write-EbkError "Command completed but `"$ext`" was not found in the installed extension list."
            $script:FailCount++
        }
    } else {
        Write-EbkError "Failed to install `"$ext`"."
        $script:FailCount++
    }
}

Write-Step "VERIFY Applying managed VS Code settings"
try {
    if (Apply-ManagedSettings -ManagedSettingsPath $SettingsConfigPath -TargetSettingsPath $UserSettingsPath) {
        if ($DryRun) {
            Write-Ok "DryRun OK: managed settings previewed."
        } else {
            Write-Ok "Managed VS Code settings applied to `"$UserSettingsPath`"."
        }
    } else {
        $script:SettingsFailCount++
    }
} catch {
    Write-EbkError "Failed to merge VS Code settings. Ensure both settings files contain valid JSON objects. $_"
    $script:SettingsFailCount++
}

$overallStatus = "SUCCESS"
if ($script:FailCount -gt 0 -or $script:InvalidCount -gt 0 -or $script:SettingsFailCount -gt 0) {
    $overallStatus = "COMPLETED WITH ISSUES"
}

Write-Step "SUMMARY Compiling final run report"
Print-StructuredReport -StatusLabel $overallStatus

if ($script:FailCount -gt 0 -or $script:InvalidCount -gt 0 -or $script:SettingsFailCount -gt 0) {
    exit 1
}

Write-Ok "VS Code setup completed successfully."
