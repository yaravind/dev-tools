# backup_codex.ps1 - Back up local Codex data
#
# Usage:
#   .\scripts\windows\backup_codex.ps1 C:\Backups\codex
#   .\scripts\windows\backup_codex.ps1 C:\Backups\codex -DryRun

# Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$TargetDir,

    [string]$SourceDir = (Join-Path $HOME ".codex"),

    [switch]$DryRun
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$start = Get-Date
$script:Copied = 0
$script:Failed = 0

function Format-Duration {
    param([TimeSpan]$Duration)
    return ("{0:00}:{1:00}:{2:00}" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds)
}

Write-Step "Codex backup"
Write-Info "Source: $SourceDir"
Write-Info "Target: $TargetDir"

if (-not (Test-Path -LiteralPath $SourceDir)) {
    if ($DryRun) {
        Write-Warn "DryRun: source directory not found on this host: $SourceDir"
    } else {
        Write-EbkError "Source directory not found: $SourceDir"
        exit 1
    }
}

if ($DryRun) {
    Write-Info "DryRun: would create target directory and copy all Codex data."
} else {
    try {
        New-Item -ItemType Directory -Path $TargetDir -Force -ErrorAction Stop | Out-Null
        Get-ChildItem -LiteralPath $SourceDir -Force -ErrorAction Stop | ForEach-Object {
            $target = Join-Path $TargetDir $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force -ErrorAction Stop
            $script:Copied++
        }
    } catch {
        $script:Failed++
        Write-EbkError "Something went wrong during the copy process. $_"
    }
}

Write-Step "SUMMARY"
Write-Host ""
Write-Host "Final Status Report" -ForegroundColor $script:EbPhase
Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
Write-Host ("  {0,-24} {1}" -f "Script", "Codex Backup (Windows)")
Write-Host ("  {0,-24} {1}" -f "Source", $SourceDir)
Write-Host ("  {0,-24} {1}" -f "Target", $TargetDir)
Write-Host ("  {0,-24} {1}" -f "Status", $(if ($script:Failed -eq 0) { if ($DryRun) { "DRY RUN" } else { "SUCCESS" } } else { "FAILED" }))
Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
Write-Host ("  {0,-24} {1}" -f "Top-level items copied", $script:Copied)
Write-Host ("  {0,-24} {1}" -f "Failed items", $script:Failed)
Write-Host ("  {0,-24} {1}" -f "Duration", (Format-Duration -Duration ((Get-Date) - $start)))
Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase

if ($script:Failed -gt 0) {
    exit 1
}

Write-Ok "Codex backup complete."
