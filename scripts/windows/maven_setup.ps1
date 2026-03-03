# maven_setup.ps1 - Install Apache Maven without winget
#
# Usage (PowerShell as Administrator recommended):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\maven_setup.ps1

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

function Ensure-PathContains {
    param(
        [string]$CurrentPath,
        [string]$Entry
    )
    if ($CurrentPath -notlike "*$Entry*") {
        return "$CurrentPath;$Entry"
    }
    return $CurrentPath
}

Write-Step "Installing Apache Maven..."

$version = "3.9.11"
$installRoot = Join-Path $env:LOCALAPPDATA "Programs\Apache"
$mavenDir = Join-Path $installRoot "apache-maven-$version"
$mavenBin = Join-Path $mavenDir "bin"
$downloadUrls = @(
    "https://dlcdn.apache.org/maven/maven-3/$version/binaries/apache-maven-$version-bin.zip",
    "https://archive.apache.org/dist/maven/maven-3/$version/binaries/apache-maven-$version-bin.zip"
)

$existingMavenHome = [Environment]::GetEnvironmentVariable("MAVEN_HOME", "User")
if (Test-CommandExists "mvn") {
    if ($existingMavenHome -and (Test-Path $existingMavenHome)) {
        $existingBin = Join-Path $existingMavenHome "bin"
        Write-Warn "mvn is already available - skipping download."
        Write-Info "Ensuring PATH contains $existingBin"
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not $userPath) { $userPath = "" }
        $userPath = Ensure-PathContains -CurrentPath $userPath -Entry $existingBin
        [Environment]::SetEnvironmentVariable("Path", $userPath, "User")
        Write-Warn "Restart your terminal to apply PATH changes."
        exit 0
    }
}

if (-not (Test-Path $mavenDir)) {
    Write-Info "Downloading Maven $version..."
    if (-not (Test-Path $installRoot)) {
        New-Item -ItemType Directory -Path $installRoot | Out-Null
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $zipPath = Join-Path $env:TEMP "apache-maven-$version-bin.zip"
    $downloaded = $false

    foreach ($url in $downloadUrls) {
        try {
            Write-Info "Fetching: $url"
            Invoke-WebRequest -Uri $url -OutFile $zipPath -ErrorAction Stop
            $downloaded = $true
            break
        } catch {
            Write-Warn "Download failed: $url"
        }
    }

    if (-not $downloaded) {
        Write-Host "ERROR: Could not download Maven $version from Apache mirrors." -ForegroundColor Red
        Write-Host "ERROR: Check network access or update the version in scripts/maven_setup.ps1." -ForegroundColor Red
        exit 1
    }

    Write-Info "Extracting Maven..."
    Expand-Archive -Path $zipPath -DestinationPath $installRoot -Force

    Remove-Item $zipPath -Force
    Write-Ok "Maven extracted to $mavenDir"
} else {
    Write-Warn "Maven directory already exists at $mavenDir - skipping download."
}

Write-Info "Setting MAVEN_HOME and PATH..."
[Environment]::SetEnvironmentVariable("MAVEN_HOME", $mavenDir, "User")
[Environment]::SetEnvironmentVariable("M2_HOME", $mavenDir, "User")

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }
$userPath = Ensure-PathContains -CurrentPath $userPath -Entry $mavenBin
[Environment]::SetEnvironmentVariable("Path", $userPath, "User")

Write-Ok "MAVEN_HOME set to $mavenDir"
Write-Warn "Restart your terminal to apply PATH changes."
