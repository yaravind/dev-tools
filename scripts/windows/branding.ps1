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

function Test-EbkUnicodeOutput {
    if ($env:EBK_ASCII -eq "1") {
        return $false
    }
    if ($env:EBK_FORCE_UNICODE -eq "1") {
        return $true
    }

    try {
        return ([Console]::OutputEncoding.WebName -eq "utf-8")
    } catch {
        return $false
    }
}

function Get-EbkGlyphs {
    if (Test-EbkUnicodeOutput) {
        return @{
            Phase = [string][char]0x25C6
            Info = [string][char]0x2139
            Ok = [string][char]0x2713
            Warn = [string][char]0x26A0
            Error = [string][char]0x2716
            Debug = [string][char]0x2022
        }
    }

    return @{
        Phase = ""
        Info = ""
        Ok = ""
        Warn = ""
        Error = ""
        Debug = ""
    }
}

function Format-EbkLogLine {
    param(
        [string]$Glyph,
        [string]$Label,
        [string]$Message
    )

    if ([string]::IsNullOrEmpty($Glyph)) {
        return ("{0,-7} {1}" -f $Label, $Message)
    }

    return ("{0} {1,-5} {2}" -f $Glyph, $Label, $Message)
}

function Write-EbkPhase {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-Host ""
    Write-Host (Format-EbkLogLine -Glyph $glyphs.Phase -Label "PHASE" -Message $Message) -ForegroundColor $script:EbPhase
}

function Write-EbkInfo {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-Host (Format-EbkLogLine -Glyph $glyphs.Info -Label "INFO" -Message $Message) -ForegroundColor $script:EbInfo
}

function Write-EbkOk {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-Host (Format-EbkLogLine -Glyph $glyphs.Ok -Label "OK" -Message $Message) -ForegroundColor $script:EbOk
}

function Write-EbkWarn {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-Host (Format-EbkLogLine -Glyph $glyphs.Warn -Label "WARN" -Message $Message) -ForegroundColor $script:EbWarn
}

function Write-EbkError {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-Host (Format-EbkLogLine -Glyph $glyphs.Error -Label "ERROR" -Message $Message) -ForegroundColor $script:EbError
}

function Write-EbkDebug {
    param([string]$Message)
    if ($env:EBK_DEBUG -ne "1") { return }
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-Host (Format-EbkLogLine -Glyph $glyphs.Debug -Label "DEBUG" -Message $Message) -ForegroundColor $script:EbDebug
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
    $tagline = "Works after coffee."
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
    $taglineLine = "| " + $tagline.PadRight($contentWidth) + " |"
    Write-Host $taglineLine -ForegroundColor $script:EbText
    Write-Host $border -ForegroundColor $script:EbPrimary
    Write-EbkInfo ("{0} ({1} mode)" -f $ScriptName, $selectedTheme)
}
