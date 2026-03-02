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
        Write-Host "ERROR: winget (App Installer) is not installed." -ForegroundColor Red
        Write-Host "Install it from the Microsoft Store:" -ForegroundColor Red
        Write-Host "  https://www.microsoft.com/store/productId/9NBLGGH4NNS1" -ForegroundColor Yellow
        exit 1
    }

    $script:WingetExe = (Get-Command winget -ErrorAction Stop).Source
}

function Invoke-WingetUninstall {
    param(
        [string]$Id
    )

    $args = @("uninstall", "--id", $Id, "--exact", "--accept-source-agreements", "--accept-package-agreements", "--silent")
    & $script:WingetExe @args
    return $LASTEXITCODE
}

function Uninstall-WingetApp {
    param(
        [string]$Id,
        [string]$Description
    )

    Write-Info "Uninstalling: $Description ($Id)..."
    $exitCode = Invoke-WingetUninstall -Id $Id

    if ($exitCode -eq 0) {
        Write-Ok "Uninstalled: $Description"
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
        Write-Info "Removing $PathFragment from PATH..."
        $newPath = ($currentPath -split ';') | Where-Object { $_ -and ($_ -notlike "*$PathFragment*") } | Join-String -Separator ';'
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

    $installRoot = Join-Path $env:LOCALAPPDATA "Programs\Apache"
    Remove-FromPath -PathFragment "apache-maven"

    if (Test-Path $installRoot) {
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

# ============================================================
# Main script execution
# ============================================================
Write-Step "Starting rollback of minimal Windows developer environment..."

Assert-Winget

Write-Step "Uninstalling applications..."
Uninstall-WingetApp -Id "Git.Git" -Description "Git for Windows"
Uninstall-WingetApp -Id "Microsoft.OpenJDK.17" -Description "Microsoft OpenJDK 17"
Uninstall-WingetApp -Id "Microsoft.VisualStudioCode" -Description "Visual Studio Code"
Uninstall-WingetApp -Id "JetBrains.IntelliJIDEA.Community" -Description "IntelliJ IDEA Community"

Uninstall-Maven

Unset-JavaHome

Write-Warn "Restart your terminal to apply the environment changes."
Write-Host "`n`nRollback complete!" -ForegroundColor Green
