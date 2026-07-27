# powershell_profile_setup.ps1 - Source repo-managed PowerShell profile config
#
# Usage:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\windows\powershell_profile_setup.ps1
#   .\scripts\windows\powershell_profile_setup.ps1 -DryRun

# Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$ConfigPath,
    [switch]$DryRun
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$script:ScriptStart = Get-Date
$script:RemovedCount = 0
$script:FailureCount = 0
$script:SourceLineAdded = 0

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

function Record-Failure {
    param([string]$Message)
    Write-EbkError $Message
    $script:FailureCount++
}

function Get-CoveredLines {
    return @(
        'Set-Alias -Name profile -Value Edit-Profile',
        'Set-Alias -Name reload -Value Reload-Profile',
        'Set-Alias -Name c -Value Clear-Host',
        'Set-Alias -Name cat -Value bat -Option AllScope',
        'Set-Alias -Name tldr -Value tlrc',
        '$env:EDITOR = "notepad"'
    )
}

function Test-CoveredLine {
    param([string]$Line)

    foreach ($coveredLine in (Get-CoveredLines)) {
        if ($Line -eq $coveredLine) {
            return $true
        }
    }
    return $false
}

function Validate-RepoConfig {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Record-Failure "Repo config not found: $ConfigPath"
        return $false
    }

    try {
        [ScriptBlock]::Create((Get-Content -Raw -Path $ConfigPath)) | Out-Null
        Write-Ok "Profile config syntax OK: $ConfigPath"
        return $true
    } catch {
        Record-Failure "Profile config syntax failed: $ConfigPath - $_"
        return $false
    }
}

function Backup-Profile {
    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        Write-Info "PowerShell profile does not exist yet; it will be created on first write."
        return $true
    }

    $backup = "{0}.bak.{1}" -f $ProfilePath, (Get-Date -Format "yyyyMMdd-HHmmss")
    if ($DryRun) {
        Write-Info "DryRun: would back up $ProfilePath to $backup"
        return $true
    }

    try {
        Copy-Item -Path $ProfilePath -Destination $backup -Force -ErrorAction Stop
        Write-Ok "Backed up profile to $backup"
        return $true
    } catch {
        Record-Failure "Failed to back up PowerShell profile. $_"
        return $false
    }
}

function Remove-CoveredLines {
    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        Write-Info "PowerShell profile not found; skipping line removal."
        return $true
    }

    $lines = Get-Content -Path $ProfilePath -ErrorAction Stop
    $kept = New-Object System.Collections.Generic.List[string]
    $consecutiveBlanks = 0

    foreach ($line in $lines) {
        if (Test-CoveredLine -Line $line) {
            $script:RemovedCount++
            if ($DryRun) {
                Write-Info "DryRun: would remove covered line: $line"
            } else {
                Write-Info "Removing covered line: $line"
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            $consecutiveBlanks++
            if ($consecutiveBlanks -gt 1) {
                continue
            }
        } else {
            $consecutiveBlanks = 0
        }

        [void]$kept.Add($line)
    }

    if ($DryRun) {
        Write-Info ("DryRun: would remove {0} covered line(s) from PowerShell profile." -f $script:RemovedCount)
        return $true
    }

    try {
        $kept | Set-Content -Path $ProfilePath -Encoding UTF8 -ErrorAction Stop
        if ($script:RemovedCount -gt 0) {
            Write-Ok ("Removed {0} covered line(s) from PowerShell profile." -f $script:RemovedCount)
        } else {
            Write-Info "No covered lines found in PowerShell profile; nothing to remove."
        }
        return $true
    } catch {
        Record-Failure "Failed to write filtered PowerShell profile. $_"
        return $false
    }
}

function Ensure-SourceLine {
    $sourceLine = '. "{0}"' -f $ConfigPath

    if (Test-Path -LiteralPath $ProfilePath) {
        $existing = Get-Content -Path $ProfilePath -ErrorAction Stop
        if ($existing -contains $sourceLine) {
            Write-Info "PowerShell profile already sources the repo config."
            return $true
        }
    }

    if ($DryRun) {
        Write-Info "DryRun: would append to PowerShell profile:"
        Write-Info "  # dev-tools shared config"
        Write-Info "  $sourceLine"
        return $true
    }

    try {
        $profileDir = Split-Path -Parent $ProfilePath
        if (-not (Test-Path -LiteralPath $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force -ErrorAction Stop | Out-Null
        }

        Add-Content -Path $ProfilePath -Encoding UTF8 -Value ""
        Add-Content -Path $ProfilePath -Encoding UTF8 -Value "# dev-tools shared config"
        Add-Content -Path $ProfilePath -Encoding UTF8 -Value $sourceLine
        $script:SourceLineAdded = 1
        Write-Ok "Appended source line to PowerShell profile."
        return $true
    } catch {
        Record-Failure "Failed to append source line to PowerShell profile. $_"
        return $false
    }
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
    Write-Host ("  {0,-24} {1}" -f "Script", "PowerShell Profile Setup (Windows)")
    Write-Host ("  {0,-24} {1}" -f "Profile", $ProfilePath)
    Write-Host ("  {0,-24} {1}" -f "Repo config", $ConfigPath)
    Write-Host ("  {0,-24} {1}" -f "Status", $StatusLabel)
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
    Write-Host ("  {0,-24} {1}" -f "Covered lines removed", $script:RemovedCount)
    Write-Host ("  {0,-24} {1}" -f "Source line added", $script:SourceLineAdded)
    Write-Host ("  {0,-24} {1}" -f "Failures", $script:FailureCount)
    Write-Host ("  {0,-24} {1}" -f "Duration", (Format-Duration -Duration ((Get-Date) - $script:ScriptStart)))
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
}

$scriptDir = Resolve-ScriptDir
if (-not $scriptDir) {
    Write-EbkError "Could not resolve script directory."
    exit 1
}

$repoRoot = Resolve-RepoRoot -ScriptDir $scriptDir
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $repoRoot "config\Microsoft.PowerShell_profile.ps1"
}
if (-not $ProfilePath) {
    $ProfilePath = $PROFILE.CurrentUserAllHosts
}

$resolvedConfig = Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue
if ($resolvedConfig) {
    $ConfigPath = $resolvedConfig.Path
}

Write-Step "PowerShell profile setup"
Write-Info "Merging repo config into PowerShell profile (source approach)"
Write-Info "Profile: $ProfilePath"
Write-Info "Repo config: $ConfigPath"

$ok = $true
$ok = (Validate-RepoConfig) -and $ok
$ok = (Backup-Profile) -and $ok
$ok = (Remove-CoveredLines) -and $ok
$ok = (Ensure-SourceLine) -and $ok

$finalStatus = "SUCCESS"
if (-not $ok -or $script:FailureCount -gt 0) {
    $finalStatus = "FAILED"
} elseif ($DryRun) {
    $finalStatus = "DRY RUN"
} elseif ($script:SourceLineAdded -eq 0 -and $script:RemovedCount -eq 0) {
    $finalStatus = "NO CHANGES"
}

Write-Step "SUMMARY Compiling final run report"
Print-StructuredReport -StatusLabel $finalStatus

if (-not $ok -or $script:FailureCount -gt 0) {
    exit 1
}

if ($DryRun) {
    Write-Ok "Dry run complete. No changes were made."
} else {
    Write-Ok "Done. Restart PowerShell or run: . `$PROFILE"
}
