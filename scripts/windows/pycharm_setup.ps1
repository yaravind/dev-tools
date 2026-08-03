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

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
    Initialize-EbkPaletteIfNeeded
    $Script:ThemeHeaderColor = $script:EbPhaseAnsi
    $Script:ThemeBodyColor = $script:EbTextAnsi
    $Script:ThemeSuccessColor = $script:EbOkAnsi
    $Script:ThemeWarnColor = $script:EbWarnAnsi
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
    try { return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected } catch { return $false }
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
        if (Test-CommandExists $cmd) { return (Get-Command $cmd -ErrorAction Stop).Source }
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
    $noisePattern = '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}|^\s*plugin repositories:\s*\[null\]\s*$|^\s+at |^(java|kotlin)\.|^Caused by:|^WARNING:|^\s*$'
    return @($Lines | Where-Object { $_ -notmatch $noisePattern })
}

function Parse-MissingDependencies {
    param([string[]]$RawLines)
    $deps = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    $depParents = @{}
    foreach ($line in $RawLines) {
        if ($line -match "Plugin '[^']+'\s+\(([^)]+)\)\s+has dependency on '([^']+)'") {
            $parent = $Matches[1].Trim()
            $depId = $Matches[2].Trim()
            if ($depId) {
                [void]$deps.Add($depId)
                if (-not $depParents.ContainsKey($depId)) {
                    $depParents[$depId] = $parent
                }
            }
        } elseif ($line -match "dependency on '([^']+)'") {
            [void]$deps.Add($Matches[1].Trim())
        }
    }
    return [PSCustomObject]@{
        Dependencies = @($deps)
        DependencyParents = $depParents
    }
}

function Invoke-PyCharmPluginInstall {
    param([string]$CliPath, [string]$PluginId)

    $rawLines = @(& $CliPath installPlugins $PluginId 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $rawOutput = $rawLines -join "`n"

    $filtered = Filter-PluginInstallOutput -Lines $rawLines
    foreach ($line in $filtered) { Write-Host $line }

    $dependencyParse = Parse-MissingDependencies -RawLines $rawLines

    $status = "failed"
    if ($rawOutput -match "already installed") { $status = "already" }
    elseif ($rawOutput -match "unknown plugins") { $status = "unknown" }
    elseif ($exitCode -eq 0) { $status = "installed" }

    return [PSCustomObject]@{
        Status = $status
        MissingDependencies = $dependencyParse.Dependencies
        MissingDependencyParents = $dependencyParse.DependencyParents
    }
}

function Print-StructuredReport {
    param(
        [string]$Mode,
        [string]$ConfigPath,
        [string]$Launcher,
        [string]$OverallStatus,
        [int]$InitialRequestedCount,
        [int]$AttemptedCount,
        [int]$InstalledCount,
        [int]$SkippedCount,
        [int]$AutoDependencyCount,
        [int]$UnknownCount,
        [int]$FailCount,
        [int]$EditionSkipCount,
        [int]$DocumentedSkipCount,
        [int]$DuplicateCount,
        [int]$InvalidCount,
        [string[]]$NetNewPlugins,
        [string[]]$DependencyOrder,
        [hashtable]$DependencyParent
    )

    $statusIcon = if ($OverallStatus -eq "SUCCESS") { "✔" } else { "⚠" }
    $statusColor = if ($OverallStatus -eq "SUCCESS") { $Script:ThemeSuccessColor } else { $Script:ThemeWarnColor }

    Write-Host ""
    Write-EbkThemedHost -Text "Final Status Report" -Color $Script:ThemeHeaderColor
    Write-EbkThemedHost -Text "──────────────────────────────────────────────────────────────────────────────" -Color $Script:ThemeHeaderColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Script", "PyCharm Plugin Setup (Windows)") -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Mode", "--$Mode") -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Config", $ConfigPath) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Launcher", $Launcher) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1} {2}" -f "Status", $statusIcon, $OverallStatus) -Color $statusColor
    Write-EbkThemedHost -Text "──────────────────────────────────────────────────────────────────────────────" -Color $Script:ThemeHeaderColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Requested", $InitialRequestedCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Attempted", $AttemptedCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Installed (net new)", $InstalledCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Already installed", $SkippedCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Auto dependencies queued", $AutoDependencyCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Unknown IDs", $UnknownCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Failed installs", $FailCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Edition skips", $EditionSkipCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Documented skips", $DocumentedSkipCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Duplicates ignored", $DuplicateCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text ("  {0,-24} {1}" -f "Invalid entries ignored", $InvalidCount) -Color $Script:ThemeBodyColor
    Write-EbkThemedHost -Text "──────────────────────────────────────────────────────────────────────────────" -Color $Script:ThemeHeaderColor

    Write-EbkThemedHost -Text "Net New Plugins Installed" -Color $Script:ThemeHeaderColor
    if (-not $NetNewPlugins -or $NetNewPlugins.Count -eq 0) {
        Write-EbkThemedHost -Text "  No net-new plugins were installed in this run." -Color $Script:ThemeBodyColor
    } else {
        foreach ($plugin in $NetNewPlugins) { Write-EbkThemedHost -Text "  • $plugin" -Color $Script:ThemeSuccessColor }
    }

    Write-Host ""
    Write-EbkThemedHost -Text "Next Steps" -Color $Script:ThemeHeaderColor
    if (-not $DependencyOrder -or $DependencyOrder.Count -eq 0) {
        Write-EbkThemedHost -Text "  No missing dependencies were detected." -Color $Script:ThemeBodyColor
    } else {
        Write-EbkThemedHost -Text "Suggested dependency entries to add to config/pycharm.txt" -Color $Script:ThemeHeaderColor
        Write-Host ("| {0,-40} | {1,-34} | {2,-40} |" -f "Plugin ID", "Required By", "Suggested Entry")
        Write-Host ("|-{0,-40}-|-{1,-34}-|-{2,-40}-|" -f ("-" * 40), ("-" * 34), ("-" * 40))
        foreach ($dep in $DependencyOrder) {
            $parent = $DependencyParent[$dep]
            $suggested = "community:$dep"
            Write-Host ("| {0,-40} | {1,-34} | {2,-40} |" -f $dep, $parent, $suggested)
        }
        Write-EbkThemedHost -Text "  Review and add the suggested entries if you want deterministic future installs." -Color $Script:ThemeBodyColor
    }
}

