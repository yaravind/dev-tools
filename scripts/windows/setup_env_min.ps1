# setup_env_min.ps1 - Minimal Windows setup for JDK-based development
#
# Installs and verifies:
#   1) Git
#   2) JDK (Microsoft OpenJDK 17)
#   3) Maven (via maven_setup.ps1)
#   4) VS Code
#   5) IntelliJ IDEA Community
#
# Usage (run as Administrator):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\setup_env_min.ps1

[CmdletBinding()]
param(
    # Shows what would happen without making changes.
    [switch]$DryRun,

    # If set, uses winget interactive mode and prompts which components to install.
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

function Test-IntelliJInstalled {
    $possiblePaths = @(
        "C:\\Program Files\\JetBrains\\IntelliJ IDEA Community Edition\\bin\\idea64.exe",
        "C:\\Program Files\\JetBrains\\IntelliJ IDEA Community Edition*\\bin\\idea64.exe",
        "$env:LOCALAPPDATA\\JetBrains\\IntelliJ IDEA Community Edition\\bin\\idea64.exe",
        "$env:LOCALAPPDATA\\JetBrains\\IntelliJ IDEA Community Edition*\\bin\\idea64.exe"
    )

    foreach ($path in $possiblePaths) {
        $found = Get-Item -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return $true
        }
    }

    return $false
}

function Assert-Winget {
    if (-not (Test-CommandExists "winget")) {
        if ($DryRun) {
            Write-Warn "DryRun: winget is not installed on this host; winget installs will be skipped."
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

function Invoke-WingetInstall {
    param(
        [string]$Id,
        [switch]$UseInteractive,
        [switch]$NoSilent
    )

    if ($DryRun) {
        Write-Info "DryRun: would run winget install for $Id (interactive=$UseInteractive, silent=$NoSilent)"
        return 0
    }

    if (-not $script:WingetExe) {
        Write-Warn "winget executable not available; cannot install $Id"
        return 1
    }

    $args = @("install", "--id", $Id, "--exact", "--accept-source-agreements", "--accept-package-agreements")
    if ($UseInteractive) {
        $args += "--interactive"
    } elseif (-not $NoSilent) {
        $args += "--silent"
    }

    & $script:WingetExe @args
    return $LASTEXITCODE
}

function Install-WingetApp {
    param(
        [string]$Id,
        [string]$Description,
        [string]$SkipCommand,
        [switch]$UseInteractive,
        [switch]$NoSilent
    )
    if ($SkipCommand -and (Test-CommandExists $SkipCommand)) {
        Write-Warn "$SkipCommand already available. Skipping $Description."
        return
    }

    Write-Info "Installing: $Description ($Id)..."
    $exitCode = Invoke-WingetInstall -Id $Id -UseInteractive:$UseInteractive -NoSilent:$NoSilent

    if ($exitCode -eq 0) {
        if ($DryRun) {
            Write-Ok "DryRun OK: $Description"
        } else {
            Write-Ok "Installed: $Description"
        }
        return
    }
    if ($exitCode -eq -1978335189) {
        Write-Warn "Already installed: $Description - skipping."
        return
    }
    if ($exitCode -eq 3010 -or $exitCode -eq 1641) {
        Write-Warn "Installed: $Description (reboot required)."
        return
    }

    Write-Warn "Could not install $Description ($Id). Exit code: $exitCode"
}

function Refresh-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# Print PATH entries one per line for quick verification (scope: Session|Machine|User)
function Print-PathEntries {
    param(
        [ValidateSet("Session","Machine","User")]
        [string]$Scope = "Session"
    )

    switch ($Scope) {
        'Session' { $pathValue = $env:Path }
        'Machine' { $pathValue = [Environment]::GetEnvironmentVariable('Path', 'Machine') }
        'User'    { $pathValue = [Environment]::GetEnvironmentVariable('Path', 'User') }
    }

    if (-not $pathValue) {
        Write-Warn "PATH ($Scope) is empty or not available."
        return
    }

    Write-Info "PATH ($Scope) entries (one per line):"
    $entries = $pathValue -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $index = 0
    foreach ($entry in $entries) {
        $index++
        Write-Host ("  {0:D2}: {1}" -f $index, $entry)
    }
}

function Install-Maven {
    if (Test-CommandExists "mvn") {
        Write-Warn "mvn already available. Skipping Maven install."
        return
    }

    $scriptDir = if ($PSScriptRoot) {
        $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path) {
        Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        Split-Path -Parent $PSCommandPath
    }
    if (-not $scriptDir) {
        Write-Warn "Could not resolve script directory for Maven installer lookup."
        return
    }
    $mavenScript = Join-Path $scriptDir "maven_setup.ps1"
    if (-not (Test-Path $mavenScript)) {
        Write-Warn "Maven installer not found at $mavenScript"
        return
    }
    & $mavenScript
}

function Set-JavaHome {
    Write-Step "Setting up JAVA_HOME..."

    $jdkSearchPaths = @(
        "C:\Program Files\Microsoft\jdk-*",
        "C:\Program Files\Eclipse Adoptium\jdk-*",
        "C:\Program Files\Java\jdk-*"
    )

    $latestJdk = $null
    foreach ($searchPath in $jdkSearchPaths) {
        $found = Get-Item -Path $searchPath -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($found) {
            $latestJdk = $found.FullName
            break
        }
    }

    if ($latestJdk) {
        Write-Info "Found JDK at: $latestJdk"
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $latestJdk, "User")
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $jdkBin = "$latestJdk\bin"
        if ($currentPath -notlike "*$jdkBin*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$jdkBin", "User")
        }
        Write-Ok "JAVA_HOME set to: $latestJdk"
        Write-Warn "Restart your terminal to apply the JAVA_HOME change."
    } else {
        Write-Warn "No JDK found in standard locations. Set JAVA_HOME manually after installing a JDK."
    }
}

function Invoke-Verify {
    Write-Step "Start verification"

    Write-Info "Verify Git..."
    if (Test-CommandExists "git") { git --version } else { Write-Warn "git not found in PATH. Restart your terminal." }

    Write-Info "Verify Java..."
    if (Test-CommandExists "java") { java -version } else { Write-Warn "java not found in PATH. Restart your terminal." }

    Write-Info "Verify Maven..."
    if (Test-CommandExists "mvn") { mvn -version } else { Write-Warn "mvn not found in PATH. Restart your terminal." }

    Write-Info "Verify VS Code..."
    if (Test-CommandExists "code") { code --version } else { Write-Warn "code not found in PATH. Restart your terminal." }

    Write-Info "Verify IntelliJ IDEA..."
    Write-Warn "IntelliJ verification is manual. Launch it once to finish first-run setup."
}

# ============================================================
# Main script execution
# ============================================================
Write-Step "Starting minimal Windows developer environment setup..."

# Determine modes early so banner can display them
$useInteractive = $false
$useSilent = $true
if ($Interactive) {
    $useInteractive = $true
    $useSilent = $false
} elseif ($Silent) {
    $useInteractive = $false
    $useSilent = $true
}

# Print a short banner/help at top that prints accepted switches, defaults, and chosen mode
Write-Host "===> setup_env_min.ps1 - Minimal Windows bootstrap" -ForegroundColor Cyan
Write-Host "===> Accepted switches: -DryRun (preview), -Interactive (installer UX), -Silent (no prompts), -Help (this message)." -ForegroundColor Cyan
Write-Host "===> Default behavior: Silent installs (no prompts)." -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "===> Mode: DryRun (no changes will be made)." -ForegroundColor Yellow
} elseif ($useInteractive) {
    Write-Host "===> Mode: Interactive (installer UX will be shown)." -ForegroundColor Yellow
} else {
    Write-Host "===> Mode: Silent (default)." -ForegroundColor Yellow
}

