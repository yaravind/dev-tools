# launchpad.ps1 - Interactive Windows setup launchpad for the Engineer Bootstrap Kit
#
# Usage:
#   .\scripts\windows\launchpad.cmd
#   .\scripts\windows\launchpad.ps1
#   .\scripts\windows\launchpad.ps1 -Profile full -DryRun
#   .\scripts\windows\launchpad.ps1 -Profile ide-only -Yes
#   .\scripts\windows\launchpad.ps1 -Profile custom

# Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet("full", "minimal-java", "ide-only", "personalize", "custom")]
    [string]$Profile,

    [switch]$DryRun,
    # Compatibility switch: non-critical failures already continue; critical failures always stop.
    [switch]$ContinueOnError,
    # Skip final launchpad confirmation only; child/admin prompts remain independent.
    [switch]$Yes,

    [string]$CloneDestination,
    [string]$CloneRepoList,
    [string]$CodexBackup,
    [string]$CodexBackupTarget
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$resolvedRoot = Resolve-Path (Join-Path $scriptDir "..\..") -ErrorAction SilentlyContinue
if ($resolvedRoot) {
    $repoRoot = $resolvedRoot.Path
} else {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$runParent = Join-Path $repoRoot ".run\launchpad\windows"
$runRoot = $null

$script:TaskOrder = New-Object System.Collections.Generic.List[string]
$script:Tasks = @{}
$script:Selected = @{}
$script:IncludedByDep = @{}
$script:TaskStatus = @{}
$script:TaskExit = @{}
$script:TaskLog = @{}
$script:TaskDuration = @{}
$script:TaskChildExit = @{}
$script:TaskBlockReason = @{}
$script:RunDuration = "-"

function Test-CanPrompt {
    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}

function Add-Task {
    param(
        [string]$Id,
        [string]$Label,
        [string]$Description,
        [string[]]$Deps = @(),
        [switch]$Admin,
        [string]$AdminReason = "",
        [switch]$SoftFail,
        [switch]$Critical
    )

    [void]$script:TaskOrder.Add($Id)
    $script:Tasks[$Id] = [ordered]@{
        Id = $Id
        Label = $Label
        Description = $Description
        Deps = $Deps
        Admin = [bool]$Admin
        AdminReason = $AdminReason
        SoftFail = [bool]$SoftFail
        Critical = [bool]$Critical
    }
}

function Register-Tasks {
    Add-Task -Id "setup_env" -Label "Install full Windows tools" `
        -Description "Install CLI tools, GUI apps, Maven, JEnv-for-Windows, and JAVA_HOME using winget." `
        -Admin -AdminReason "winget installs usually need an elevated PowerShell session." -Critical
    Add-Task -Id "setup_env_min" -Label "Install minimal Java tools" `
        -Description "Install Git, Microsoft OpenJDK 17, Maven, VS Code, and IntelliJ IDEA Community." `
        -Admin -AdminReason "winget installs usually need an elevated PowerShell session." -Critical
    Add-Task -Id "git_setup" -Label "Configure Git" `
        -Description "Set global Git identity, Git Credential Manager, and optional GitHub CLI account."
    Add-Task -Id "clone_repos" -Label "Clone GitHub repositories" `
        -Description "Clone config/github-repos.txt entries, skipping existing directories." -SoftFail
    Add-Task -Id "powershell_profile" -Label "Set up PowerShell profile" `
        -Description "Source config/Microsoft.PowerShell_profile.ps1 from the user PowerShell profile."
    Add-Task -Id "taskbar_setup" -Label "Customize Taskbar" `
        -Description "Apply Taskbar pins from config/taskbar_apps.txt." `
        -Admin -AdminReason "Taskbar pin changes are more reliable from an elevated PowerShell session." -SoftFail
    Add-Task -Id "jenv_setup" -Label "Configure jenv" `
        -Description "Register installed JDKs with JEnv-for-Windows and optionally select a global Java version."
    Add-Task -Id "vscode_setup" -Label "Set up VS Code" `
        -Description "Install VS Code extensions and merge managed settings."
    Add-Task -Id "intellij_setup" -Label "Set up IntelliJ" `
        -Description "Install IntelliJ plugins from config/intellij.txt."
    Add-Task -Id "pycharm_setup" -Label "Set up PyCharm" `
        -Description "Install PyCharm plugins from config/pycharm.txt."
    Add-Task -Id "backup_codex" -Label "Back up Codex" `
        -Description "Back up local .codex data to a target directory." -SoftFail
    Add-Task -Id "restore_codex" -Label "Restore Codex backup" `
        -Description "Replace local .codex from a full backup with safety backup and rollback." -SoftFail
    Add-Task -Id "verify_codex" -Label "Verify Codex restore" `
        -Description "Run read-only diagnostics for local .codex data and app profile/cache signals." -SoftFail
}

function Test-TaskExists {
    param([string]$Id)
    return $script:Tasks.ContainsKey($Id)
}

function Test-TaskDependencies {
    param([string]$Id)
    foreach ($dep in $script:Tasks[$Id].Deps) {
        $state = if ($script:TaskStatus.ContainsKey($dep)) { $script:TaskStatus[$dep] } else { "not-run" }
        if ($state -eq "success" -or ($DryRun -and $state -eq "planned")) { continue }
        $script:TaskStatus[$Id] = "blocked"
        $script:TaskExit[$Id] = "-"
        $script:TaskBlockReason[$Id] = "Prerequisite $dep is $state."
        Write-Warn ("{0} blocked: {1}" -f $script:Tasks[$Id].Label, $script:TaskBlockReason[$Id])
        return $false
    }
    return $true
}

function Set-UnrunDependantsBlocked {
    foreach ($id in $script:TaskOrder) {
        if ($script:Selected.ContainsKey($id) -and -not $script:TaskStatus.ContainsKey($id)) {
            [void](Test-TaskDependencies -Id $id)
        }
    }
}

function Select-Task {
    param(
        [string]$Id,
        [switch]$ByDependency
    )

    if (-not (Test-TaskExists -Id $Id)) {
        Write-EbkError "Unknown task id: $Id"
        return
    }

    $task = $script:Tasks[$Id]
    foreach ($dep in $task.Deps) {
        Select-Task -Id $dep -ByDependency
    }

    if (-not $script:Selected.ContainsKey($Id) -and $ByDependency) {
        $script:IncludedByDep[$Id] = $true
    } elseif (-not $ByDependency) {
        $script:IncludedByDep.Remove($Id)
    }
    $script:Selected[$Id] = $true
}

function Select-ProfileTasks {
    param([string]$SelectedProfile)

    $script:Selected.Clear()
    $script:IncludedByDep.Clear()

    switch ($SelectedProfile) {
        "full" {
            foreach ($id in @("setup_env", "git_setup", "clone_repos", "powershell_profile", "taskbar_setup", "jenv_setup", "vscode_setup", "intellij_setup", "pycharm_setup")) {
                Select-Task -Id $id
            }
        }
        "minimal-java" {
            foreach ($id in @("setup_env_min", "git_setup", "powershell_profile", "vscode_setup", "intellij_setup")) {
                Select-Task -Id $id
            }
        }
        "ide-only" {
            foreach ($id in @("vscode_setup", "intellij_setup", "pycharm_setup")) {
                Select-Task -Id $id
            }
        }
        "personalize" {
            foreach ($id in @("powershell_profile", "taskbar_setup")) {
                Select-Task -Id $id
            }
        }
        "custom" {
            Prompt-CustomTasks
        }
    }
}

function Read-LaunchpadConfirmation {
    param([string]$Prompt, [string]$DefaultValue)
    while ($true) {
        $answer = Read-EbkDefault -Prompt $Prompt -DefaultValue $DefaultValue
        switch ($answer.Trim().ToLowerInvariant()) {
            { $_ -in @("y", "yes") } { return $true }
            { $_ -in @("n", "no") } { return $false }
            default { Write-Warn "Enter y or n." }
        }
    }
}

function Prompt-Profile {
    Write-Step "Choose setup profile"
    Write-Host "  1. full         - winget full tools, Git, repos, shell, Taskbar, Java, IDEs"
    Write-Host "  2. minimal-java - Git, JDK 17, Maven, VS Code, IntelliJ CE, Git config, IDE plugins"
    Write-Host "  3. ide-only     - VS Code, IntelliJ, and PyCharm plugin setup only"
    Write-Host "  4. personalize  - PowerShell profile and Taskbar"
    Write-Host "  5. custom       - Choose individual tasks"
    while ($true) {
        $choice = Read-EbkDefault -Prompt "Select profile [1-5] (default: 1 - full)" -DefaultValue "1"
        switch ($choice.Trim().ToLowerInvariant()) {
            { $_ -in @("", "1", "full") } { return "full" }
            { $_ -in @("2", "minimal-java") } { return "minimal-java" }
            { $_ -in @("3", "ide-only") } { return "ide-only" }
            { $_ -in @("4", "personalize") } { return "personalize" }
            { $_ -in @("5", "custom") } { return "custom" }
            default {
                Write-Warn "Unknown selection '$choice'; choose a profile from 1 to 5."
            }
        }
    }
}

function Prompt-CustomTasks {
    Write-Step "Choose tasks"
    $i = 1
    foreach ($id in $script:TaskOrder) {
        $task = $script:Tasks[$id]
        Write-Host ("  {0,2}. {1,-22} {2}" -f $i, $id, $task.Label)
        $i++
    }

    $selection = Read-EbkLine -Prompt "Enter comma-separated numbers or ids (example: 1,3,vscode_setup)"
    if ([string]::IsNullOrWhiteSpace($selection)) {
        Write-Warn "No custom tasks selected."
        return
    }

    foreach ($token in ($selection -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $id = $token
        if ($token -match '^\d+$') {
            $index = 0
            if (-not [int]::TryParse($token, [ref]$index) -or $index -lt 1 -or $index -gt $script:TaskOrder.Count) {
                Write-Warn "Ignoring invalid task number: $token"
                continue
            }
            $id = $script:TaskOrder[$index - 1]
        }

        if (Test-TaskExists -Id $id) {
            Select-Task -Id $id
        } else {
            Write-Warn "Ignoring unknown task id: $id"
        }
    }
}

function Prompt-OptionalTasks {
    if ($CodexBackup -and -not $script:Selected.ContainsKey("restore_codex")) {
        Select-Task -Id "restore_codex"
    }

    if (-not (Test-CanPrompt)) {
        return
    }

    if (-not $script:Selected.ContainsKey("restore_codex")) {
        if (Read-LaunchpadConfirmation -Prompt "Restore a Codex backup as part of this run? (y/N)" -DefaultValue "n") {
            Select-Task -Id "restore_codex"
        }
    }
}

function Prompt-TaskValues {
    if ($script:Selected.ContainsKey("clone_repos") -and -not (Test-CanPrompt) -and -not $CloneDestination) {
        $script:Selected.Remove("clone_repos")
        $script:IncludedByDep.Remove("clone_repos")
        Write-Info "Repository cloning not selected; provide -CloneDestination to opt in with redirected input."
    }
    if ($script:Selected.ContainsKey("clone_repos") -and (Test-CanPrompt)) {
        Write-Step "Clone GitHub repositories"
        if (-not (Read-LaunchpadConfirmation -Prompt "Clone repositories from config/github-repos.txt? (y/N)" -DefaultValue "n")) {
            $script:Selected.Remove("clone_repos")
            $script:IncludedByDep.Remove("clone_repos")
        } elseif (-not $CloneDestination) {
            $value = Read-EbkLine -Prompt "Directory to clone into [default: current directory]"
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $script:CloneDestinationOverride = $value
            }
        }
    }

    if ($script:Selected.ContainsKey("restore_codex") -and -not $CodexBackup) {
        if (-not (Test-CanPrompt)) {
            throw "Codex restore needs -CodexBackup when stdin is not interactive."
        }
        while (-not $script:CodexBackupOverride) {
            $value = Read-EbkLine -Prompt "Codex backup folder to restore from"
            if ([string]::IsNullOrWhiteSpace($value)) {
                Write-Warn "A backup path is required for Codex restore."
            } else {
                $script:CodexBackupOverride = $value
            }
        }
    }
}

function Get-PwshCommand {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    $powershell = Get-Command powershell -ErrorAction SilentlyContinue
    if ($powershell) { return $powershell.Source }
    return "powershell"
}

function Get-TaskCommand {
    param([string]$Id)

    $ps = Get-PwshCommand
    $repoList = if ($CloneRepoList) { $CloneRepoList } else { Join-Path $repoRoot "config\github-repos.txt" }
    $cloneDest = if ($CloneDestination) { $CloneDestination } elseif ($script:CloneDestinationOverride) { $script:CloneDestinationOverride } else { "." }
    $restoreSource = if ($CodexBackup) { $CodexBackup } else { $script:CodexBackupOverride }
    $backupTarget = if ($CodexBackupTarget) { $CodexBackupTarget } else { Join-Path $HOME ("codex-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss")) }

    switch ($Id) {
        "setup_env" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "setup_env.ps1")) }
        }
        "setup_env_min" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "setup_env_min.ps1"), "-Silent") }
        }
        "git_setup" {
            $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "git_setup.ps1"))
            return @{ File = $ps; Args = $args }
        }
        "clone_repos" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "clone_github_repos.ps1"), $repoList, $cloneDest) }
        }
        "powershell_profile" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "powershell_profile_setup.ps1")) }
        }
        "taskbar_setup" {
            $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "taskbar_setup.ps1"), "-ConfigPath", (Join-Path $repoRoot "config\taskbar_apps.txt"))
            return @{ File = $ps; Args = $args }
        }
        "jenv_setup" {
            $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "jenv_setup.ps1"))
            return @{ File = $ps; Args = $args }
        }
        "vscode_setup" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "vscode_setup.ps1"), "-Yes") }
        }
        "intellij_setup" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "intellij_setup.ps1"), "-Yes") }
        }
        "pycharm_setup" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "pycharm_setup.ps1"), "-Yes") }
        }
        "backup_codex" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "backup_codex.ps1"), $backupTarget) }
        }
        "restore_codex" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "restore_codex.ps1"), $restoreSource) }
        }
        "verify_codex" {
            return @{ File = $ps; Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptDir "verify_codex_restore.ps1")) }
        }
        default {
            throw "No command registered for task: $Id"
        }
    }
}

