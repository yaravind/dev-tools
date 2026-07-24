# Requires -Version 5.1

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

Write-Step "Type in your first and last name (no accent or special characters - e.g. 'c'): "
$full_name = Read-Host

Write-Step "Type in your email address (the one used for your GitHub account): "
$email = Read-Host

Write-Info "Setting global git config user.email..."
git config --global user.email "$email"
Write-Info "Setting global git config user.name..."
git config --global user.name "$full_name"

Write-Ok "Awesome, all set."
