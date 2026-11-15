$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "branding.ps1")
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "launchpad.ps1") -Raw
foreach ($statement in [ScriptBlock]::Create($source).Ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([ScriptBlock]::Create($statement.Extent.Text))
    }
}
$script:TaskOrder = New-Object System.Collections.Generic.List[string]
$script:Tasks = @{}
$script:Selected = @{ intellij_setup = $true; pending = $true }
$script:TaskStatus = @{}
$script:TaskExit = @{}
$script:TaskLog = @{}
$script:TaskDuration = @{}
$script:TaskChildExit = @{}
$script:TaskBlockReason = @{}
Register-Tasks
$script:TaskOrder.Clear()
$script:TaskOrder.Add("intellij_setup")
$script:TaskOrder.Add("pending")
$runRoot = Join-Path ([IO.Path]::GetTempPath()) ("dev-tools-results-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $runRoot | Out-Null
$DryRun = $false
$previousResult = $env:EBK_RESULT_FILE
$scriptDir = $PSScriptRoot
function Resolve-AdminScope { return 0 }
function Check-TaskReady { return $true }
function Get-TaskCommand {
    $helper = (Join-Path $PSScriptRoot "branding.ps1").Replace("'", "''")
    $code = ". '$helper'; if ('$mockState' -ne 'absent') { Write-EbkTaskResult -Status '$mockState' -FailedInstalls $mockFailed }; Write-Output 'Status COMPLETED WITH ISSUES'; Write-Output 'Failed installs 0'; exit $mockRc"
    return @{ File = Get-PwshCommand; Args = @("-NoProfile", "-Command", $code) }
}
try {
    foreach ($mockState in @("success", "issues", "skipped", "failed", "absent")) {
        $mockFailed = 0
        $mockRc = 0
        $expected = "success"
        $expectedRc = 0
        switch ($mockState) {
            issues { $mockRc = 1; $expected = "issues" }
            skipped { $mockRc = 75; $expected = "skipped" }
            failed { $mockRc = 1; $mockFailed = 2; $expected = "failed"; $expectedRc = 1 }
            absent { $mockRc = 1; $expected = "failed"; $expectedRc = 1 }
        }
        $rc = Invoke-Task -Id intellij_setup
        if ($rc -ne $expectedRc -or $script:TaskStatus.intellij_setup -ne $expected -or $script:TaskChildExit.intellij_setup -ne $mockRc) {
            throw "Incorrect structured outcome for $mockState."
        }
        if ($env:EBK_RESULT_FILE -ne $previousResult) { throw "Result environment leaked." }
    }
    $file = Join-Path $runRoot "intellij_setup.result.json"
    foreach ($invalid in @(
        '{"schema_version":2,"status":"success","failed_installs":0}',
        '{"schema_version":1,"status":"issues","failed_installs":1}',
        '{"schema_version":"1","status":"success","failed_installs":0}',
        '{"schema_version":1,"status":"success","failed_installs":"0"}',
        '{"schema_version":true,"status":"success","failed_installs":0}',
        'not-json'
    )) {
        [IO.File]::WriteAllText($file, $invalid)
        $failed = $false
        try { Read-ChildResult -File $file -ExitCode 1 } catch { $failed = $true }
        if (-not $failed) { throw "Invalid result was accepted: $invalid" }
    }
    $env:EBK_RESULT_FILE = $file
    Write-EbkTaskResult -Status failed -FailedInstalls 1
    $failed = $false
    try { Read-ChildResult -File $file -ExitCode 0 } catch { $failed = $true }
    if (-not $failed) { throw "Contradictory success exit code was accepted." }
    foreach ($scriptName in @("intellij_setup.ps1", "pycharm_setup.ps1")) {
        $childSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot $scriptName) -Raw
        $resultBlock = [regex]::Match($childSource, '(?s)\$resultState = if .*?Write-EbkTaskResult[^\r\n]+').Value
        if (-not $resultBlock) { throw "Child script is not wired to structured results: $scriptName" }
        foreach ($failCount in @(0, 2)) {
            $overallStatus = "COMPLETED WITH ISSUES"
            . ([ScriptBlock]::Create($resultBlock))
            $state = Read-ChildResult -File $file -ExitCode 1
            $expectedState = if ($failCount -eq 0) { "issues" } else { "failed" }
            if ($state -ne $expectedState) { throw "Child result wiring is incorrect: $scriptName" }
        }
    }
    $script:RunDuration = "1.23456"
    Write-RunSummary
    $summary = Get-Content -LiteralPath (Join-Path $runRoot "summary.json") -Raw | ConvertFrom-Json
    if ($summary.schema_version -ne 1 -or $summary.duration_seconds -ne 1.23456 -or $summary.tasks.Count -ne 2 -or
        $summary.tasks[0].status -ne "failed" -or $summary.tasks[0].exit_code -ne 1 -or
        $summary.tasks[0].child_exit_code -ne 1 -or $summary.tasks[0].duration_seconds -le 0 -or
        $summary.tasks[1].status -ne "not-run" -or $null -ne $summary.tasks[1].duration_seconds) {
        throw "JSON summary differs from task state."
    }
} finally {
    $env:EBK_RESULT_FILE = $previousResult
    foreach ($name in @("intellij_setup.log", "intellij_setup.result.json", "summary.json")) {
        Remove-Item -LiteralPath (Join-Path $runRoot $name) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $runRoot
}
Write-EbkOk "Launchpad structured-result and JSON summary checks passed."
$global:LASTEXITCODE = 0
