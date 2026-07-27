# git_setup.ps1 - Configure Git identity, credential helper, and GitHub CLI auth on Windows
#
# Usage:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\windows\git_setup.ps1
#   .\scripts\windows\git_setup.ps1 -Action UpdateIdentity -Name "First Last" -Email "you@example.com"
#   .\scripts\windows\git_setup.ps1 -Action AddGitHubAccount
#   .\scripts\windows\git_setup.ps1 -DryRun -Yes

# Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet("Auto","Skip","UpdateIdentity","AddGitHubAccount")]
    [string]$Action = "Auto",

    [string]$Name,
    [string]$Email,

    [switch]$Yes,
    [switch]$DryRun
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$script:ScriptStart = Get-Date
$script:FailCount = 0
$script:ActionPerformed = 0
$script:SelectedAction = "none"

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Write-Indented {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    foreach ($line in ($Text -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Info ("  {0}" -f $line)
        }
    }
}

function Record-Failure {
    param([string]$Message)
    Write-EbkError $Message
    $script:FailCount++
}

function Get-GitGlobalValue {
    param([string]$Key)

    $value = git config --global --get $Key 2>$null
    if ($LASTEXITCODE -eq 0) {
        return ($value -join "`n")
    }
    return ""
}

function Get-GitCredentialHelpers {
    $helpers = git config --global --get-all credential.helper 2>$null
    if ($LASTEXITCODE -eq 0) {
        return @($helpers)
    }
    return @()
}

function Test-ExistingGitState {
    $currentName = Get-GitGlobalValue -Key "user.name"
    $currentEmail = Get-GitGlobalValue -Key "user.email"
    $helpers = Get-GitCredentialHelpers

    return (-not [string]::IsNullOrWhiteSpace($currentName) -or
        -not [string]::IsNullOrWhiteSpace($currentEmail) -or
        $helpers.Count -gt 0)
}

function Print-ExistingGitState {
    $currentName = Get-GitGlobalValue -Key "user.name"
    $currentEmail = Get-GitGlobalValue -Key "user.email"
    $helpers = Get-GitCredentialHelpers

    Write-Step "DISCOVER Reading existing Git and GitHub CLI configuration"
    Write-Info ("Global user.name: {0}" -f ($(if ($currentName) { $currentName } else { "not set" })))
    Write-Info ("Global user.email: {0}" -f ($(if ($currentEmail) { $currentEmail } else { "not set" })))

    if ($helpers.Count -eq 0) {
        Write-Info "Credential helpers: not set"
    } else {
        Write-Info "Credential helpers:"
        Write-Indented -Text ($helpers -join "`n")
    }

    Write-Step "DISCOVER Reading existing GitHub CLI authentication state"
    if (Test-CommandExists "gh") {
        $status = (& gh auth status 2>&1) -join "`n"
        if ([string]::IsNullOrWhiteSpace($status)) {
            Write-Warn "gh returned no account status."
        } else {
            Write-Indented -Text $status
        }
    } else {
        Write-Warn "gh is not installed or is not in PATH."
    }
}

function Read-RequiredValue {
    param(
        [string]$Prompt,
        [string]$CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue.Trim()
    }

    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
        Write-Warn "Value cannot be empty."
    }
}

function Read-EmailValue {
    param([string]$CurrentValue)

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        return $CurrentValue.Trim()
    }

    while ($true) {
        $value = Read-RequiredValue -Prompt "Type in your email address used for GitHub" -CurrentValue ""
        if ($value -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            return $value
        }
        Write-Warn "Email address does not look valid: $value"
    }
}

function Resolve-CredentialHelper {
    $helpers = Get-GitCredentialHelpers
    foreach ($helper in $helpers) {
        if ($helper -match '^(manager|manager-core)$') {
            return $helper
        }
    }
    return "manager"
}

function Configure-CredentialHelper {
    $targetHelper = Resolve-CredentialHelper
    $helpers = Get-GitCredentialHelpers

    if ($helpers -contains $targetHelper) {
        Write-Ok "credential.helper is already set to $targetHelper."
        return
    }

    if ($DryRun) {
        Write-Info "DryRun: would set credential.helper to $targetHelper."
        return
    }

    git config --global --replace-all credential.helper $targetHelper
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Set credential.helper to $targetHelper."
    } else {
        Record-Failure "Failed to set credential.helper to $targetHelper."
    }
}

function Update-GlobalGitIdentity {
    Write-Step "CONFIGURE Updating global Git identity and credential helper"

    if ($DryRun) {
        $dryName = if (-not [string]::IsNullOrWhiteSpace($Name)) { $Name.Trim() } else { "<your name>" }
        $dryEmail = if (-not [string]::IsNullOrWhiteSpace($Email)) { $Email.Trim() } else { "<your@email.com>" }
        Write-Info "DryRun: would set global user.name to $dryName."
        Write-Info "DryRun: would set global user.email to $dryEmail."
        Configure-CredentialHelper
        $script:ActionPerformed = 1
        $script:SelectedAction = "update-global-identity"
        return
    }

    $fullName = Read-RequiredValue -Prompt "Type in your first and last name (no accent or special characters)" -CurrentValue $Name
    $gitEmail = Read-EmailValue -CurrentValue $Email

    git config --global user.name "$fullName"
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Set global user.name to $fullName."
    } else {
        Record-Failure "Failed to set global user.name."
    }

    git config --global user.email "$gitEmail"
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Set global user.email to $gitEmail."
    } else {
        Record-Failure "Failed to set global user.email."
    }

    Configure-CredentialHelper
    $script:ActionPerformed = 1
    $script:SelectedAction = "update-global-identity"
}

