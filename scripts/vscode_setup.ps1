# vscode_setup.ps1 - Install VS Code extensions from config on Windows
#
# Usage (run as Administrator):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\vscode_setup.ps1
#   .\scripts\vscode_setup.ps1 -Yes
#   .\scripts\vscode_setup.ps1 -DryRun
#   .\scripts\vscode_setup.ps1 -WhatIf

param(
    [string]$ConfigPath,
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
    Write-Host "===> $Message" -ForegroundColor Yellow
}

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
    foreach ($line in Get-Content -Path $Path -ErrorAction Stop) {
        if (Is-CommentOrEmpty -Line $line) { continue }
        $ext = $line.Trim()
        if ($ext) { $extensions.Add($ext) }
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

        Write-Host "ERROR: VS Code CLI 'code' not found. Install VS Code and enable the 'code' command." -ForegroundColor Red
        exit 1
    }

    return @(code --list-extensions)
}

function Print-Extensions {
    param(
        [string]$Title,
        [System.Collections.IEnumerable]$Items
    )

    Write-Step $Title
    foreach ($item in $Items) {
        Write-Info $item
    }
}

$scriptDir = Resolve-ScriptDir
if (-not $scriptDir) {
    Write-Host "ERROR: Could not resolve script directory." -ForegroundColor Red
    exit 1
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $scriptDir ".."
    $ConfigPath = Join-Path $ConfigPath "config"
    $ConfigPath = Join-Path $ConfigPath "vscode.txt"
}

$resolvedConfig = Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue
if ($resolvedConfig) {
    $ConfigPath = $resolvedConfig.Path
} elseif (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "ERROR: Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

Write-Step "Starting VS Code extension setup (Windows)"
Write-Info "Config file: $ConfigPath"

$installedList = Get-InstalledExtensions -SkipCodeCheck:$DryRun
$installedSet = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
foreach ($ext in $installedList) {
    if ($ext) { [void]$installedSet.Add($ext) }
}

$desired = Get-ConfigExtensions -Path $ConfigPath
Print-Extensions -Title "Extensions from config" -Items $desired
Write-Info ("Total extensions found: {0}" -f $desired.Count)

if (-not $Yes) {
    $proceed = Read-Host "Proceed with installation? (y/n)"
    if ($proceed -notmatch "^[yY]$") {
        Write-Warn "Aborted by user. No changes made."
        exit 0
    }
}

$installed = 0
$skipped = 0
$failed = 0

foreach ($ext in $desired) {
    if ($installedSet.Contains($ext)) {
        Write-Warn "Extension already installed: $ext"
        $skipped++
        continue
    }

    if ($DryRun) {
        Write-Info "DryRun: would install extension: $ext"
        $skipped++
        continue
    }

    Write-Info "Installing extension: $ext"
    code --install-extension $ext
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Installed: $ext"
        $installed++
        [void]$installedSet.Add($ext)
    } else {
        Write-Warn "Failed to install: $ext"
        $failed++
    }
}

Write-Step "VS Code extension installation complete"
Write-Ok ("Installed: {0}" -f $installed)
Write-Warn ("Skipped: {0}" -f $skipped)
Write-Warn ("Failed: {0}" -f $failed)
