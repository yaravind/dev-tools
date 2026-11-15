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