function Add-GitHubAccount {
    Write-Step "CONFIGURE Adding a GitHub CLI account"

    if (-not (Test-CommandExists "gh")) {
        Record-Failure "gh is not installed or is not in PATH. Install GitHub CLI first, then rerun this option."
        return
    }

    if ($DryRun) {
        Write-Info "DryRun: would run gh auth login."
        $script:ActionPerformed = 1
        $script:SelectedAction = "add-gh-account"
        return
    }

    Write-Info "Starting gh auth login. Follow the GitHub CLI prompts to add an account."
    gh auth login
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "GitHub CLI account setup completed."
        $script:ActionPerformed = 1
        $script:SelectedAction = "add-gh-account"
    } else {
        Record-Failure "gh auth login failed or was canceled."
    }
}

function Print-NextSteps {
    Write-Step "NEXT STEPS"
    Write-Info "1. If Git prompts for GitHub credentials, use your GitHub username and a personal access token as the password."
    Write-Info "2. To generate a token, go to GitHub > Settings > Developer settings > Personal access tokens."
    Write-Info "3. Prefer a fine-grained token when you want to limit repository access or your organization requires it."
    Write-Info "4. Windows will store accepted HTTPS credentials through Git Credential Manager."
}

function Resolve-Action {
    if ($Action -ne "Auto") {
        return $Action
    }

    $hasExistingState = Test-ExistingGitState
    if ($Yes -or -not [Environment]::UserInteractive) {
        if ($hasExistingState) {
            Write-Warn "Non-interactive confirmation enabled; existing Git state found, using action: Skip"
            return "Skip"
        }
        Write-Warn "Non-interactive confirmation enabled; no Git state found, using action: UpdateIdentity"
        return "UpdateIdentity"
    }

    Write-Step "CHOOSE Select a Git setup action"
    if ($hasExistingState) {
        Write-Info "1. Skip changes"
        Write-Info "2. Update global Git identity and credential helper"
        Write-Info "3. Add another GitHub CLI account with gh auth login"
        $choice = Read-Host "Select an option [1-3] (default: 1)"
        switch ($choice.Trim().ToLowerInvariant()) {
            { $_ -in @("", "1", "skip") } { return "Skip" }
            { $_ -in @("2", "update") } { return "UpdateIdentity" }
            { $_ -in @("3", "add") } { return "AddGitHubAccount" }
            default {
                Write-Warn "Unknown selection '$choice'; skipping changes."
                return "Skip"
            }
        }
    }

    Write-Info "1. Configure global Git identity and credential helper"
    Write-Info "2. Add a GitHub CLI account with gh auth login"
    Write-Info "3. Skip changes"
    $newChoice = Read-Host "Select an option [1-3] (default: 1)"
    switch ($newChoice.Trim().ToLowerInvariant()) {
        { $_ -in @("", "1", "configure") } { return "UpdateIdentity" }
        { $_ -in @("2", "add") } { return "AddGitHubAccount" }
        { $_ -in @("3", "skip") } { return "Skip" }
        default {
            Write-Warn "Unknown selection '$newChoice'; skipping changes."
            return "Skip"
        }
    }
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
    Write-Host ("  {0,-24} {1}" -f "Script", "Git Setup (Windows)")
    Write-Host ("  {0,-24} {1}" -f "Action selected", $script:SelectedAction)
    Write-Host ("  {0,-24} {1}" -f "Status", $StatusLabel)
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
    Write-Host ("  {0,-24} {1}" -f "Action performed", $script:ActionPerformed)
    Write-Host ("  {0,-24} {1}" -f "Failures", $script:FailCount)
    Write-Host ("  {0,-24} {1}" -f "Duration", (Format-Duration -Duration ((Get-Date) - $script:ScriptStart)))
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
}

if (-not (Test-CommandExists "git")) {
    Write-EbkError "git is not installed or is not in PATH."
    exit 1
}

Print-ExistingGitState

$resolvedAction = Resolve-Action
switch ($resolvedAction) {
    "Skip" {
        $script:SelectedAction = "skip"
        Write-Ok "Skipped Git setup changes."
    }
    "UpdateIdentity" {
        Update-GlobalGitIdentity
    }
    "AddGitHubAccount" {
        Add-GitHubAccount
    }
}

if ($script:ActionPerformed -eq 1) {
    Print-NextSteps
}

$finalStatus = "SUCCESS"
if ($script:FailCount -gt 0) {
    $finalStatus = "FAILED"
} elseif ($script:ActionPerformed -eq 0) {
    $finalStatus = "NO CHANGES"
}

Write-Step "SUMMARY Compiling final run report"
Print-StructuredReport -StatusLabel $finalStatus

if ($script:FailCount -gt 0) {
    Write-EbkError ("Completed with {0} error(s)." -f $script:FailCount)
    exit 1
}

Write-Ok "Git setup complete."
exit 0
