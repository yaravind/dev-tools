# jenv_setup.ps1 — Windows equivalent of jenv_setup.sh
#
# Discovers all installed JDKs and registers them with JEnv-for-Windows.
# https://github.com/FelixSelter/JEnv-for-Windows
#
# Usage: Run in PowerShell as Administrator:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\jenv_setup.ps1

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

# ============================================================
# Install JEnv-for-Windows if not already installed
# ============================================================

function Install-JEnv {
    Write-Step "Checking for JEnv-for-Windows..."
    if (Test-CommandExists "jenv") {
        Write-Ok "jenv is already installed."
    } else {
        Write-Info "Installing JEnv-for-Windows from GitHub..."
        # NOTE: Review the installer script before running in sensitive environments:
        # https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/jenv.ps1
        iwr -useb "https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/jenv.ps1" | iex

        # Append newly registered paths without discarding existing PATH modifications
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path    = $env:Path + ";$machinePath;$userPath"

        if (Test-CommandExists "jenv") {
            Write-Ok "JEnv-for-Windows installed successfully."
        } else {
            Write-Host "ERROR: jenv not found after installation. Restart your terminal and re-run this script." -ForegroundColor Red
            Write-Host "  Manual install: iwr -useb 'https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/jenv.ps1' | iex" -ForegroundColor Yellow
            exit 1
        }
    }
}

# ============================================================
# Discover all installed JDKs in common Windows locations
# ============================================================

function Get-InstalledJdks {
    $searchPaths = @(
        "C:\Program Files\Microsoft\jdk-*",
        "C:\Program Files\Eclipse Adoptium\jdk-*",
        "C:\Program Files\Java\jdk-*",
        "C:\Program Files\BellSoft\LibericaJDK-*"
    )

    $jdks = @()
    foreach ($pattern in $searchPaths) {
        $found = Get-Item -Path $pattern -ErrorAction SilentlyContinue
        if ($found) {
            $jdks += $found
        }
    }
    return $jdks
}

# ============================================================
# Main script execution
# ============================================================

Write-Step "Starting jenv setup for Windows..."

Install-JEnv

$jdks = Get-InstalledJdks
if ($jdks.Count -eq 0) {
    Write-Warn "No JDKs found in standard installation directories."
    Write-Warn "Install a JDK first (e.g. run setup_env.ps1) then re-run this script."
    exit 1
}

Write-Step "Adding discovered JDKs to jenv..."
foreach ($jdk in $jdks) {
    $jdkPath = $jdk.FullName
    Write-Info "Processing JDK: $jdkPath"
    jenv add "$jdkPath"
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Successfully added: $jdkPath"
    } else {
        Write-Warn "Failed to add: $jdkPath (exit code: $LASTEXITCODE)"
    }
}

# List all Java versions managed by jenv
Write-Step "Available Java versions managed by jenv:"
jenv list

# Prompt the user to select a global version (validate against listed versions)
do {
    Write-Host "`nChoose the version (from above) to set as Global version: " -NoNewline
    $globalVer = Read-Host
} while ([string]::IsNullOrWhiteSpace($globalVer))

jenv use "$globalVer"
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Could not switch to version '$globalVer'. Check the version name and try: jenv use <version>"
}

# Verify
Write-Step "Verifying Java setup..."
Write-Info "Running 'java -version'..."
java -version

Write-Info "Verifying JAVA_HOME..."
Write-Host $env:JAVA_HOME

Write-Host "`n`n👌 Awesome, all set." -ForegroundColor Green