function Format-Command {
    param([hashtable]$Command)
    $parts = @($Command.File) + @($Command.Args)
    return ($parts | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join " "
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Resolve-AdminScope {
    param([System.Collections.IDictionary]$Task)

    $script:AdminBlockReason = ""
    $script:AdminBlockFix = ""

    if (-not $Task.Admin -or (Test-IsAdmin)) {
        return 0
    }

    Write-Warn ("{0} is admin-scoped." -f $Task.Label)
    if ($Task.AdminReason) {
        Write-Info ("{0}" -f $Task.AdminReason)
    }

    if (-not (Test-CanPrompt)) {
        $script:AdminBlockReason = ("{0} installs or configures Windows components that require an elevated PowerShell session. Launchpad is running non-elevated, so continuing can trigger hidden prompts, failed installs, or a stalled child process." -f $Task.Label)
        $script:AdminBlockFix = "Start PowerShell as Administrator, rerun this launchpad profile, or choose a profile without admin-scoped tasks such as ide-only."
        Write-EbkError ("{0} requires an elevated PowerShell session." -f $Task.Label)
        Write-EbkError ("Reason: {0}" -f $script:AdminBlockReason)
        Write-EbkError ("Fix: {0}" -f $script:AdminBlockFix)
        Write-EbkError "No child script was started."
        return 1
    }

    if (-not (Read-LaunchpadConfirmation -Prompt "Continue without elevated PowerShell? This may prompt, fail, or stall. (y/N)" -DefaultValue "n")) {
        $script:AdminBlockReason = "User did not approve running an admin-scoped task from a non-elevated PowerShell session."
        $script:AdminBlockFix = "Rerun from an elevated PowerShell session or choose a profile without admin-scoped tasks."
        Write-Warn ("Skipping {0} without elevated PowerShell." -f $Task.Label)
        return 2
    }

    Write-Warn "Continuing without elevation because you explicitly confirmed it."
    return 0
}

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-LaunchpadPersistedEnvironment {
    param([string]$Name, [string]$Scope)
    return [Environment]::GetEnvironmentVariable($Name, $Scope)
}

function Update-InstallEnvironment {
    param([string]$Id)
    if ($Id -notin @("setup_env", "setup_env_min")) { return }

    $entries = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @(
        (Get-LaunchpadPersistedEnvironment -Name "Path" -Scope "Machine"),
        (Get-LaunchpadPersistedEnvironment -Name "Path" -Scope "User"),
        $env:Path
    )) {
        foreach ($entry in ($value -split ";")) {
            if (-not [string]::IsNullOrWhiteSpace($entry) -and $seen.Add($entry)) {
                [void]$entries.Add($entry)
            }
        }
    }
    $env:Path = $entries -join ";"
    $javaHome = Get-LaunchpadPersistedEnvironment -Name "JAVA_HOME" -Scope "User"
    if (-not $javaHome) { $javaHome = Get-LaunchpadPersistedEnvironment -Name "JAVA_HOME" -Scope "Machine" }
    if ($javaHome) { $env:JAVA_HOME = $javaHome }
    Write-Info "Refreshed the launchpad PATH and persisted Java environment."
}

function Check-TaskReady {
    param([string]$Id)

    switch ($Id) {
        "setup_env" {
            if (-not $DryRun -and -not (Test-CommandExists "winget")) {
                Write-EbkError "Full setup requires winget in PATH."
                return $false
            }
        }
        "setup_env_min" {
            if (-not $DryRun -and -not (Test-CommandExists "winget")) {
                Write-EbkError "Minimal setup requires winget in PATH."
                return $false
            }
        }
        "clone_repos" {
            $repoList = if ($CloneRepoList) { $CloneRepoList } else { Join-Path $repoRoot "config\github-repos.txt" }
            if (-not (Test-Path -LiteralPath $repoList)) {
                Write-EbkError "Repo list not found."
                return $false
            }
            if (-not $DryRun -and -not (Test-CommandExists "git")) {
                Write-EbkError "Clone repositories requires git in PATH."
                return $false
            }
        }
        "vscode_setup" {
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "config\vscode.txt"))) {
                Write-EbkError "VS Code config not found."
                return $false
            }
        }
        "intellij_setup" {
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "config\intellij.txt"))) {
                Write-EbkError "IntelliJ config not found."
                return $false
            }
        }
        "pycharm_setup" {
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "config\pycharm.txt"))) {
                Write-EbkError "PyCharm config not found."
                return $false
            }
        }
        "taskbar_setup" {
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "config\taskbar_apps.txt"))) {
                Write-EbkError "Taskbar config not found."
                return $false
            }
        }
        "restore_codex" {
            $restoreSource = if ($CodexBackup) { $CodexBackup } else { $script:CodexBackupOverride }
            if (-not $restoreSource) {
                Write-EbkError "Codex restore requires -CodexBackup."
                return $false
            }
            if (-not $DryRun -and -not (Test-Path -LiteralPath $restoreSource)) {
                Write-EbkError "Codex backup folder not found: $restoreSource"
                return $false
            }
        }
    }

    return $true
}

