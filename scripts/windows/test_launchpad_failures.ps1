$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "branding.ps1")
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "launchpad.ps1") -Raw -Encoding UTF8
foreach ($statement in [ScriptBlock]::Create($source).Ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([ScriptBlock]::Create($statement.Extent.Text))
    }
}
$script:TaskOrder = New-Object System.Collections.Generic.List[string]
$script:Tasks = @{}
$script:Selected = @{}
$script:TaskStatus = @{}
$script:TaskExit = @{}
$script:TaskLog = @{}
$script:TaskDuration = @{}
$script:TaskChildExit = @{}
$script:TaskBlockReason = @{}
$script:TaskCommands = @{}
$scriptDir = $PSScriptRoot
$runRoot = Join-Path ([IO.Path]::GetTempPath()) ("dev-tools-failures-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $runRoot | Out-Null
$childMarker = Join-Path $runRoot "child-started"
$realChild = (Get-Command Invoke-ChildTask).ScriptBlock
$previousPath = $env:Path
$previousJava = $env:JAVA_HOME
$previousResult = $env:EBK_RESULT_FILE
function Resolve-AdminScope {
    if ($mode -eq "admin-skip") { return 2 }
    if ($mode -eq "admin-failure") { return 1 }
    return 0
}
function Check-TaskReady { return $mode -ne "readiness-failure" }
function Get-TaskCommand {
    if ($mode -eq "build-failure") { throw "Mock build failure" }
    $marker = $childMarker.Replace("'", "''")
    return @{ File = Get-PwshCommand; Args = @("-NoProfile", "-Command", "[IO.File]::WriteAllText('$marker','started'); exit $mockExit") }
}
function Invoke-ChildTask {
    param($Id, $Command, $LogFile)
    if ($mode -eq "result-write-failure") {
        $Command.Args = @("-NoProfile", "-Command",
            ". '$((Join-Path $PSScriptRoot 'branding.ps1').Replace("'", "''"))'; `$env:EBK_RESULT_FILE = '$runRoot/missing/result.json'; Write-EbkTaskResult -Status success")
    }
    return (& $realChild -Id $Id -Command $Command -LogFile $LogFile)
}
try {
    Add-Task -Id test -Label Test -Description "Mock task"
    foreach ($mode in @("success", "child-failure", "admin-skip", "admin-failure", "readiness-failure", "build-failure", "planned", "result-write-failure")) {
        $DryRun = $mode -eq "planned"
        $mockExit = if ($mode -eq "child-failure") { 7 } else { 0 }
        $script:TaskStatus.Clear()
        $script:TaskExit.Clear()
        $script:TaskChildExit.Clear()
        if (Test-Path -LiteralPath $childMarker) { Remove-Item -LiteralPath $childMarker }
        if (Test-Path -LiteralPath (Join-Path $runRoot "test.log")) { Remove-Item -LiteralPath (Join-Path $runRoot "test.log") }
        $expectedState = switch ($mode) { success { "success" } admin-skip { "skipped" } planned { "planned" } default { "failed" } }
        $expectedRc = switch ($mode) { success { 0 } admin-skip { 0 } planned { 0 } child-failure { 7 } default { 1 } }
        $rc = Invoke-Task -Id test
        if ($rc -ne $expectedRc -or $script:TaskStatus.test -ne $expectedState) { throw "Incorrect outcome for $mode." }
        if ($script:TaskDuration.test -notmatch '^\d+\.\d{5}$') { throw "Missing duration for $mode." }
        $shouldStart = $mode -in @("success", "child-failure")
        if ((Test-Path -LiteralPath $childMarker) -ne $shouldStart) { throw "Child-start invariant failed for $mode." }
        if (Test-Path -LiteralPath (Join-Path $runRoot "test.log")) {
            $durations = @(Get-Content -LiteralPath (Join-Path $runRoot "test.log") | Where-Object { $_ -like "Duration seconds:*" })
            if ($durations.Count -ne 1 -or $durations[0] -ne "Duration seconds: $($script:TaskDuration.test)") { throw "Log timing mismatch for $mode." }
        }
    }
    $shellBinary = Get-PwshCommand
    function Get-LaunchpadPersistedEnvironment {
        param($Name, $Scope)
        if ($Name -eq "Path") { return $previousPath }
        return "launchpad-refreshed-java"
    }
    function Get-TaskCommand {
        param($Id)
        $code = if ($Id -eq "handoff") { 'if ($env:JAVA_HOME -ne "launchpad-refreshed-java") { exit 9 }; Write-Output "environment-inherited"' } else { "exit 0" }
        return @{ File = $shellBinary; Args = @("-NoProfile", "-Command", $code) }
    }
    $script:TaskOrder.Clear()
    $script:Tasks.Clear()
    $script:Selected.Clear()
    $script:TaskStatus.Clear()
    Add-Task -Id setup_env -Label Install -Description "Mock"
    Add-Task -Id handoff -Label Handoff -Description "Mock" -Deps @("setup_env")
    $script:Selected.setup_env = $true
    $script:Selected.handoff = $true
    $mode = "success"
    $DryRun = $false
    $rc = Invoke-SelectedTasks
    if ($rc -ne 0 -or $script:TaskStatus.handoff -ne "success") { throw "Parent environment refresh did not reach the next child." }
    if ((Get-Content -LiteralPath (Join-Path $runRoot "handoff.log")) -notcontains "environment-inherited") { throw "Child did not verify inherited environment." }
    $env:Path = $previousPath
    function Get-TaskCommand { return @{ File = $shellBinary; Args = @("-NoProfile", "-Command", "exit 7") } }
    $script:TaskOrder.Clear()
    $script:Tasks.Clear()
    $script:TaskStatus.Clear()
    Add-Task -Id prereq -Label Prerequisite -Description "Mock" -Critical
    Add-Task -Id dependent -Label Dependent -Description "Mock" -Deps @("prereq")
    Add-Task -Id chained -Label Chained -Description "Mock" -Deps @("dependent")
    Add-Task -Id independent -Label Independent -Description "Mock"
    foreach ($id in $script:TaskOrder) { $script:Selected[$id] = $true }
    $mode = "child-failure"
    $mockExit = 7
    $DryRun = $false
    $rc = Invoke-LaunchpadRun
    $summary = Get-Content -LiteralPath (Join-Path $runRoot "summary.json") -Raw | ConvertFrom-Json
    if ($rc -ne 7 -or ($summary.tasks.status -join ",") -ne "failed,blocked,blocked,not-run") { throw "Critical failure summary is incorrect." }
    foreach ($row in $summary.tasks | Select-Object -Skip 1) {
        if ($null -ne $row.duration_seconds -or $null -ne $row.child_exit_code) { throw "Unexecuted task was timed or started." }
    }
    Add-Content -LiteralPath (Join-Path $runRoot "prereq.log") -Value @("Failed installs 0", "Error: actual failure detail")
    $details = Print-ProblemDetails 6>&1
    $detailText = $details -join "`n"
    if ($detailText -notmatch "      Error: actual failure detail" -or
        $detailText -match '(?m)^      Log file:|(?m)^      Failed installs 0') {
        throw "Problem excerpts selected metadata or a zero-failure counter."
    }
    function Write-RunSummary { throw "Mock summary write failure" }
    function Invoke-SelectedTasks { return 0 }
    $rc = Invoke-LaunchpadRun
    if ($rc -ne 1) { throw "Summary write failure reported success." }
    $script:TaskStatus.Clear()
    if (Test-TaskDependencies -Id dependent) { throw "Not-run prerequisite was accepted." }
} finally {
    $env:Path = $previousPath
    $env:JAVA_HOME = $previousJava
    $env:EBK_RESULT_FILE = $previousResult
    foreach ($name in @("test.log", "prereq.log", "setup_env.log", "handoff.log", "child-started", "summary.json")) {
        if (Test-Path -LiteralPath (Join-Path $runRoot $name)) { Remove-Item -LiteralPath (Join-Path $runRoot $name) -Force }
    }
    Remove-Item -LiteralPath $runRoot
    $global:LASTEXITCODE = 0
}
Write-EbkOk "Launchpad failure matrix and whole-run regression checks passed."
