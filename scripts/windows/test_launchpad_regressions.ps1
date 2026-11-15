param([switch]$InputProbe)

$ErrorActionPreference = "Stop"
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "launchpad.ps1") -Raw -Encoding UTF8
. (Join-Path $PSScriptRoot "branding.ps1")
if ($InputProbe) {
    try {
        $value = Read-EbkDefault -Prompt "Probe" -DefaultValue "y"
        if ($value -ne "y") { throw "Unexpected default value: $value" }
        exit 0
    } catch {
        Write-EbkError "Input probe failed: $_"
        exit 1
    }
}
$ast = [ScriptBlock]::Create($source).Ast
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([ScriptBlock]::Create($statement.Extent.Text))
    }
}

$invokeSelectedOriginal = (Get-Command Invoke-SelectedTasks).ScriptBlock
$commandOriginal = (Get-Command Get-TaskCommand).ScriptBlock
$readDefaultOriginal = (Get-Command Read-EbkDefault).ScriptBlock
$adminOriginal = (Get-Command Resolve-AdminScope).ScriptBlock

function Assert-Launchpad {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$originalPath = $env:Path
$originalJava = $env:JAVA_HOME
try {
    function Get-LaunchpadPersistedEnvironment {
        param([string]$Name, [string]$Scope)
        if ($Name -eq "JAVA_HOME") { return "C:\NewJava" }
        if ($Scope -eq "Machine") { return "C:\Windows;C:\NewTool" }
        return "C:\UserTool;c:\newtool"
    }
    $env:Path = "C:\SessionOnly;C:\Windows"
    Update-InstallEnvironment -Id setup_env
    Assert-Launchpad ($env:Path -eq "C:\Windows;C:\NewTool;C:\UserTool;C:\SessionOnly") "PATH refresh lost or duplicated entries."
    Assert-Launchpad ($env:JAVA_HOME -eq "C:\NewJava") "JAVA_HOME was not refreshed."
    Update-InstallEnvironment -Id setup_env_min
    Assert-Launchpad (($env:Path -split ";").Count -eq 4) "Repeated refresh duplicated PATH."
    function Get-LaunchpadPersistedEnvironment { throw "Mock environment read failure" }
    $failed = $false
    try { Update-InstallEnvironment -Id setup_env } catch { $failed = $true }
    Assert-Launchpad $failed "Environment errors must propagate."
    Update-InstallEnvironment -Id git_setup
} finally {
    $env:Path = $originalPath
    $env:JAVA_HOME = $originalJava
}
Write-EbkOk "Launchpad environment regression checks passed."

$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
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
Register-Tasks
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("dev-tools-launchpad-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$runRoot = Join-Path $testRoot "logs"
$DryRun = $false
$mockExit = 0
function Resolve-AdminScope { return 0 }
function Check-TaskReady { return $true }
function Get-TaskCommand {
    return @{ File = (Get-Command pwsh).Source; Args = @("-NoProfile", "-Command", "[Console]::Error.WriteLine('warning'); Write-Output 'child-output'; exit $mockExit") }
}
try {
    $rc = Invoke-Task -Id vscode_setup
    Assert-Launchpad ($rc -eq 0 -and $script:TaskStatus.vscode_setup -eq "success") "Child warnings must not fail successful tasks."
    $mockExit = 7
    $rc = Invoke-Task -Id vscode_setup
    Assert-Launchpad ($rc -eq 7 -and $script:TaskChildExit.vscode_setup -eq 7) "Child exit code was lost."
    function Add-Content {
        param($LiteralPath, $Path, $Value, $ErrorAction)
        if ($Value -like "Duration seconds:*") { throw "Mock final log write failure" }
        Microsoft.PowerShell.Management\Add-Content -LiteralPath $(if ($LiteralPath) { $LiteralPath } else { $Path }) -Value $Value -ErrorAction Stop
    }
    $rc = Invoke-Task -Id vscode_setup
    Assert-Launchpad ($rc -eq 7 -and $script:TaskStatus.vscode_setup -eq "failed") "Log failure lost child exit status."
    $mockExit = 0
    $rc = Invoke-Task -Id vscode_setup
    Assert-Launchpad ($rc -eq 1 -and $script:TaskStatus.vscode_setup -eq "failed") "Final log failure reported success."
    Remove-Item Function:\Add-Content
    $script:TaskChildExit.Clear()
    $runRoot = Join-Path $testRoot "block/logs"
    Set-Content -LiteralPath (Join-Path $testRoot "block") -Value "block"
    $rc = Invoke-Task -Id vscode_setup
    Assert-Launchpad ($rc -ne 0 -and $script:TaskStatus.vscode_setup -eq "failed") "Directory failure was not recorded."
    Assert-Launchpad ($script:TaskDuration.vscode_setup -match '^\d+\.\d{5}$') "Failure duration was not finalized."
    $runRoot = Join-Path $testRoot "logs"
    function Get-TaskCommand { return @{ File = (Join-Path $testRoot "missing-command"); Args = @() } }
    $rc = Invoke-Task -Id vscode_setup
    Assert-Launchpad ($rc -ne 0 -and $script:TaskStatus.vscode_setup -eq "failed") "Child start failure reported success."
    function Get-TaskCommand { throw "Mock command construction failure" }
    $rc = Invoke-Task -Id vscode_setup
    Assert-Launchpad ($rc -ne 0) "Command construction failure reported success."
    function Invoke-SelectedTasks { throw "Mock unexpected run failure" }
    $runOutput = Invoke-LaunchpadRun 6>&1
    Assert-Launchpad (($runOutput | Where-Object { $_ -is [int] }) -eq 1) "Unexpected run failure lost exit status."
    Assert-Launchpad (($runOutput -join "`n") -match "Launchpad summary") "Exception bypassed final summary."
} finally {
    Remove-Item -LiteralPath (Join-Path $testRoot "logs/vscode_setup.log"), (Join-Path $testRoot "logs/summary.json"), (Join-Path $testRoot "block") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $testRoot "logs"), $testRoot -Force
}
Write-EbkOk "Launchpad infrastructure regression checks passed."

Set-Item Function:Invoke-SelectedTasks $invokeSelectedOriginal
Assert-Launchpad $script:Tasks.setup_env_min.Critical "Minimal setup must be critical."
$script:TaskOrder.Clear()
$script:Tasks.Clear()
$script:Selected.Clear()
Add-Task -Id prereq -Label Prerequisite -Description "Mock prerequisite"
Add-Task -Id dependant -Label Dependant -Description "Mock dependant" -Deps @("prereq")
Add-Task -Id independent -Label Independent -Description "Mock independent"
Select-Task -Id dependant
Assert-Launchpad ($script:IncludedByDep.ContainsKey("prereq")) "Auto-selected prerequisite label is missing."
Select-Task -Id prereq
Assert-Launchpad (-not $script:IncludedByDep.ContainsKey("prereq")) "Explicit selection retained a dependency label."
foreach ($id in $script:TaskOrder) { $script:Selected[$id] = $true }
function Invoke-Task {
    param([string]$Id)
    $script:Executed.Add($Id)
    if ($Id -eq "prereq") {
        $script:TaskStatus[$Id] = $prereqState
        if ($prereqState -eq "failed") { return 7 }
    } else { $script:TaskStatus[$Id] = "success" }
    return 0
}
foreach ($prereqState in @("success", "skipped", "failed", "issues", "planned")) {
    $script:TaskStatus.Clear()
    $script:TaskExit.Clear()
    $script:TaskDuration.Clear()
    $script:TaskBlockReason.Clear()
    $script:Executed = New-Object System.Collections.Generic.List[string]
    $DryRun = $prereqState -eq "planned"
    $rc = Invoke-SelectedTasks
    if ($prereqState -in @("success", "planned")) {
        Assert-Launchpad ($rc -eq 0 -and $script:Executed.Count -eq 3) "Successful/planned prerequisite was blocked."
    } else {
        Assert-Launchpad ($rc -ne 0 -and $script:TaskStatus.dependant -eq "blocked") "Unmet prerequisite did not block its dependant."
        Assert-Launchpad (($script:Executed -join " ") -eq "prereq independent") "Blocked task ran or independent task was stopped."
        Assert-Launchpad (-not $script:TaskDuration.ContainsKey("dependant")) "Blocked task should not be timed."
    }
}
$script:Tasks.prereq.Critical = $true
$prereqState = "failed"
foreach ($ContinueOnError in @($false, $true)) {
    $script:TaskStatus.Clear()
    $script:Executed.Clear()
    $rc = Invoke-SelectedTasks
    Assert-Launchpad ($rc -eq 7 -and $script:Executed.Count -eq 1 -and $script:TaskStatus.dependant -eq "blocked") "Critical failure policy differs with compatibility switch."
}
$summary = Print-Summary 6>&1
Assert-Launchpad (($summary -join "`n") -match "Blocked: 1") "Blocked count is missing from summary."
Assert-Launchpad (($summary -join "`n") -match "Prerequisite prereq is failed.") "Blocked reason is missing from summary."
Write-EbkOk "Launchpad dependency and critical-policy regression checks passed."

$script:Answers = New-Object System.Collections.Generic.Queue[string]
function Read-EbkDefault {
    param([string]$Prompt, [string]$DefaultValue)
    if ($script:Answers.Count -eq 0) { throw [IO.EndOfStreamException]::new("Mock EOF") }
    $answer = $script:Answers.Dequeue()
    if ($answer -eq "") { return $DefaultValue }
    return $answer
}
$script:Answers.Enqueue("typo")
$script:Answers.Enqueue("3")
Assert-Launchpad ((Prompt-Profile) -eq "ide-only") "Invalid profile must reprompt instead of choosing full."
$script:Answers.Enqueue("")
Assert-Launchpad ((Prompt-Profile) -eq "full") "Blank profile must preserve its default."
$failed = $false
try { Prompt-Profile } catch [IO.EndOfStreamException] { $failed = $true }
Assert-Launchpad $failed "Profile EOF must propagate."
$DryRun = $false
$Yes = $false
$script:Answers.Enqueue("invalid")
$script:Answers.Enqueue("yes")
Assert-Launchpad (Confirm-Plan) "Invalid confirmation must reprompt."
$script:Answers.Enqueue("")
Assert-Launchpad (Confirm-Plan) "Blank confirmation must preserve yes."
$script:Answers.Enqueue("no")
Assert-Launchpad (-not (Confirm-Plan)) "No confirmation must cancel."
$failed = $false
try { Confirm-Plan } catch [IO.EndOfStreamException] { $failed = $true }
Assert-Launchpad $failed "Confirmation EOF must not approve or succeed."
$Yes = $true
Assert-Launchpad (Confirm-Plan) "Yes must skip final confirmation."
Set-Item Function:Get-TaskCommand $commandOriginal
foreach ($id in @("git_setup", "jenv_setup", "taskbar_setup", "restore_codex")) {
    $command = Get-TaskCommand -Id $id
    Assert-Launchpad ("-Yes" -notin $command.Args) "Launchpad Yes implicitly approved child task $id."
}
function Test-IsAdmin { return $false }
function Test-CanPrompt { return $false }
Set-Item Function:Resolve-AdminScope $adminOriginal
$script:TaskOrder.Clear()
$script:Tasks.Clear()
Register-Tasks
$rc = Resolve-AdminScope -Task $script:Tasks.setup_env
Assert-Launchpad ($rc -eq 1) "Redirected admin approval must fail without prompting."
$script:Selected.Clear()
Select-Task -Id clone_repos
$CloneDestination = ""
Prompt-TaskValues
Assert-Launchpad (-not $script:Selected.ContainsKey("clone_repos")) "Redirected cloning must remain opt-in."
$CloneDestination = "C:\ExplicitDestination"
Select-Task -Id clone_repos
Prompt-TaskValues
Assert-Launchpad ($script:Selected.ContainsKey("clone_repos")) "Explicit clone destination must opt in."
function Test-CanPrompt { return $true }
$script:Selected.Clear()
Select-Task -Id restore_codex
$CodexBackup = ""
function Read-EbkLine { throw [IO.EndOfStreamException]::new("Mock required-path EOF") }
$failed = $false
try { Prompt-TaskValues } catch [IO.EndOfStreamException] { $failed = $true }
Assert-Launchpad $failed "Required-path EOF must stop the prompt loop."
Set-Item Function:Read-EbkDefault $readDefaultOriginal
foreach ($sendBlank in @($false, $true)) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Get-PwshCommand
    $info.Arguments = '-NoProfile -File "' + $PSCommandPath + '" -InputProbe'
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($sendBlank) { $process.StandardInput.WriteLine("") }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) {
            $process.Kill()
            throw "Redirected input probe hung."
        }
        $expectedExit = if ($sendBlank) { 0 } else { 1 }
        Assert-Launchpad ($process.ExitCode -eq $expectedExit) "Redirected EOF/default probe failed: $($stdout.Result) $($stderr.Result)"
    } finally {
        $process.Dispose()
    }
}
Write-EbkOk "Launchpad prompt and EOF regression checks passed."