function Print-ProfileDetails {
    if ($Profile -eq "minimal-java") {
        Write-Step "Profile details: minimal-java"
        Write-Host "This profile runs the smallest Java/Spark-oriented Windows setup path:"
        Write-Host "  - Install Git, Microsoft OpenJDK 17, Maven, VS Code, and IntelliJ IDEA Community"
        Write-Host "  - Configure global Git identity and credential helper"
        Write-Host "  - Source the shared PowerShell profile"
        Write-Host "  - Install VS Code extensions/settings and IntelliJ plugins"
        Write-Host ""
    }
}

function New-LaunchpadRunDirectory {
    New-Item -ItemType Directory -Path $runParent -Force -ErrorAction Stop | Out-Null
    $name = "{0}-{1}-{2}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $PID, [guid]::NewGuid().ToString("N")
    $directory = Join-Path $runParent $name
    New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
    return $directory
}

function Print-Plan {
    Write-Step "Run plan"
    Print-ProfileDetails
    Write-Host ("Profile: {0}" -f $Profile)
    Write-Host ("Mode: {0}" -f $(if ($DryRun) { "dry-run" } else { "execute" }))
    Write-Host "Failure policy: continue after non-critical failures; stop after core setup failures; block unmet prerequisites"
    Write-Host ("Logs: {0}" -f $runRoot)
    Write-Host ""

    $index = 1
    foreach ($id in $script:TaskOrder) {
        if (-not $script:Selected.ContainsKey($id)) { continue }
        $task = $script:Tasks[$id]
        $command = Get-TaskCommand -Id $id
        $labels = New-Object System.Collections.Generic.List[string]
        if ($task.Admin) { [void]$labels.Add("[admin]") }
        if ($task.SoftFail) { [void]$labels.Add("[continues-on-issues]") }
        if ($script:IncludedByDep.ContainsKey($id)) { [void]$labels.Add("(dependency)") }
        $labelText = if ($labels.Count -gt 0) { " " + ($labels -join " ") } else { "" }

        Write-Host ("{0,2}. {1}{2}" -f $index, $task.Label, $labelText)
        Write-Host ("    {0}" -f $task.Description)
        if ($task.Admin -and $task.AdminReason) {
            Write-Warn ("admin: {0}" -f $task.AdminReason)
        }
        if ($task.SoftFail) {
            Write-Warn "issues: Nonzero exit is recorded and the launchpad continues."
        }
        Write-Host ("    command: {0}" -f (Format-Command -Command $command))
        $index++
    }
}