# Print PATH before installation for quick verification
Print-PathEntries -Scope "Session"
Print-PathEntries -Scope "Machine"
Print-PathEntries -Scope "User"

if ($Help) {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Usage: .\scripts\windows\setup_env_min.ps1 [ -DryRun ] [ -Interactive ] [ -Silent ] [ -Help ]" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\scripts\windows\setup_env_min.ps1            # Silent (default)" -ForegroundColor Cyan
    Write-Host "  .\scripts\windows\setup_env_min.ps1 -Interactive  # Show installer UX" -ForegroundColor Cyan
    Write-Host "  .\scripts\windows\setup_env_min.ps1 -DryRun       # Preview actions, no changes" -ForegroundColor Cyan
    exit 0
}

Assert-Winget

Write-Info "Updating winget sources..."
if (-not $DryRun -and $script:WingetExe) {
    & $script:WingetExe source update
} else {
    Write-Info "DryRun/No winget: skipping winget source update"
}

Write-Step "Installing required tools..."
Install-WingetApp -Id "Git.Git" -Description "Git for Windows" -SkipCommand "git" -UseInteractive:$useInteractive -NoSilent:$(! $useSilent)

if (Test-CommandExists "java") {
    Write-Warn "java already available. Skipping JDK install."
} else {
    Install-WingetApp -Id "Microsoft.OpenJDK.17" -Description "Microsoft OpenJDK 17" -UseInteractive:$useInteractive -NoSilent:$(! $useSilent)
}

if (Test-CommandExists "code") {
    Write-Warn "code already available. Skipping Visual Studio Code install."
} else {
    Install-WingetApp -Id "Microsoft.VisualStudioCode" -Description "Visual Studio Code" -UseInteractive:$useInteractive -NoSilent:$(! $useSilent)
}

if (Test-IntelliJInstalled) {
    Write-Warn "IntelliJ IDEA Community already installed. Skipping install."
} else {
    Install-WingetApp -Id "JetBrains.IntelliJIDEA.Community" -Description "IntelliJ IDEA Community" -UseInteractive:$useInteractive -NoSilent:$(! $useSilent)
}

Refresh-SessionPath

Install-Maven

Refresh-SessionPath

Set-JavaHome

# Rebuild session path after JAVA_HOME changes and print PATH after installation
Refresh-SessionPath
Print-PathEntries -Scope "Session"
Print-PathEntries -Scope "User"

Invoke-Verify

Write-Host "`n`nAwesome, all set!" -ForegroundColor Green

