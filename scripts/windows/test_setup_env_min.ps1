# test_setup_env_min.ps1 - Lightweight harness that runs setup_env_min.ps1 in DryRun and reports result

param(
    [switch]$VerboseOutput
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$minScript = Join-Path $scriptDir "setup_env_min.ps1"

if (-not (Test-Path $minScript)) {
    Write-Warn "Missing: $minScript"
    exit 2
}

Write-Step "DryRun: setup_env_min.ps1 (via test harness)"
try {
    $proc = Start-Process -FilePath pwsh -ArgumentList @('-NoProfile','-NonInteractive','-Command',"& '$minScript' -DryRun") -NoNewWindow -PassThru -Wait -ErrorAction Stop
    $exit = $proc.ExitCode
    if ($exit -eq 0) {
        Write-Ok "DryRun OK: $(Split-Path -Leaf $minScript)"
        exit 0
    } else {
        Write-Warn "DryRun FAILED: $(Split-Path -Leaf $minScript) - Exit code: $exit"
        exit $exit
    }
} catch {
    Write-Warn "DryRun FAILED: $(Split-Path -Leaf $minScript) - Exception: $_"
    exit 1
}
