# restore_codex.ps1 - Restore a full Codex backup into the local Codex directory
#
# Usage:
#   .\scripts\windows\restore_codex.ps1 C:\Backups\codex
#   .\scripts\windows\restore_codex.ps1 C:\Backups\codex -DryRun
#   .\scripts\windows\restore_codex.ps1 C:\Backups\codex -Yes

# Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$SourceDir,

    [string]$TargetDir = (Join-Path $HOME ".codex"),

    [switch]$Yes,
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
$backupRoot = Join-Path $HOME ".codex-restore-backups"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safetyBackup = Join-Path $backupRoot "codex-before-restore-$timestamp"

function Format-Duration {
    param([TimeSpan]$Duration)
    return ("{0:00}:{1:00}:{2:00}" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds)
}

function Test-CodexBackupShape {
    param([string]$Path)
    return ((Test-Path -LiteralPath (Join-Path $Path "sessions")) -or
        (Test-Path -LiteralPath (Join-Path $Path "archived_sessions")))
}

function Rollback-Restore {
    Write-Warn "Restore failed. Rolling back to the original Codex directory..."
    Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $safetyBackup) {
        Move-Item -LiteralPath $safetyBackup -Destination $TargetDir -ErrorAction Stop
        Write-Ok "Rollback completed successfully."
    } else {
        Write-Warn "No original Codex directory existed; partial target was removed."
    }
}

$resolvedSource = Resolve-Path -Path $SourceDir -ErrorAction SilentlyContinue
if ($resolvedSource) {
    $SourceDir = $resolvedSource.Path
}

Write-Step "Codex full restore"
Write-Info "Source: $SourceDir"
Write-Info "Target: $TargetDir"
Write-Warn "Completely quit the Codex app before restoring. Copying live SQLite files can create an inconsistent restore."

if (-not (Test-Path -LiteralPath $SourceDir)) {
    if ($DryRun) {
        Write-Warn "DryRun: backup source directory not found on this host: $SourceDir"
    } else {
        Write-EbkError "Backup source directory not found: $SourceDir"
        exit 1
    }
} elseif (-not (Test-CodexBackupShape -Path $SourceDir)) {
    if ($DryRun) {
        Write-Warn "DryRun: source does not look like a Codex backup; no sessions directories found."
    } else {
        Write-EbkError "The folder does not look like a Codex backup; no sessions directories found."
        exit 1
    }
}

if ($SourceDir -eq $TargetDir) {
    Write-EbkError "Source and target directories are the same."
    exit 1
}

if ($DryRun) {
    Write-Info "DryRun: would move existing target to safety backup: $safetyBackup"
    Write-Info "DryRun: would copy all top-level backup items into target."
} else {
    if (-not $Yes) {
        $response = Read-Host "Replace $TargetDir with this backup? (y/N)"
        if ($response -notmatch '^[Yy]$') {
            Write-Warn "Restore canceled."
            exit 0
        }
    }

    try {
        if (Test-Path -LiteralPath $TargetDir) {
            New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null
            Write-Info "Moving existing Codex directory to safety backup: $safetyBackup"
            Move-Item -LiteralPath $TargetDir -Destination $safetyBackup -ErrorAction Stop
        }

        New-Item -ItemType Directory -Path $TargetDir -Force -ErrorAction Stop | Out-Null

        Get-ChildItem -LiteralPath $SourceDir -Force -ErrorAction Stop | ForEach-Object {
            $destination = Join-Path $TargetDir $_.Name
            Write-Info "Copying $($_.Name)"
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
            $script:Copied++
        }
    } catch {
        $script:Failed++
        Write-EbkError "Restore copy failed. $_"
        try {
            Rollback-Restore
        } catch {
            Write-EbkError "Automatic rollback failed. Original data remains at: $safetyBackup"
        }
    }
}

Write-Step "SUMMARY"
Write-Host ""
Write-Host "Final Status Report" -ForegroundColor $script:EbPhase
Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
Write-Host ("  {0,-24} {1}" -f "Script", "Codex Restore (Windows)")
Write-Host ("  {0,-24} {1}" -f "Source", $SourceDir)
Write-Host ("  {0,-24} {1}" -f "Target", $TargetDir)
Write-Host ("  {0,-24} {1}" -f "Status", $(if ($script:Failed -eq 0) { if ($DryRun) { "DRY RUN" } else { "SUCCESS" } } else { "FAILED" }))
Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
Write-Host ("  {0,-24} {1}" -f "Top-level items copied", $script:Copied)
Write-Host ("  {0,-24} {1}" -f "Failed items", $script:Failed)
Write-Host ("  {0,-24} {1}" -f "Safety backup", $(if (Test-Path -LiteralPath $safetyBackup) { $safetyBackup } else { "not created" }))
Write-Host ("  {0,-24} {1}" -f "Duration", (Format-Duration -Duration ((Get-Date) - $start)))
Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase

if ($script:Failed -gt 0) {
    exit 1
}

Write-Ok "Codex restore complete."
