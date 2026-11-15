$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "branding.ps1")
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "launchpad.ps1") -Raw -Encoding UTF8
foreach ($statement in [ScriptBlock]::Create($source).Ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([ScriptBlock]::Create($statement.Extent.Text))
    }
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("dev-tools-launchpad-concurrency-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$runs = New-Object System.Collections.Generic.List[string]
$processes = @()
$runParent = $testRoot
try {
    function Get-Date { return "20260101-000000" }
    $first = New-LaunchpadRunDirectory
    $second = New-LaunchpadRunDirectory
    if ($first -eq $second -or -not (Test-Path $first) -or -not (Test-Path $second)) {
        throw "Same timestamp and PID reused a run directory."
    }
    Remove-Item -LiteralPath $first, $second
    Remove-Item Function:\Get-Date
    $runParent = Join-Path $testRoot "block"
    Set-Content -LiteralPath $runParent -Value "block"
    $failed = $false
    try { New-LaunchpadRunDirectory } catch { $failed = $true }
    if (-not $failed) { throw "Run directory allocation failure was ignored." }

    foreach ($index in 1..2) {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = Get-PwshCommand
        $info.Arguments = '-NoProfile -File "' + (Join-Path $PSScriptRoot "launchpad.ps1") + '" -Profile ide-only -DryRun -Yes'
        $info.UseShellExecute = $false
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($info)
        $process.StandardInput.Close()
        $processes += @{
            Process = $process
            Output = $process.StandardOutput.ReadToEndAsync()
            Error = $process.StandardError.ReadToEndAsync()
        }
    }
    foreach ($entry in $processes) {
        if (-not $entry.Process.WaitForExit(15000)) { throw "Concurrent dry-run hung." }
        if ($entry.Process.ExitCode -ne 0) { throw "Concurrent dry-run failed: $($entry.Error.Result)" }
        $text = $entry.Output.Result
        $match = [regex]::Match($text, '(?m)^Logs: (.+)\r?$')
        if (-not $match.Success) { throw "Run plan has no reserved log directory." }
        $run = $match.Groups[1].Value.Trim()
        [void]$runs.Add($run)
        if ($text -notmatch [regex]::Escape("  Logs:    $run")) { throw "Summary log directory differs from plan." }
        $rows = [regex]::Matches($text, '(?m)^  (vscode_setup|intellij_setup|pycharm_setup)\s+planned\s+-\s+([0-9]+\.[0-9]{5})\s+(.+)\r?$')
        if ($rows.Count -ne 3) { throw "Concurrent dry-run has incomplete task rows." }
        foreach ($row in $rows) {
            $log = Join-Path $run ($row.Groups[1].Value + ".log")
            $durations = @(Get-Content -LiteralPath $log | Where-Object { $_ -like "Duration seconds:*" })
            if ($durations.Count -ne 1 -or $durations[0] -ne "Duration seconds: $($row.Groups[2].Value)") {
                throw "Concurrent task log is incomplete or differs from its summary."
            }
        }
    }
    if ($runs.Count -ne 2 -or $runs[0] -eq $runs[1]) { throw "Concurrent runs shared a log directory." }
} finally {
    foreach ($entry in $processes) {
        if (-not $entry.Process.HasExited) { $entry.Process.Kill(); $entry.Process.WaitForExit() }
        $entry.Process.Dispose()
    }
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $expectedParent = [IO.Path]::GetFullPath((Join-Path $repoRoot ".run/launchpad/windows"))
    foreach ($run in $runs) {
        if ([IO.Path]::GetDirectoryName($run) -ne $expectedParent) { throw "Unexpected cleanup directory: $run" }
        foreach ($id in @("vscode_setup", "intellij_setup", "pycharm_setup")) {
            Remove-Item -LiteralPath (Join-Path $run "$id.log") -Force
        }
        Remove-Item -LiteralPath (Join-Path $run "summary.json") -Force
        Remove-Item -LiteralPath $run
    }
    Remove-Item -LiteralPath (Join-Path $testRoot "block") -Force
    Remove-Item -LiteralPath $testRoot
}
Write-EbkOk "Launchpad unique-directory and concurrent dry-run checks passed."
