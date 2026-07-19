# pycharm_setup.ps1 - Install PyCharm plugins from config on Windows
#
# Usage (PowerShell):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\windows\pycharm_setup.ps1
#   .\scripts\windows\pycharm_setup.ps1 -Community
#   .\scripts\windows\pycharm_setup.ps1 -Professional
#   .\scripts\windows\pycharm_setup.ps1 -Yes
#   .\scripts\windows\pycharm_setup.ps1 -DryRun

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Professional,
    [switch]$Community,
    [switch]$Yes,
    [Alias("WhatIf")]
    [switch]$DryRun
)

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
    Write-Host "===> WARN: $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
}

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Resolve-ScriptDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    return (Split-Path -Parent $PSCommandPath)
}

function Test-IsInteractiveInput {
    try {
        return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    } catch {
        return $false
    }
}

function Print-ModeOptions {
    Write-Step "Select PyCharm plugin installation mode"
    Write-Info "1) --professional (default): install community and professional plugin entries"
    Write-Info "2) --community            : install only community entries and skip professional entries"
}

function Resolve-Mode {
    if ($Professional -and $Community) {
        Write-Err "Use only one mode switch: -Professional or -Community."
        exit 1
    }

    if ($Professional) { return "professional" }
    if ($Community) { return "community" }

    $mode = "professional"
    if ($Yes) {
        Write-Warn "Non-interactive confirmation enabled (-Yes); using mode: --$mode"
        return $mode
    }

    if (-not (Test-IsInteractiveInput)) {
        Write-Warn "No interactive terminal detected; using mode: --$mode"
        return $mode
    }

    while ($true) {
        $choice = Read-Host "Enter mode [1/2] (default: --$mode)"
        $choice = if ($null -eq $choice) { "" } else { $choice.Trim() }
        switch -Regex ($choice) {
            '^(|1|professional|--professional)$' { return "professional" }
            '^(2|community|--community)$' { return "community" }
            default { Write-Warn "Invalid selection '$choice'. Enter 1 or 2." }
        }
    }
}

function Test-PyCharmRunning {
    $p = Get-Process -Name pycharm64, pycharm -ErrorAction SilentlyContinue
    return $null -ne $p
}

function Resolve-PyCharmCli {
    param([switch]$AllowMissing)

    $candidates = New-Object System.Collections.Generic.List[string]
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs")

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $candidates.Add((Join-Path $root "JetBrains\PyCharm\bin\pycharm64.exe"))
        $candidates.Add((Join-Path $root "JetBrains\PyCharm Community Edition\bin\pycharm64.exe"))
        $candidates.Add((Join-Path $root "JetBrains\PyCharm Professional\bin\pycharm64.exe"))
    }

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) { continue }
        $wildcards = @(
            (Join-Path $root "JetBrains\PyCharm*\bin\pycharm64.exe"),
            (Join-Path $root "JetBrains\PyCharm* Edition\bin\pycharm64.exe")
        )
        foreach ($wc in $wildcards) {
            $found = Get-Item -Path $wc -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    foreach ($cmd in @("pycharm64.exe", "pycharm64", "pycharm.exe", "pycharm")) {
        if (Test-CommandExists $cmd) {
            return (Get-Command $cmd -ErrorAction Stop).Source
        }
    }

    if ($AllowMissing) {
        Write-Warn "PyCharm CLI not found on this host. Continuing due to -DryRun."
        return $null
    }

    Write-Err "PyCharm CLI not found. Launch PyCharm once and ensure pycharm64.exe (or pycharm) is available."
    exit 1
}

function Filter-PluginInstallOutput {
    param([string[]]$Lines)

    if (-not $Lines) { return @() }
    $noisePattern = '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}|^\s+at |^(java|kotlin)\.|^Caused by:|^WARNING:|^\s*$'
    return @($Lines | Where-Object { $_ -notmatch $noisePattern })
}

