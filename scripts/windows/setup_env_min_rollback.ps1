# setup_env_min_rollback.ps1 - Rollback for Minimal Windows setup
#
# Uninstalls and cleans up:
#   1) Git
#   2) JDK (Microsoft OpenJDK 17)
#   3) Maven
#   4) VS Code
#   5) IntelliJ IDEA Community
#
# Usage (run as Administrator):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\setup_env_min_rollback.ps1

[CmdletBinding()]
param(
    # Shows what would happen without making changes.
    [switch]$DryRun,

    # If set, uses winget interactive mode and prompts which components to uninstall.
    [switch]$Interactive,

    # If set, uses winget silent mode (default). Ignored when -Interactive is used.
    [switch]$Silent,

    # Print help and exit
    [switch]$Help
)

# ============================================================
# Helper Functions
# ============================================================

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

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Assert-Winget {
    if (-not (Test-CommandExists "winget")) {
        if ($DryRun) {
            Write-Warn "DryRun: winget is not installed on this host; winget uninstalls will be skipped."
            $script:WingetExe = $null
            return
        }
        Write-Host "ERROR: winget (App Installer) is not installed." -ForegroundColor Red
        Write-Host "Install it from the Microsoft Store:" -ForegroundColor Red
        Write-Host "  https://www.microsoft.com/store/productId/9NBLGGH4NNS1" -ForegroundColor Yellow
        exit 1
    }

    $script:WingetExe = (Get-Command winget -ErrorAction Stop).Source
}

function Invoke-WingetUninstall {
    param(
        [string]$Id,
        [switch]$UseInteractive,
        [switch]$UseSilent
    )

    if ($DryRun) {
        Write-Info "DryRun: would run winget uninstall for $Id"
        return 0
    }

    if (-not $script:WingetExe) {
        Write-Warn "winget executable not available; cannot uninstall $Id"
        return 1
    }

    # NOTE: winget uninstall does not support --accept-package-agreements on some versions.
    # Keep args compatible with winget v1.12+ (per log) and PowerShell 5.1.
    $args = @(
        "uninstall",
        "--id", $Id,
        "--exact",
        "--accept-source-agreements",
        "--disable-interactivity",
        "--force"
    )

    if ($UseInteractive) {
        # Allow prompts/UX from the installer/uninstaller.
        $args += "--interactive"
    } elseif ($UseSilent) {
        $args += "--silent"
    }

    & $script:WingetExe @args
    return $LASTEXITCODE
}

function Uninstall-WingetApp {
    param(
        [string]$Id,
        [string]$Description,
        [switch]$UseInteractive,
        [switch]$UseSilent
    )

    Write-Info "Uninstalling: $Description ($Id)..."
    $exitCode = Invoke-WingetUninstall -Id $Id -UseInteractive:$UseInteractive -UseSilent:$UseSilent

    if ($exitCode -eq 0) {
        if ($DryRun) {
            Write-Ok "DryRun OK: $Description"
        } else {
            Write-Ok "Uninstalled: $Description"
        }
        return
    }
    if ($exitCode -eq -1978335189) { # Not found
        Write-Warn "Not installed: $Description - skipping."
        return
    }
     if ($exitCode -eq -1978335184) { # No applicable installer
        Write-Warn "Not installed: $Description - skipping."
        return
    }
    if ($exitCode -eq 3010 -or $exitCode -eq 1641) {
        Write-Warn "Uninstalled: $Description (reboot required)."
        return
    }

    Write-Warn "Could not uninstall $Description ($Id). Exit code: $exitCode"
}

function Remove-EnvironmentVar {
    param(
        [string]$Name,
        [string]$Scope = "User"
    )
    $currentValue = [Environment]::GetEnvironmentVariable($Name, $Scope)
    if ($currentValue) {
        if ($DryRun) {
            Write-Info "DryRun: would remove environment variable $Name ($Scope)"
            return
        }
        Write-Info "Removing environment variable $Name..."
        [Environment]::SetEnvironmentVariable($Name, $null, $Scope)
        Write-Ok "$Name removed."
    } else {
        Write-Warn "Environment variable $Name not set."
    }
}

function Remove-FromPath {
    param(
        [string]$PathFragment,
        [string]$Scope = "User"
    )
    $currentPath = [Environment]::GetEnvironmentVariable("Path", $Scope)
    if ($currentPath -and ($currentPath -like "*$PathFragment*")) {
        if ($DryRun) {
            Write-Info "DryRun: would remove $PathFragment from PATH ($Scope)"
            return
        }

        Write-Info "Removing $PathFragment from PATH..."

        $parts = $currentPath -split ';' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and ($_ -notlike "*$PathFragment*") }

        # PowerShell 5.1 compatible join (Join-String is PS7+)
        $newPath = [string]::Join(';', $parts)

        [Environment]::SetEnvironmentVariable("Path", $newPath, $Scope)
        Write-Ok "PATH updated."
    } else {
        Write-Warn "$PathFragment not found in PATH."
    }
}

