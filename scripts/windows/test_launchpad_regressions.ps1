$ErrorActionPreference = "Stop"
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "launchpad.ps1") -Raw
. (Join-Path $PSScriptRoot "branding.ps1")
$ast = [ScriptBlock]::Create($source).Ast
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([ScriptBlock]::Create($statement.Extent.Text))
    }
}

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
    Remove-Item -LiteralPath (Join-Path $testRoot "logs/vscode_setup.log"), (Join-Path $testRoot "block") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $testRoot "logs"), $testRoot -Force
}
Write-EbkOk "Launchpad infrastructure regression checks passed."