function Invoke-PyCharmPluginInstall {
    param(
        [string]$CliPath,
        [string]$PluginId
    )

    $rawLines = @(& $CliPath installPlugins $PluginId 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $rawOutput = $rawLines -join "`n"

    $filtered = Filter-PluginInstallOutput -Lines $rawLines
    foreach ($line in $filtered) {
        Write-Host $line
    }

    if ($rawOutput -match "already installed") { return "already" }
    if ($rawOutput -match "unknown plugins") { return "unknown" }
    if ($exitCode -eq 0) { return "installed" }
    return "failed"
}

$scriptDir = Resolve-ScriptDir
if (-not $scriptDir) {
    Write-Err "Could not resolve script directory."
    exit 1
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $scriptDir ".."
    $ConfigPath = Join-Path $ConfigPath ".."
    $ConfigPath = Join-Path $ConfigPath "config"
    $ConfigPath = Join-Path $ConfigPath "pycharm.txt"
}

$resolvedConfig = Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue
if ($resolvedConfig) {
    $ConfigPath = $resolvedConfig.Path
} elseif (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Err "Config file not found: $ConfigPath"
    exit 1
}

Print-ModeOptions
$mode = Resolve-Mode
Write-Info "Selected mode: --$mode"
Write-Step "Reading PyCharm plugin IDs from $ConfigPath"

$pluginsToInstall = New-Object System.Collections.Generic.List[string]
$seenPlugins = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
$duplicateCount = 0
$invalidCount = 0
$editionSkipCount = 0

foreach ($line in Get-Content -Path $ConfigPath -ErrorAction Stop) {
    if ($null -eq $line) { continue }
    $entry = $line.Trim()
    if (-not $entry -or $entry.StartsWith("#")) { continue }

    $pluginEdition = "community"
    $pluginId = $entry
    if ($entry -match '^(community|professional)\s*:\s*(.+)$') {
        $pluginEdition = $Matches[1].ToLowerInvariant()
        $pluginId = $Matches[2].Trim()
    }

    if ($pluginEdition -eq "professional" -and $mode -eq "community") {
        Write-Warn "Skipping professional-only plugin `"$pluginId`" in --community mode."
        $editionSkipCount++
        continue
    }

    if ($pluginId -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]*$') {
        Write-Warn "Ignoring invalid plugin ID `"$pluginId`"."
        $invalidCount++
        continue
    }

    if (-not $seenPlugins.Add($pluginId)) {
        Write-Warn "Duplicate plugin ID `"$pluginId`" in config. Ignoring duplicate entry."
        $duplicateCount++
        continue
    }

    [void]$pluginsToInstall.Add($pluginId)
}

if ($pluginsToInstall.Count -eq 0) {
    Write-Err "No valid plugin IDs found in $ConfigPath."
    exit 1
}

if ((-not $DryRun) -and (Test-PyCharmRunning)) {
    Write-Err "PyCharm appears to be running. Quit PyCharm, then re-run this script."
    exit 1
}

$pyCharmCli = Resolve-PyCharmCli -AllowMissing:$DryRun
if ($pyCharmCli) {
    Write-Step "Using PyCharm launcher: $pyCharmCli"
}
Write-Info ("Total plugin IDs queued: {0}" -f $pluginsToInstall.Count)

$installCount = 0
$skipCount = 0
$unknownCount = 0
$failCount = 0
$dryRunCount = 0

for ($i = 0; $i -lt $pluginsToInstall.Count; $i++) {
    $pluginId = $pluginsToInstall[$i]
    Write-Step ("Installing plugin [{0}/{1}]: {2}" -f ($i + 1), $pluginsToInstall.Count, $pluginId)

    if ($DryRun) {
        Write-Info "DryRun: would install plugin: $pluginId"
        $dryRunCount++
        continue
    }

    $result = Invoke-PyCharmPluginInstall -CliPath $pyCharmCli -PluginId $pluginId
    switch ($result) {
        "installed" {
            Write-Ok "Installed `"$pluginId`"."
            $installCount++
        }
        "already" {
            Write-Warn "Plugin `"$pluginId`" is already installed. Skipping."
            $skipCount++
        }
        "unknown" {
            Write-Warn "Plugin `"$pluginId`" not found in Marketplace (unknown plugin ID). Check the ID or remove from config."
            $unknownCount++
        }
        default {
            Write-Err "Failed to install `"$pluginId`"."
            $failCount++
        }
    }
}

Write-Step "PyCharm plugin setup complete."
Write-Ok ("Installed: {0}" -f $installCount)
Write-Warn ("Skipped (already installed): {0}" -f $skipCount)
Write-Warn ("Skipped by edition mode: {0}" -f $editionSkipCount)
Write-Warn ("Duplicates ignored: {0}" -f $duplicateCount)
Write-Warn ("Invalid ignored: {0}" -f $invalidCount)
if ($unknownCount -gt 0) {
    Write-Warn ("Unknown plugin IDs (not in Marketplace): {0}" -f $unknownCount)
} else {
    Write-Ok ("Unknown plugin IDs: {0}" -f $unknownCount)
}
if ($DryRun) {
    Write-Info ("DryRun plugins previewed: {0}" -f $dryRunCount)
}
if ($failCount -gt 0) {
    Write-Err ("Failed: {0}" -f $failCount)
} else {
    Write-Ok ("Failed: {0}" -f $failCount)
}

if ($failCount -gt 0 -or $invalidCount -gt 0 -or $unknownCount -gt 0) {
    Write-Err "PyCharm setup completed with issues."
    exit 1
}

Write-Ok "PyCharm setup completed successfully."
