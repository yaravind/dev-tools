# clone_github_repos.ps1 - Clone GitHub repositories listed as org/repo-name
#
# Usage:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\windows\clone_github_repos.ps1
#   .\scripts\windows\clone_github_repos.ps1 repos.txt
#   .\scripts\windows\clone_github_repos.ps1 repos.txt C:\Developer
#   Get-Content repos.txt | .\scripts\windows\clone_github_repos.ps1 -
#   .\scripts\windows\clone_github_repos.ps1 -DryRun

# Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RepoListPath,

    [Parameter(Position = 1)]
    [string]$DestinationDir = ".",

    [switch]$DryRun
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$script:ScriptStart = Get-Date
$script:Total = 0
$script:Cloned = 0
$script:Skipped = 0
$script:Failed = 0
$script:Invalid = 0

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

function Resolve-RepoRoot {
    param([string]$ScriptDir)

    $resolved = Resolve-Path (Join-Path $ScriptDir "..\..") -ErrorAction SilentlyContinue
    if ($resolved) {
        return $resolved.Path
    }
    return (Split-Path -Parent (Split-Path -Parent $ScriptDir))
}

function Trim-RepoLine {
    param([string]$Line)

    if ($null -eq $Line) {
        return ""
    }

    $withoutComment = ($Line -split "#", 2)[0]
    return $withoutComment.Trim()
}

function Format-Duration {
    param([TimeSpan]$Duration)

    if ($Duration.TotalHours -ge 1) {
        return ("{0}h {1}m {2}s" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds)
    }
    if ($Duration.TotalMinutes -ge 1) {
        return ("{0}m {1}s" -f [int]$Duration.TotalMinutes, $Duration.Seconds)
    }
    return ("{0}s" -f [int]$Duration.TotalSeconds)
}

function Print-StructuredReport {
    param([string]$StatusLabel)

    Write-Host ""
    Write-Host "Final Status Report" -ForegroundColor $script:EbPhase
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
    Write-Host ("  {0,-24} {1}" -f "Script", "Clone GitHub Repositories (Windows)")
    Write-Host ("  {0,-24} {1}" -f "Repo source", $RepoListPath)
    Write-Host ("  {0,-24} {1}" -f "Destination", $DestinationDir)
    Write-Host ("  {0,-24} {1}" -f "Status", $StatusLabel)
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
    Write-Host ("  {0,-24} {1}" -f "Total entries", $script:Total)
    Write-Host ("  {0,-24} {1}" -f "Cloned", $script:Cloned)
    Write-Host ("  {0,-24} {1}" -f "Skipped existing", $script:Skipped)
    Write-Host ("  {0,-24} {1}" -f "Failed clones", $script:Failed)
    Write-Host ("  {0,-24} {1}" -f "Invalid entries", $script:Invalid)
    Write-Host ("  {0,-24} {1}" -f "Duration", (Format-Duration -Duration ((Get-Date) - $script:ScriptStart)))
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
}

function Invoke-CloneRepo {
    param([string]$Line)

    $repo = Trim-RepoLine -Line $Line
    if ([string]::IsNullOrWhiteSpace($repo)) {
        return
    }

    $script:Total++

    if ($repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        Write-EbkError "Invalid repo entry, expected org/repo-name: $repo"
        $script:Invalid++
        return
    }

    $repoName = ($repo -split "/", 2)[1]
    $clonePath = Join-Path $DestinationDir $repoName

    if (Test-Path -LiteralPath $clonePath) {
        Write-Warn "Skipping ${repo}: $clonePath already exists."
        $script:Skipped++
        return
    }

    if ($DryRun) {
        Write-Info "DryRun: would clone $repo into $clonePath."
        $script:Skipped++
        return
    }

    Write-Info "Cloning $repo into $clonePath..."
    $output = & git clone "https://github.com/$repo.git" "$clonePath" 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($output) { $output | ForEach-Object { Write-Host $_ } }
        Write-Ok "Cloned $repo."
        $script:Cloned++
    } else {
        if ($output) { $output | ForEach-Object { Write-Host $_ } }
        Write-EbkError "Failed to clone $repo."
        $script:Failed++
    }
}

$scriptDir = Resolve-ScriptDir
if (-not $scriptDir) {
    Write-EbkError "Could not resolve script directory."
    exit 1
}

$repoRoot = Resolve-RepoRoot -ScriptDir $scriptDir
if (-not $RepoListPath) {
    $RepoListPath = Join-Path $repoRoot "config\github-repos.txt"
}

if ($RepoListPath -ne "-") {
    $resolvedRepoList = Resolve-Path -Path $RepoListPath -ErrorAction SilentlyContinue
    if ($resolvedRepoList) {
        $RepoListPath = $resolvedRepoList.Path
    } elseif (-not (Test-Path -LiteralPath $RepoListPath)) {
        Write-EbkError "Repo list file not found: $RepoListPath"
        exit 1
    }
}

if (-not (Test-CommandExists "git")) {
    if ($DryRun) {
        Write-Warn "DryRun: git is not installed or is not in PATH; clone commands will only be previewed."
    } else {
        Write-EbkError "git is not installed or is not in PATH."
        exit 1
    }
}

if (-not $DryRun -and -not (Test-Path -LiteralPath $DestinationDir)) {
    New-Item -ItemType Directory -Path $DestinationDir -Force -ErrorAction Stop | Out-Null
}

Write-Step "DISCOVER"
if ($RepoListPath -eq "-") {
    Write-Info "Repo list: stdin"
} else {
    Write-Info "Repo list: $RepoListPath"
}
Write-Info "Destination: $DestinationDir"

Write-Step "EXECUTE"
if ($RepoListPath -eq "-") {
    $lines = @($input)
} else {
    $lines = @(Get-Content -Path $RepoListPath -ErrorAction Stop)
}
foreach ($line in $lines) {
    Invoke-CloneRepo -Line $line
}

Write-Step "SUMMARY"
$finalStatus = "SUCCESS"
if ($script:Failed -gt 0 -or $script:Invalid -gt 0) {
    $finalStatus = "FAILED"
} elseif ($script:Cloned -eq 0 -and $script:Skipped -gt 0) {
    $finalStatus = "NO CHANGES"
}

Print-StructuredReport -StatusLabel $finalStatus

if ($script:Failed -gt 0 -or $script:Invalid -gt 0) {
    exit 1
}
