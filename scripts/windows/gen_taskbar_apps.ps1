# Requires -Version 5.1

function Write-Step($msg) {
    Write-Host "===> $msg" -ForegroundColor Magenta
}
function Write-Info($msg) {
    Write-Host "===> $msg" -ForegroundColor Cyan
}
function Write-Ok($msg) {
    Write-Host "===> $msg" -ForegroundColor Green
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path $scriptDir '../../config/taskbar_apps.txt'

Write-Step "Enumerating current Taskbar pinned apps..."

# Get all pinned taskbar items (using Win32 API via Shell.Application)
$shell = New-Object -ComObject Shell.Application
$taskbarFolder = $shell.Namespace(0x1F3F) # Taskbar pinned folder
$pinnedItems = @()
if ($taskbarFolder) {
    foreach ($item in $taskbarFolder.Items()) {
        $pinnedItems += $item.Path
    }
} else {
    Write-Info "Could not access Taskbar pinned folder via Shell.Application. Falling back to StartLayout export."
    # Export StartLayout XML and parse for taskbar pins
    $layoutFile = Join-Path $env:TEMP "StartLayout.xml"
    Export-StartLayout -Path $layoutFile -As XML
    $xml = [xml](Get-Content $layoutFile)
    $pinnedItems = $xml.LayoutModificationTemplate.DefaultLayoutOverride.LayoutOptions.Group.Group | Where-Object { $_.Type -eq 'Taskbar' } | ForEach-Object { $_.DesktopApplicationID }
}

Write-Step "Writing pinned apps to $configPath ..."

@(
    '# Taskbar apps list (Windows)',
    '# - One entry per line',
    '# - Lines starting with "--" remove pinned items',
    '# - Blank lines and comments are ignored',
    '# - "SPACER" is not supported on Windows Taskbar (will be skipped)',
    '# - Use AUMID entries for Microsoft Store apps: AUMID:Microsoft.WindowsTerminal_8wekyb3d8bbwe!App',
    ''
) | Set-Content -Path $configPath

foreach ($app in $pinnedItems) {
    if ($app) {
        Add-Content -Path $configPath -Value $app
    }
}

Write-Ok "Done. Pinned Taskbar apps exported to $configPath"