function Confirm-Plan {
    if ($Yes -or $DryRun) {
        return $true
    }

    return (Read-LaunchpadConfirmation -Prompt "Proceed with this launchpad run? (Y/n)" -DefaultValue "y")
}

function Write-LaunchpadOutputLine {
    param([AllowNull()][string]$Line)

    if ($null -eq $Line) {
        return
    }

    if (Get-Command Initialize-EbkPaletteIfNeeded -ErrorAction SilentlyContinue) {
        Initialize-EbkPaletteIfNeeded
    }

    $color = $null
    if ($Line -match '^\s*(?:\S+\s+)?(PHASE|INFO|OK|WARN|ERROR|DEBUG)\s+') {
        switch ($matches[1]) {
            "PHASE" { $color = $script:EbPhase }
            "INFO" { $color = $script:EbInfo }
            "OK" { $color = $script:EbOk }
            "WARN" { $color = $script:EbWarn }
            "ERROR" { $color = $script:EbError }
            "DEBUG" { $color = $script:EbDebug }
        }
    }

    if ($color) {
        Write-Host $Line -ForegroundColor $color
    } else {
        Write-Host $Line
    }
}

function Invoke-Task {
    param([string]$Id)

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $ErrorActionPreference = "Stop"
    $result = 1
    $script:TaskChildExit.Remove($Id)
    $script:TaskLog.Remove($Id)
    $script:TaskStatus[$Id] = "running"
    $script:TaskExit[$Id] = "-"
    try {
        $result = Invoke-TaskCore -Id $Id
    } catch {
        Set-TaskFailure -Id $Id -Message "Task execution or logging failed: $_"
        $result = $script:TaskExit[$Id]
    } finally {
        $timer.Stop()
        $script:TaskDuration[$Id] = $timer.Elapsed.TotalSeconds.ToString("F5", [Globalization.CultureInfo]::InvariantCulture)
        if ($script:TaskLog.ContainsKey($Id) -and (Test-Path -LiteralPath $script:TaskLog[$Id])) {
            try {
                Add-Content -LiteralPath $script:TaskLog[$Id] -Value ("Duration seconds: {0}" -f $script:TaskDuration[$Id]) -ErrorAction Stop
            } catch {
                Set-TaskFailure -Id $Id -Message "Cannot finalize task log: $_"
                $result = $script:TaskExit[$Id]
            }
        }
    }
    return $result
}

