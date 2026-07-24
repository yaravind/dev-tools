# Shared CLI branding for dev-tools / Engineer Bootstrap Kit.

function Get-EbkTheme {
    param(
        [ValidateSet("Auto","Dark","Light")]
        [string]$Theme = "Auto"
    )

    if ($Theme -ne "Auto") {
        return $Theme.ToLowerInvariant()
    }

    if ($env:EBK_THEME) {
        $envTheme = $env:EBK_THEME.Trim().ToLowerInvariant()
        if ($envTheme -in @("dark","light")) {
            return $envTheme
        }
    }

    try {
        $bg = $Host.UI.RawUI.BackgroundColor
        if ($bg -in @("White","Gray")) {
            return "light"
        }
    } catch {
        # Keep default dark when host does not expose background color.
    }

    return "dark"
}

function Set-EbkPalette {
    param(
        [ValidateSet("dark","light")]
        [string]$Theme
    )

    if ($Theme -eq "light") {
        $script:EbPrimary = "Magenta"
        $script:EbAccent = "Green"
        $script:EbText = "Black"
        $script:EbMuted = "DarkGray"
        $script:EbPhase = $script:EbPrimary
        $script:EbInfo = "Blue"
        $script:EbOk = $script:EbAccent
        $script:EbWarn = "DarkYellow"
        $script:EbError = "Red"
        $script:EbDebug = $script:EbMuted
    } else {
        $script:EbPrimary = "DarkMagenta"
        $script:EbAccent = "Green"
        $script:EbText = "Gray"
        $script:EbMuted = "Cyan"
        $script:EbPhase = "Magenta"
        $script:EbInfo = "Cyan"
        $script:EbOk = $script:EbAccent
        $script:EbWarn = "Yellow"
        $script:EbError = "Red"
        $script:EbDebug = $script:EbMuted
    }
}

function Initialize-EbkPaletteIfNeeded {
    if (-not $script:EbPhase -or -not $script:EbInfo -or -not $script:EbOk) {
        $theme = Get-EbkTheme
        Set-EbkPalette -Theme $theme
    }
}

function Write-EbkPhase {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    Write-Host ""
    Write-Host "◆ PHASE $Message" -ForegroundColor $script:EbPhase
}

function Write-EbkInfo {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    Write-Host "ℹ INFO  $Message" -ForegroundColor $script:EbInfo
}

function Write-EbkOk {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    Write-Host "✓ OK    $Message" -ForegroundColor $script:EbOk
}

function Write-EbkWarn {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    Write-Host "⚠ WARN  $Message" -ForegroundColor $script:EbWarn
}

function Write-EbkError {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    Write-Host "✖ ERROR $Message" -ForegroundColor $script:EbError
}

function Write-EbkDebug {
    param([string]$Message)
    if ($env:EBK_DEBUG -ne "1") { return }
    Initialize-EbkPaletteIfNeeded
    Write-Host "• DEBUG $Message" -ForegroundColor $script:EbDebug
}

# Backward-compatible aliases used by existing scripts.
function Write-Step { param([string]$Message) ; Write-EbkPhase $Message }
function Write-Info { param([string]$Message) ; Write-EbkInfo $Message }
function Write-Ok { param([string]$Message) ; Write-EbkOk $Message }
function Write-Warn { param([string]$Message) ; Write-EbkWarn $Message }
function Write-Err { param([string]$Message) ; Write-EbkError $Message }
function Write-DebugLog { param([string]$Message) ; Write-EbkDebug $Message }

function Show-EbkBanner {
    param(
        [string]$ScriptName = "",
        [ValidateSet("Auto","Dark","Light")]
        [string]$Theme = "Auto"
    )

    if ([string]::IsNullOrWhiteSpace($ScriptName)) {
        if ($MyInvocation.ScriptName) {
            $ScriptName = [System.IO.Path]::GetFileName($MyInvocation.ScriptName)
        } else {
            $ScriptName = "script"
        }
    }

    $selectedTheme = Get-EbkTheme -Theme $Theme
    Set-EbkPalette -Theme $selectedTheme
    $contentWidth = 60
    $tagline = "Works on my machine. And yours."
    $border = "+" + ("-" * ($contentWidth + 2)) + "+"
    $artLines = @(
        '     _                 _              _     ',
        '  __| | _____   __    | |_ ___   ___ | |___ ',
        ' / _` |/ _ \ \ / /____| __/ _ \ / _ \| / __|',
        '| (_| |  __/\ V /_____| || (_) | (_) | \__ \',
        ' \__,_|\___| \_/       \__\___/ \___/|_|___/'
    )

    Write-Host ""
    Write-Host $border -ForegroundColor $script:EbPrimary
    foreach ($line in $artLines) {
        $artLine = "| " + $line.PadRight($contentWidth) + " |"
        Write-Host $artLine -ForegroundColor $script:EbAccent
    }
    if ($Host.UI.SupportsVirtualTerminal) {
        $esc = [char]27
        $taglineLine = "| " + $esc + "[1m" + $tagline.PadRight($contentWidth) + $esc + "[0m |"
        Write-Host $taglineLine -ForegroundColor $script:EbText
    } else {
        $taglineLine = "| " + $tagline.PadRight($contentWidth) + " |"
        Write-Host $taglineLine -ForegroundColor $script:EbText
    }
    Write-Host $border -ForegroundColor $script:EbPrimary
    Write-EbkInfo ("{0} ({1} mode)" -f $ScriptName, $selectedTheme)
}
