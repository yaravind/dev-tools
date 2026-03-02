# run_tests.ps1 - Dry-run validation for Windows scripts
#
# Usage (PowerShell):
#   .\scripts\windows\run_tests.ps1

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

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$resolvedRoot = Resolve-Path (Join-Path $scriptDir "..\..") -ErrorAction SilentlyContinue
if ($resolvedRoot) {
    $repoRoot = $resolvedRoot.Path
} else {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

Write-Step "Starting Windows script dry-run checks"

$scripts = @(
    "gen_taskbar_apps.ps1",
    "setup_env.ps1",
    "setup_env_min.ps1",
    "setup_env_min_rollback.ps1",
    "jenv_setup.ps1",
    "maven_setup.ps1",
    "taskbar_setup.ps1",
    "vscode_setup.ps1",
    "run_taskbar_setup.ps1",
    "run_vscode_setup.ps1"
)

foreach ($script in $scripts) {
    $path = Join-Path $scriptDir $script
    if (-not (Test-Path $path)) {
        Write-Warn "Missing script: $path"
        continue
    }
    try {
        [ScriptBlock]::Create((Get-Content -Raw $path)) | Out-Null
        Write-Ok "Syntax OK: $script"
    } catch {
        Write-Warn "Syntax FAILED: $script - $_"
    }
}

# Dry-run execution for safe scripts
try {
    if (-not $IsWindows) {
        Write-Warn "Skipping taskbar_setup.ps1 DryRun on non-Windows host."
    } else {
        $configPath = Join-Path $repoRoot "config"
        $configPath = Join-Path $configPath "taskbar_apps.txt"
        if ([string]::IsNullOrWhiteSpace($configPath)) {
            Write-Warn "Config path is empty for taskbar_setup.ps1"
        } elseif (Test-Path $configPath) {
            Write-Info "DryRun: taskbar_setup.ps1"
            & (Join-Path $scriptDir "taskbar_setup.ps1") -DryRun -Yes -ConfigPath $configPath | Out-Null
            Write-Ok "DryRun OK: taskbar_setup.ps1"
        } else {
            Write-Warn "Config missing for taskbar_setup.ps1: $configPath"
        }
    }
} catch {
    Write-Warn "DryRun FAILED: taskbar_setup.ps1 - $_"
}

try {
    $configPath = Join-Path $repoRoot "config"
    $configPath = Join-Path $configPath "vscode.txt"
    if ([string]::IsNullOrWhiteSpace($configPath)) {
        Write-Warn "Config path is empty for vscode_setup.ps1"
    } elseif (Test-Path $configPath) {
        Write-Info "DryRun: vscode_setup.ps1"
        & (Join-Path $scriptDir "vscode_setup.ps1") -DryRun -Yes -ConfigPath $configPath | Out-Null
        Write-Ok "DryRun OK: vscode_setup.ps1"
    } else {
        Write-Warn "Config missing for vscode_setup.ps1: $configPath"
    }
} catch {
    Write-Warn "DryRun FAILED: vscode_setup.ps1 - $_"
}

Write-Step "Windows dry-run checks complete"
