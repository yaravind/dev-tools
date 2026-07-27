# verify_codex_restore.ps1 - Read-only diagnostics for restored Codex data on Windows
#
# Usage:
#   .\scripts\windows\verify_codex_restore.ps1
#   .\scripts\windows\verify_codex_restore.ps1 -AllowMissing

# Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$CodexDir = (Join-Path $HOME ".codex"),
    [switch]$AllowMissing
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$script:Pass = 0
$script:Warn = 0
$script:Fail = 0
$script:Issues = New-Object System.Collections.Generic.List[string]

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==== $Title ====" -ForegroundColor $script:EbPhase
}

function Add-Pass {
    param([string]$Message)
    $script:Pass++
    Write-Ok $Message
}

function Add-Warn {
    param([string]$Message)
    $script:Warn++
    [void]$script:Issues.Add("WARNING: $Message")
    Write-Warn $Message
}

function Add-Fail {
    param([string]$Message)
    $script:Fail++
    [void]$script:Issues.Add("FAILURE: $Message")
    Write-EbkError $Message
}

function Get-KnownCodexLocations {
    $locations = New-Object System.Collections.Generic.List[string]
    [void]$locations.Add((Join-Path $HOME ".codex"))
    [void]$locations.Add((Join-Path $HOME "Developer\.codex"))
    [void]$locations.Add((Join-Path $HOME "Documents\.codex"))
    [void]$locations.Add((Join-Path $HOME "Documents\Codex\.codex"))

    foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA)) {
        if ($base) {
            [void]$locations.Add((Join-Path $base "Codex\.codex"))
            [void]$locations.Add((Join-Path $base "ChatGPT\.codex"))
            [void]$locations.Add((Join-Path $base "OpenAI\.codex"))
        }
    }
    return @($locations)
}

function Get-AppProfileLocations {
    $locations = New-Object System.Collections.Generic.List[string]
    foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA)) {
        if ($base) {
            [void]$locations.Add((Join-Path $base "Codex"))
            [void]$locations.Add((Join-Path $base "ChatGPT"))
            [void]$locations.Add((Join-Path $base "OpenAI"))
        }
    }
    if ($env:LOCALAPPDATA) {
        [void]$locations.Add((Join-Path $env:LOCALAPPDATA "Packages"))
    }
    return @($locations)
}

function Get-DirectorySizeBytes {
    param([string]$Path)
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return [int64]$sum
}

Write-Section "Locations to check"
$codexLocations = Get-KnownCodexLocations
foreach ($location in $codexLocations) {
    Write-Host " * $location"
}

Write-Section "App profile/cache locations to check"
$appProfileLocations = Get-AppProfileLocations
foreach ($location in $appProfileLocations) {
    Write-Host " * $location"
}

Write-Section "1. Verify .codex"
if (Test-Path -LiteralPath $CodexDir) {
    Add-Pass "Found $CodexDir"
} else {
    if ($AllowMissing) {
        Add-Warn "$CodexDir not found"
        Write-Section "Summary"
        Write-Host ("PASS={0} WARN={1} FAIL={2}" -f $script:Pass, $script:Warn, $script:Fail)
        exit 0
    }
    Add-Fail "$CodexDir not found"
    Write-Section "Summary"
    Write-Host ("PASS={0} WARN={1} FAIL={2}" -f $script:Pass, $script:Warn, $script:Fail)
    exit 1
}

Write-Section "2. Key files"
foreach ($item in @("sessions", "archived_sessions", "session_index.jsonl", "history.jsonl", "logs_2.sqlite", "state_5.sqlite", "memories_1.sqlite", "goals_1.sqlite")) {
    $path = Join-Path $CodexDir $item
    if (Test-Path -LiteralPath $path) {
        Add-Pass "$item exists"
    } else {
        Add-Warn "$item missing"
    }
}

