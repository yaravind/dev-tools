# run_vscode_setup.ps1 - minimal runner for VS Code extension setup

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

Set-ExecutionPolicy Bypass -Scope Process -Force
& "$PSScriptRoot\vscode_setup.ps1" -Yes