function Set-TaskFailure {
    param([string]$Id, [string]$Message)
    $script:TaskStatus[$Id] = "failed"
    $rc = if ($script:TaskChildExit.ContainsKey($Id) -and $script:TaskChildExit[$Id] -ne 0) {
        $script:TaskChildExit[$Id]
    } else { 1 }
    $script:TaskExit[$Id] = $rc
    Write-EbkError $Message
    if ($script:TaskLog.ContainsKey($Id) -and (Test-Path -LiteralPath $script:TaskLog[$Id])) {
        try {
            Add-Content -LiteralPath $script:TaskLog[$Id] -Value "Launchpad status: failed`nError: $Message" -ErrorAction Stop
        } catch {
            Write-EbkError "Could not record task failure in the log: $_"
        }
    }
}

function Invoke-ChildTask {
    param([string]$Id, [hashtable]$Command, [string]$LogFile)
    $application = Get-Command $Command.File -CommandType Application -ErrorAction Stop
    $previousColor = $env:EBK_FORCE_COLOR
    # Windows PowerShell represents native stderr as ErrorRecords, even for warnings.
    $ErrorActionPreference = "Continue"
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $env:EBK_FORCE_COLOR = "1"
        $global:LASTEXITCODE = $null
        & $application.Source @($Command.Args) 2>&1 | ForEach-Object {
            $line = [string]$_
            Add-Content -LiteralPath $LogFile -Value $line -ErrorAction Stop
            Write-LaunchpadOutputLine -Line $line
        }
        if ($null -eq $LASTEXITCODE) { throw "Child process did not provide an exit code." }
        $script:TaskChildExit[$Id] = $LASTEXITCODE
        return $LASTEXITCODE
    } finally {
        $env:EBK_FORCE_COLOR = $previousColor
        if ($null -ne $LASTEXITCODE) { $script:TaskChildExit[$Id] = $LASTEXITCODE }
    }
}

