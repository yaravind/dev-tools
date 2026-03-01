# Requires -Version 5.1

function Write-Step($msg) {
    Write-Host "===> $msg" -ForegroundColor Magenta
}
function Write-Ok($msg) {
    Write-Host "===> $msg" -ForegroundColor Green
}
function Write-Info($msg) {
    Write-Host "===> $msg" -ForegroundColor Cyan
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

