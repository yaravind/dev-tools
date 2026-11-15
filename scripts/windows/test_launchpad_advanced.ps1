$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "branding.ps1")
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "launchpad.ps1") -Raw -Encoding UTF8
foreach ($statement in [ScriptBlock]::Create($source).Ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([ScriptBlock]::Create($statement.Extent.Text))
    }
}
function Assert-Advanced {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("dev-tools-advanced-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:TaskChildExit = @{}
$writerFactory = (Get-Command New-TaskLogWriter).ScriptBlock
$renderLine = (Get-Command Write-LaunchpadOutputLine).ScriptBlock
$previousColor = $env:EBK_FORCE_COLOR
$previousOutputEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $script:WriterCount = 0
    $script:RenderedCount = 0
    function New-TaskLogWriter {
        param([string]$LogFile)
        $script:WriterCount++
        $script:LastWriter = & $writerFactory -LogFile $LogFile
        return $script:LastWriter
    }
    function Add-Content { throw "Streaming must not use per-line Add-Content." }
    function Write-LaunchpadOutputLine { param($Line) $script:RenderedCount++ }
    $env:EBK_FORCE_COLOR = "original"
    $command = @{
        File = Get-PwshCommand
        Args = @("-NoProfile", "-Command", '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); 1..3000 | ForEach-Object { "line-$_-$([char]0x2713)" }; exit 7')
    }
    $log = Join-Path $testRoot "stream.log"
    $rc = Invoke-ChildTask -Id test -Command $command -LogFile $log
    $lines = [IO.File]::ReadAllLines($log, [Text.Encoding]::UTF8)
    Assert-Advanced ($rc -eq 7 -and $script:TaskChildExit.test -eq 7) "Streaming lost child exit code."
    Assert-Advanced ($script:WriterCount -eq 1 -and $script:RenderedCount -eq 3000 -and $lines.Count -eq 3000) "Streaming writer or output count is incorrect."
    foreach ($index in 1..3000) {
        Assert-Advanced ($lines[$index - 1] -eq "line-$index-$([char]0x2713)") "Streaming corrupted UTF-8 line $index."
    }
    Assert-Advanced ($env:EBK_FORCE_COLOR -eq "original") "Streaming leaked color state."
    function Write-LaunchpadOutputLine { throw "Mock renderer failure" }
    $failed = $false
    try { Invoke-ChildTask -Id test -Command $command -LogFile $log } catch { $failed = $true }
    Assert-Advanced $failed "Renderer failure must propagate."
    Assert-Advanced ($env:EBK_FORCE_COLOR -eq "original") "Failure leaked color state."
    $disposed = $false
    try { $script:LastWriter.WriteLine("must fail") } catch [ObjectDisposedException] { $disposed = $true }
    Assert-Advanced $disposed "Writer was not disposed on failure."
    $failed = $false
    try { Invoke-ChildTask -Id test -Command $command -LogFile (Join-Path $testRoot "missing/log") } catch { $failed = $true }
    Assert-Advanced $failed "Invalid log path must fail explicitly."
} finally {
    $env:EBK_FORCE_COLOR = $previousColor
    [Console]::OutputEncoding = $previousOutputEncoding
    Remove-Item Function:\Add-Content
    Set-Item Function:New-TaskLogWriter $writerFactory
    Set-Item Function:Write-LaunchpadOutputLine $renderLine
    Remove-Item -LiteralPath (Join-Path $testRoot "stream.log") -Force
    Remove-Item -LiteralPath $testRoot
}
Write-EbkOk "Launchpad streaming regression checks passed."

$script:TaskOrder = @("backup_codex")
$script:Selected = @{ backup_codex = $true }
$script:TaskCommands = @{}
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$CodexBackupTarget = ""
$dateCalls = 0
function Get-Date {
    param($Format)
    $script:dateCalls++
    return "20260101-00000$script:dateCalls"
}
Freeze-TaskCommands
$planned = Get-ResolvedTaskCommand -Id backup_codex
$plannedText = Format-Command -Command $planned
$executed = Get-ResolvedTaskCommand -Id backup_codex
Assert-Advanced ($dateCalls -eq 1 -and (Format-Command -Command $executed) -eq $plannedText) "Generated backup destination changed after planning."
Remove-Item Function:\Get-Date
$arguments = @("", "path with spaces", "single'quote", 'double"quote', '$literal', "line`nbreak")
$formatted = Format-Command -Command @{ File = "fake-command"; Args = $arguments }
$parsed = [ScriptBlock]::Create($formatted).Ast.EndBlock.Statements[0].PipelineElements[0].CommandElements
Assert-Advanced ($parsed.Count -eq $arguments.Count + 1) "Display changed argument count."
foreach ($index in 0..($arguments.Count - 1)) {
    Assert-Advanced ($parsed[$index + 1].Value -ceq $arguments[$index]) "PowerShell quoting changed argument $index."
}
Write-EbkOk "Launchpad frozen-command and quoting regression checks passed."