$scriptDir = Resolve-ScriptDir
if (-not $scriptDir) { Write-Err "Could not resolve script directory." ; exit 1 }

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
$dependencyOrder = New-Object System.Collections.Generic.List[string]
$dependencyParent = @{}
$netNewPlugins = New-Object System.Collections.Generic.List[string]
$duplicateCount = 0
$invalidCount = 0
$editionSkipCount = 0
$documentedSkipCount = 0
$autoDependencyCount = 0

foreach ($line in Get-Content -Path $ConfigPath -ErrorAction Stop) {
    if ($null -eq $line) { continue }
    $entry = $line.Trim()
    if (-not $entry -or $entry.StartsWith("#")) { continue }

    $pluginEdition = "community"
    $pluginId = $entry
    if ($entry -match '^(community|professional|bundled|unavailable)\s*:\s*(.+)$') {
        $pluginEdition = $Matches[1].ToLowerInvariant()
        $pluginId = $Matches[2].Trim()
    }

    if ($pluginEdition -in @("bundled", "unavailable")) {
        Write-Warn "Skipping documented $pluginEdition plugin `"$pluginId`"."
        $documentedSkipCount++
        continue
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

if ($pluginsToInstall.Count -eq 0) { Write-Err "No valid plugin IDs found in $ConfigPath." ; exit 1 }
$initialRequestedCount = $pluginsToInstall.Count

if ((-not $DryRun) -and (Test-PyCharmRunning)) {
    Write-Err "PyCharm appears to be running. Quit PyCharm, then re-run this script."
    exit 1
}

$pyCharmCli = Resolve-PyCharmCli -AllowMissing:$DryRun
if ($pyCharmCli) { Write-Step "Using PyCharm launcher: $pyCharmCli" }
Write-Info ("Total plugin IDs queued: {0}" -f $pluginsToInstall.Count)

$installCount = 0
$skipCount = 0
$unknownCount = 0
$failCount = 0
$dryRunCount = 0

$index = 0
while ($index -lt $pluginsToInstall.Count) {
    $pluginId = $pluginsToInstall[$index]
    Write-Step ("Installing plugin [{0}/{1}]: {2}" -f ($index + 1), $pluginsToInstall.Count, $pluginId)

    if ($DryRun) {
        Write-Info "DryRun: would install plugin: $pluginId"
        $dryRunCount++
        $index++
        continue
    }

    $result = Invoke-PyCharmPluginInstall -CliPath $pyCharmCli -PluginId $pluginId
    foreach ($depId in $result.MissingDependencies) {
        if ([string]::IsNullOrWhiteSpace($depId)) { continue }
        $requiredBy = if ($result.MissingDependencyParents.ContainsKey($depId)) { $result.MissingDependencyParents[$depId] } else { $pluginId }

        if (-not $dependencyParent.ContainsKey($depId)) {
            $dependencyParent[$depId] = $requiredBy
            [void]$dependencyOrder.Add($depId)
        }

        if ($seenPlugins.Add($depId)) {
            [void]$pluginsToInstall.Add($depId)
            $autoDependencyCount++
            Write-Info "Queued missing dependency plugin: $depId (required by $requiredBy)"
        }
    }

    switch ($result.Status) {
        "installed" {
            Write-Ok "Installed `"$pluginId`"."
            $installCount++
            [void]$netNewPlugins.Add($pluginId)
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

    $index++
}

if ($DryRun) { Write-Info ("DryRun plugins previewed: {0}" -f $dryRunCount) }

$overallStatus = "SUCCESS"
if ($failCount -gt 0 -or $invalidCount -gt 0 -or $unknownCount -gt 0) { $overallStatus = "COMPLETED WITH ISSUES" }

Print-StructuredReport `
    -Mode $mode `
    -ConfigPath $ConfigPath `
    -Launcher $pyCharmCli `
    -OverallStatus $overallStatus `
    -InitialRequestedCount $initialRequestedCount `
    -AttemptedCount $index `
    -InstalledCount $installCount `
    -SkippedCount $skipCount `
    -AutoDependencyCount $autoDependencyCount `
    -UnknownCount $unknownCount `
    -FailCount $failCount `
    -EditionSkipCount $editionSkipCount `
    -DocumentedSkipCount $documentedSkipCount `
    -DuplicateCount $duplicateCount `
    -InvalidCount $invalidCount `
    -NetNewPlugins @($netNewPlugins) `
    -DependencyOrder @($dependencyOrder) `
    -DependencyParent $dependencyParent

if ($overallStatus -ne "SUCCESS") {
    Write-Err "PyCharm setup completed with issues."
    exit 1
}

Write-Ok "PyCharm setup completed successfully."