function Invoke-TaskCore {
    param([string]$Id)

    $task = $script:Tasks[$Id]
    $logFile = Join-Path $runRoot "$Id.log"
    $script:TaskLog[$Id] = $logFile

    Write-Step ("Running {0}" -f $task.Label)
    Write-Info "Log file: $logFile"

    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $command = Get-TaskCommand -Id $Id
    @(
        "Launchpad task log"
        "Task id: $Id"
        "Task label: $($task.Label)"
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
        "Command: $(Format-Command -Command $command)"
        "Log file: $logFile"
        ""
    ) | Set-Content -Path $logFile -Encoding UTF8

    if ($DryRun) {
        $script:TaskStatus[$Id] = "planned"
        $script:TaskExit[$Id] = "-"
        Write-Host ("[dry-run] {0}" -f (Format-Command -Command $command))
        Add-Content -Path $logFile -Value "Launchpad status: planned dry-run"
        Add-Content -Path $logFile -Value ("Finished: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
        Add-Content -Path $logFile -Value "Exit code: planned"
        return 0
    }

    $adminStatus = Resolve-AdminScope -Task $task
    if ($adminStatus -eq 2) {
        $script:TaskStatus[$Id] = "skipped"
        $script:TaskExit[$Id] = "-"
        Add-Content -Path $logFile -Value "Launchpad status: skipped"
        Add-Content -Path $logFile -Value ("Reason: {0}" -f $script:AdminBlockReason)
        Add-Content -Path $logFile -Value ("Fix: {0}" -f $script:AdminBlockFix)
        Add-Content -Path $logFile -Value "Child script started: no"
        Add-Content -Path $logFile -Value ("Finished: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
        Add-Content -Path $logFile -Value "Exit code: skipped"
        return 0
    }
    if ($adminStatus -ne 0) {
        $script:TaskStatus[$Id] = "failed"
        $script:TaskExit[$Id] = 1
        Add-Content -Path $logFile -Value "Launchpad status: failed before script execution"
        Add-Content -Path $logFile -Value "Error: elevated PowerShell session required."
        Add-Content -Path $logFile -Value ("Reason: {0}" -f $script:AdminBlockReason)
        Add-Content -Path $logFile -Value ("Fix: {0}" -f $script:AdminBlockFix)
        Add-Content -Path $logFile -Value "Child script started: no"
        Add-Content -Path $logFile -Value ("Finished: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
        Add-Content -Path $logFile -Value "Exit code: 1"
        return 1
    }

    if (-not (Check-TaskReady -Id $Id)) {
        $script:TaskStatus[$Id] = "failed"
        $script:TaskExit[$Id] = 1
        Add-Content -Path $logFile -Value "Launchpad status: failed readiness check"
        return 1
    }

    $rc = Invoke-ChildTask -Id $Id -Command $command -LogFile $logFile
    $script:TaskExit[$Id] = $rc

    Add-Content -Path $logFile -Value ""
    Add-Content -Path $logFile -Value ("Finished: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    Add-Content -Path $logFile -Value ("Exit code: {0}" -f $rc)

    if ($rc -eq 0) {
        try {
            Update-InstallEnvironment -Id $Id
        } catch {
            $script:TaskStatus[$Id] = "failed"
            $script:TaskExit[$Id] = 1
            Write-EbkError "Environment refresh failed: $_"
            Add-Content -Path $logFile -Value "Launchpad status: failed environment refresh`nError: $_"
            return 1
        }
        $script:TaskStatus[$Id] = "success"
        Write-Ok ("{0} completed." -f $task.Label)
        return 0
    }

    if ($task.SoftFail) {
        $script:TaskStatus[$Id] = "issues"
        Write-Warn ("{0} completed with issues. Continuing; review {1}." -f $task.Label, $logFile)
        return 0
    }

    $script:TaskStatus[$Id] = "failed"
    Write-EbkError ("{0} failed with exit code {1}." -f $task.Label, $rc)
    return $rc
}

function Invoke-SelectedTasks {
    if ($script:Selected.Count -eq 0) {
        Write-Warn "No tasks selected. Nothing to run."
        return 0
    }

    $overall = 0
    foreach ($id in $script:TaskOrder) {
        if (-not $script:Selected.ContainsKey($id)) { continue }

        if (-not (Test-TaskDependencies -Id $id)) {
            if ($overall -eq 0) { $overall = 1 }
            continue
        }
        $rc = Invoke-Task -Id $id
        if ($rc -ne 0) {
            if ($overall -eq 0) { $overall = $rc }
            $task = $script:Tasks[$id]
            if ($task.Critical) {
                Write-EbkError ("Critical task failed; stopping because {0} runs core setup." -f $task.Label)
                Set-UnrunDependantsBlocked
                return $rc
            }
            Write-Warn ("Recorded failure for {0}; continuing with remaining selected tasks." -f $task.Label)
        }
    }

    return $overall
}

function Print-ProblemDetails {
    $shown = $false
    foreach ($id in $script:TaskOrder) {
        $state = if ($script:TaskStatus.ContainsKey($id)) { $script:TaskStatus[$id] } else { "" }
        if ($state -notin @("failed", "issues", "blocked")) { continue }

        if (-not $shown) {
            Write-Host ""
            Write-Warn "Captured problem details"
            $shown = $true
        }

        $logFile = if ($script:TaskLog.ContainsKey($id)) { $script:TaskLog[$id] } else { "not-created" }
        $exit = if ($script:TaskExit.ContainsKey($id)) { $script:TaskExit[$id] } else { "-" }
        Write-Host ("  - {0} ({1}, exit {2})" -f $script:Tasks[$id].Label, $state, $exit)
        if ($state -eq "blocked") {
            Write-Host ("    Reason: {0}" -f $script:TaskBlockReason[$id])
            continue
        }
        Write-Host ("    Log file: {0}" -f $logFile)

        if (Test-Path -LiteralPath $logFile) {
            $matches = Get-Content -Path $logFile -ErrorAction SilentlyContinue |
                Where-Object { $_ -match 'ERROR|FAIL|fatal:|Traceback|Exception|failed' } |
                Select-Object -First 8
            if ($matches) {
                $matches | ForEach-Object { Write-Host ("      {0}" -f $_) }
            } else {
                Write-Host "      No error-looking lines found; last log lines:"
                Get-Content -Path $logFile -Tail 8 | ForEach-Object { Write-Host ("      {0}" -f $_) }
            }
        }
    }
}

function Print-Summary {
    $counts = @{
        success = 0
        failed = 0
        issues = 0
        planned = 0
        skipped = 0
        blocked = 0
        pending = 0
    }

    Write-Step "Launchpad summary"
    Write-Host ("  {0,-24} {1,-10} {2,-6} {3,12} {4}" -f "Task", "Status", "Exit", "Time (s)", "Log file")
    Write-Host ("  {0,-24} {1,-10} {2,-6} {3,12} {4}" -f "------------------------", "----------", "------", "------------", "--------")
    foreach ($id in $script:TaskOrder) {
        if (-not $script:Selected.ContainsKey($id)) { continue }
        $state = if ($script:TaskStatus.ContainsKey($id)) { $script:TaskStatus[$id] } else { "not-run" }
        switch ($state) {
            "success" { $counts.success++ }
            "failed" { $counts.failed++ }
            "issues" { $counts.issues++ }
            "planned" { $counts.planned++ }
            "skipped" { $counts.skipped++ }
            "blocked" { $counts.blocked++ }
            default { $counts.pending++ }
        }
        $exit = if ($script:TaskExit.ContainsKey($id)) { $script:TaskExit[$id] } else { "-" }
        $log = if ($script:TaskLog.ContainsKey($id)) { $script:TaskLog[$id] } else { "-" }
        $duration = if ($script:TaskDuration.ContainsKey($id)) { $script:TaskDuration[$id] } else { "-" }
        Write-Host ("  {0,-24} {1,-10} {2,-6} {3,12} {4}" -f $id, $state, $exit, $duration, $log)
    }

    Write-Host ""
    Write-Host ("  Success: {0}" -f $counts.success)
    Write-Host ("  Issues:  {0}" -f $counts.issues)
    Write-Host ("  Failed:  {0}" -f $counts.failed)
    Write-Host ("  Planned: {0}" -f $counts.planned)
    Write-Host ("  Skipped: {0}" -f $counts.skipped)
    Write-Host ("  Blocked: {0}" -f $counts.blocked)
    Write-Host ("  Not run: {0}" -f $counts.pending)
    Write-Host ("  Overall execution time (s): {0}" -f $script:RunDuration)
    Write-Host ("  Logs:    {0}" -f $runRoot)

    Print-ProblemDetails
}

function Invoke-LaunchpadRun {
    $runTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $result = 1
    try {
        $result = Invoke-SelectedTasks
    } catch {
        Write-EbkError "Launchpad execution failed: $_"
    } finally {
        $runTimer.Stop()
        $script:RunDuration = $runTimer.Elapsed.TotalSeconds.ToString("F5", [Globalization.CultureInfo]::InvariantCulture)
        Print-Summary
    }
    return $result
}

Register-Tasks

try {
    if (-not $Profile) { $Profile = Prompt-Profile }
    Select-ProfileTasks -SelectedProfile $Profile
    Prompt-OptionalTasks
    Prompt-TaskValues
    $runRoot = New-LaunchpadRunDirectory
    Print-Plan
    if (-not (Confirm-Plan)) {
        Write-Warn "Launchpad run canceled."
        exit 0
    }
} catch {
    Write-EbkError "Launchpad preparation canceled or failed: $_"
    exit 1
}

$result = Invoke-LaunchpadRun
exit $result