function Uninstall-Maven {
    Write-Step "Uninstalling Maven..."
    Remove-EnvironmentVar -Name "MAVEN_HOME"
    Remove-EnvironmentVar -Name "M2_HOME"

    Remove-FromPath -PathFragment "apache-maven"

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Write-Warn "LOCALAPPDATA is not set; skipping Maven directory cleanup."
        return
    }

    $installRoot = Join-Path $env:LOCALAPPDATA "Programs\Apache"

    if (Test-Path $installRoot) {
        if ($DryRun) {
            Write-Info "DryRun: would delete Maven directory: $installRoot"
            return
        }
        Write-Info "Deleting Maven directory: $installRoot"
        Remove-Item -Recurse -Force $installRoot
        Write-Ok "Maven directory deleted."
    } else {
        Write-Warn "Maven directory not found."
    }
}

function Unset-JavaHome {
    Write-Step "Unsetting JAVA_HOME..."
    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    if ($javaHome) {
        Remove-FromPath -PathFragment "$javaHome\bin"
    }
    Remove-EnvironmentVar -Name "JAVA_HOME"
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$DefaultYes = $true
    )

    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $DefaultYes
        }
        switch ($answer.Trim().ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
        }
        Write-Warn "Please answer y or n."
    }
}

# ============================================================
# Main script execution
# ============================================================
Write-Step "Starting rollback of minimal Windows developer environment..."

if ($Help) {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Usage: .\scripts\windows\setup_env_min_rollback.ps1 [ -DryRun ] [ -Interactive ] [ -Silent ] [ -Help ]" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\scripts\windows\setup_env_min_rollback.ps1          # Silent (default)" -ForegroundColor Cyan
    Write-Host "  .\scripts\windows\setup_env_min_rollback.ps1 -Interactive  # Choose what to uninstall" -ForegroundColor Cyan
    Write-Host "  .\scripts\windows\setup_env_min_rollback.ps1 -DryRun       # Preview actions, no changes" -ForegroundColor Cyan
    exit 0
}

Assert-Winget

# Default behavior: silent unless explicitly interactive
$useInteractive = $false
$useSilent = $true
if ($Interactive) {
    $useInteractive = $true
    $useSilent = $false
} elseif ($Silent) {
    $useInteractive = $false
    $useSilent = $true
}

$components = @(
    [pscustomobject]@{ Key = 'Git';        Description = 'Git for Windows';        Kind = 'Winget'; Id = 'Git.Git' },
    [pscustomobject]@{ Key = 'JDK';        Description = 'Microsoft OpenJDK 17';   Kind = 'Winget'; Id = 'Microsoft.OpenJDK.17' },
    [pscustomobject]@{ Key = 'VSCode';     Description = 'Visual Studio Code';    Kind = 'Winget'; Id = 'Microsoft.VisualStudioCode' },
    [pscustomobject]@{ Key = 'IntelliJ';   Description = 'IntelliJ IDEA Community'; Kind = 'Winget'; Id = 'JetBrains.IntelliJIDEA.Community' },
    [pscustomobject]@{ Key = 'Maven';      Description = 'Maven + env vars';       Kind = 'Maven' },
    [pscustomobject]@{ Key = 'JAVA_HOME';  Description = 'JAVA_HOME + PATH entry'; Kind = 'JavaHome' }
)

$selected = @()
if ($Interactive) {
    Write-Step "Interactive mode: choose what to uninstall"
    foreach ($c in $components) {
        $doIt = Read-YesNo -Prompt ("Uninstall {0}?" -f $c.Description) -DefaultYes:$true
        if ($doIt) {
            $selected += $c
        }
    }

    if (-not $selected -or $selected.Count -eq 0) {
        Write-Warn "Nothing selected. Exiting."
        exit 0
    }
} else {
    $selected = $components
}

Write-Step "Uninstalling selected components..."

foreach ($c in $selected) {
    switch ($c.Kind) {
        'Winget' {
            Uninstall-WingetApp -Id $c.Id -Description $c.Description -UseInteractive:$useInteractive -UseSilent:$useSilent
        }
        'Maven' {
            Uninstall-Maven
        }
        'JavaHome' {
            Unset-JavaHome
        }
        default {
            Write-Warn "Unknown component kind: $($c.Kind)"
        }
    }
}

Write-Warn "Restart your terminal to apply the environment changes."
Write-Host "`n`nRollback complete!" -ForegroundColor Green