Write-Section "3. Session index"
$sessionIndex = Join-Path $CodexDir "session_index.jsonl"
if (Test-Path -LiteralPath $sessionIndex) {
    $lineCount = (Get-Content -Path $sessionIndex -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Info "Lines: $lineCount"
    if ($lineCount -gt 0) {
        Add-Pass "Session index populated"
    } else {
        Add-Fail "Session index empty"
    }
    Get-Content -Path $sessionIndex -TotalCount 3 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
}

Write-Section "4. Sessions"
$sessionsDir = Join-Path $CodexDir "sessions"
if (Test-Path -LiteralPath $sessionsDir) {
    $sessionFiles = @(Get-ChildItem -LiteralPath $sessionsDir -Recurse -File -Force -ErrorAction SilentlyContinue)
    Write-Info ("Files: {0} Size: {1} bytes" -f $sessionFiles.Count, (Get-DirectorySizeBytes -Path $sessionsDir))
    if ($sessionFiles.Count -gt 0) {
        Add-Pass "Session files found"
    } else {
        Add-Warn "No session files"
    }
    $sessionFiles | Select-Object -First 5 | ForEach-Object { Write-Host $_.FullName }
}

Write-Section "5. Archived sessions"
$archivedDir = Join-Path $CodexDir "archived_sessions"
if (Test-Path -LiteralPath $archivedDir) {
    $archivedFiles = @(Get-ChildItem -LiteralPath $archivedDir -Recurse -File -Force -ErrorAction SilentlyContinue)
    Write-Info ("Files: {0} Size: {1} bytes" -f $archivedFiles.Count, (Get-DirectorySizeBytes -Path $archivedDir))
    if ($archivedFiles.Count -gt 0) {
        Add-Pass "Archived sessions found"
    } else {
        Add-Warn "No archived sessions"
    }
}

Write-Section "6. Other .codex dirs"
$foundCodex = $false
foreach ($location in $codexLocations) {
    if (Test-Path -LiteralPath $location) {
        Write-Info "Found $location"
        $foundCodex = $true
    }
}
if (-not $foundCodex) {
    Add-Warn "No .codex directories found in known Windows locations"
}

Write-Section "7. SQLite"
if (Get-Command sqlite3 -ErrorAction SilentlyContinue) {
    foreach ($db in @("logs_2.sqlite", "state_5.sqlite", "memories_1.sqlite", "goals_1.sqlite")) {
        $dbPath = Join-Path $CodexDir $db
        if (Test-Path -LiteralPath $dbPath) {
            $result = sqlite3 "$dbPath" "pragma integrity_check;" 2>$null
            if ($result -match "ok") {
                Add-Pass "$db integrity OK"
            } else {
                Add-Warn "$db integrity could not be verified"
            }
        }
    }
} else {
    Add-Warn "sqlite3 not installed"
}

Write-Section "8. Codex or ChatGPT process"
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Codex|ChatGPT|OpenAI' })
if ($running.Count -gt 0) {
    Add-Warn "Codex/ChatGPT/OpenAI process appears to be running. Quit it before restore."
    $running | Select-Object ProcessName, Id | Format-Table | Out-String | Write-Host
} else {
    Add-Pass "Codex/ChatGPT/OpenAI process not detected"
}

Write-Section "9. App profile/cache sentinel"
if (Test-Path -LiteralPath $sessionIndex) {
    $firstLine = Get-Content -Path $sessionIndex -TotalCount 1 -ErrorAction SilentlyContinue
    $sentinelId = ""
    $sentinelTitle = ""
    try {
        $parsed = $firstLine | ConvertFrom-Json -ErrorAction Stop
        $sentinelId = $parsed.id
        $sentinelTitle = $parsed.thread_name
    } catch {
        Add-Warn "Could not parse first session_index.jsonl line as JSON"
    }

    if ($sentinelId) {
        Write-Info "Restored session sentinel id: $sentinelId"
        if ($sentinelTitle) { Write-Info "Restored session sentinel title: $sentinelTitle" }

        $foundProfile = $false
        $foundSentinel = $false
        foreach ($location in $appProfileLocations) {
            if (Test-Path -LiteralPath $location) {
                $foundProfile = $true
                Write-Info "Scanning $location"
                $matches = Get-ChildItem -LiteralPath $location -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Select-String -Pattern $sentinelId -SimpleMatch -ErrorAction SilentlyContinue
                if ($matches) {
                    Add-Pass "App profile references restored session id in $location"
                    $foundSentinel = $true
                    break
                }
            }
        }
        if (-not $foundProfile) { Add-Warn "No Codex/ChatGPT/OpenAI app profile/cache directories found" }
        if (-not $foundSentinel) { Add-Warn "Restored session sentinel was not found in app profile/cache locations" }
    } else {
        Add-Warn "Could not extract a restored session id from session_index.jsonl"
    }
} else {
    Add-Warn "Cannot check app profile/cache without session_index.jsonl"
}

Write-Section "Summary"
Write-Host ("PASS={0} WARN={1} FAIL={2}" -f $script:Pass, $script:Warn, $script:Fail)
if ($script:Fail -eq 0) {
    Write-Host ""
    Write-Host "Likely diagnosis:"
    Write-Host " * Restored data appears present in .codex."
    Write-Host " * If the UI index/cache sentinel warned, the app profile/cache has not visibly linked to a restored session."
    Write-Host " * In that case, do not repeat the .codex restore without first backing up app profile locations."
} else {
    $script:Issues | ForEach-Object { Write-Host $_ }
    exit 1
}
