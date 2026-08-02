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

    $esc = [char]27
    $script:EbReset = "$esc[0m"

    if ($Theme -eq "light") {
        $script:EbPrimaryAnsi = "$esc[0;35m"
        $script:EbAccentAnsi = "$esc[0;32m"
        $script:EbTextAnsi = ""
        $script:EbMutedAnsi = "$esc[0;90m"
        $script:EbBoldAnsi = "$esc[1m"
        $script:EbPhaseAnsi = $script:EbPrimaryAnsi
        $script:EbInfoAnsi = "$esc[0;34m"
        $script:EbOkAnsi = $script:EbAccentAnsi
        $script:EbWarnAnsi = "$esc[0;33m"
        $script:EbErrorAnsi = "$esc[0;31m"
        $script:EbDebugAnsi = $script:EbMutedAnsi
        $script:EbPrimary = "Magenta"
        $script:EbAccent = "Green"
        $script:EbText = "Black"
        $script:EbMuted = "DarkGray"
        $script:EbPhase = $script:EbPrimary
        $script:EbInfo = "Blue"
        $script:EbOk = $script:EbAccent
        $script:EbWarn = "Yellow"
        $script:EbError = "Red"
        $script:EbDebug = $script:EbMuted
    } else {
        $script:EbPrimaryAnsi = "$esc[1;35m"
        $script:EbAccentAnsi = "$esc[1;32m"
        $script:EbTextAnsi = ""
        $script:EbMutedAnsi = "$esc[0;36m"
        $script:EbBoldAnsi = "$esc[1m"
        $script:EbPhaseAnsi = $script:EbPrimaryAnsi
        $script:EbInfoAnsi = "$esc[1;36m"
        $script:EbOkAnsi = $script:EbAccentAnsi
        $script:EbWarnAnsi = "$esc[1;33m"
        $script:EbErrorAnsi = "$esc[1;31m"
        $script:EbDebugAnsi = $script:EbMutedAnsi
        $script:EbPrimary = "Magenta"
        $script:EbAccent = "Green"
        $script:EbText = "White"
        $script:EbMuted = "Cyan"
        $script:EbPhase = "Magenta"
        $script:EbInfo = "Cyan"
        $script:EbOk = $script:EbAccent
        $script:EbWarn = "Yellow"
        $script:EbError = "Red"
        $script:EbDebug = $script:EbMuted
    }
}

function Test-EbkColorOutput {
    if ($env:NO_COLOR) {
        return $false
    }
    if ($env:EBK_FORCE_COLOR -eq "1") {
        return $true
    }

    try {
        return -not [Console]::IsOutputRedirected
    } catch {
        return $true
    }
}

function Enable-EbkAnsiOutputRendering {
    if (Get-Variable -Name PSStyle -Scope Global -ErrorAction SilentlyContinue) {
        try {
            $global:PSStyle.OutputRendering = "Ansi"
        } catch {
            # Older hosts may expose PSStyle without a writable OutputRendering property.
        }
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

function Format-EbkLogPrefix {
    param(
        [string]$Glyph,
        [string]$Label
    )

    if ([string]::IsNullOrEmpty($Glyph)) {
        return ("{0,-7} " -f $Label)
    }

    return ("{0} {1,-5} " -f $Glyph, $Label)
}

function Format-EbkAnsi {
    param(
        [string]$Color,
        [string]$Text,
        [string]$Weight = ""
    )

    if (-not (Test-EbkColorOutput)) {
        return $Text
    }

    Enable-EbkAnsiOutputRendering
    return ("{0}{1}{2}{3}" -f $Color, $Weight, $Text, $script:EbReset)
}

function Format-EbkAnsiLogLine {
    param(
        [string]$Color,
        [string]$Glyph,
        [string]$Label,
        [string]$Message
    )

    if (-not (Test-EbkColorOutput)) {
        return (Format-EbkLogLine -Glyph $Glyph -Label $Label -Message $Message)
    }

    Enable-EbkAnsiOutputRendering
    return ("{0}{1}{2}{3}" -f $Color, (Format-EbkLogPrefix -Glyph $Glyph -Label $Label), $script:EbReset, $Message)
}

function Write-EbkLogLine {
    param(
        [string]$Color,
        [string]$Glyph,
        [string]$Label,
        [string]$Message,
        [switch]$ErrorStream
    )

    $line = Format-EbkAnsiLogLine -Color $Color -Glyph $Glyph -Label $Label -Message $Message
    if ($ErrorStream) {
        [Console]::Error.WriteLine($line)
    } else {
        Write-EbkStdout $line
    }
}

function Write-EbkStdout {
    param([string]$Text)

    if ((Test-EbkColorOutput) -and $env:EBK_FORCE_COLOR -eq "1") {
        try {
            if ([Console]::IsOutputRedirected) {
                [Console]::Out.WriteLine($Text)
                return
            }
        } catch {
            # Fall back to PowerShell pipeline output.
        }
    }

    Write-Host $Text
}

function Write-EbkThemedHost {
    param(
        [string]$Text,
        [string]$Color = "",
        [string]$Weight = ""
    )

    Write-EbkStdout (Format-EbkAnsi -Color $Color -Text $Text -Weight $Weight)
}

function Write-EbkBoxLine {
    param(
        [int]$BoxWidth,
        [string]$Line,
        [string]$Color,
        [string]$Weight = ""
    )

    $padded = $Line.PadRight($BoxWidth)
    if (-not (Test-EbkColorOutput)) {
        Write-EbkStdout ("| {0} |" -f $padded)
        return
    }

    Enable-EbkAnsiOutputRendering
    Write-EbkStdout ($script:EbPrimaryAnsi + "| " + $Color + $Weight + $padded + " " + $script:EbPrimaryAnsi + "|" + $script:EbReset)
}

function Write-EbkPhase {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-EbkStdout ""
    Write-EbkLogLine -Color $script:EbPhaseAnsi -Glyph $glyphs.Phase -Label "PHASE" -Message $Message
}

function Write-EbkInfo {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-EbkLogLine -Color $script:EbInfoAnsi -Glyph $glyphs.Info -Label "INFO" -Message $Message
}

function Write-EbkOk {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-EbkLogLine -Color $script:EbOkAnsi -Glyph $glyphs.Ok -Label "OK" -Message $Message
}

function Write-EbkWarn {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-EbkLogLine -Color $script:EbWarnAnsi -Glyph $glyphs.Warn -Label "WARN" -Message $Message
}

function Write-EbkError {
    param([string]$Message)
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-EbkLogLine -Color $script:EbErrorAnsi -Glyph $glyphs.Error -Label "ERROR" -Message $Message -ErrorStream
}

function Write-EbkDebug {
    param([string]$Message)
    if ($env:EBK_DEBUG -ne "1") { return }
    Initialize-EbkPaletteIfNeeded
    $glyphs = Get-EbkGlyphs
    Write-EbkLogLine -Color $script:EbDebugAnsi -Glyph $glyphs.Debug -Label "DEBUG" -Message $Message
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

    Write-EbkThemedHost -Text $border -Color $script:EbPrimaryAnsi
    foreach ($line in $artLines) {
        Write-EbkBoxLine -BoxWidth $contentWidth -Line $line -Color $script:EbAccentAnsi
    }
    Write-EbkBoxLine -BoxWidth $contentWidth -Line $tagline -Color $script:EbTextAnsi -Weight $script:EbBoldAnsi
    Write-EbkThemedHost -Text $border -Color $script:EbPrimaryAnsi
    $glyphs = Get-EbkGlyphs
    $bannerMessage = "{0} ({1} mode)" -f $ScriptName, $selectedTheme
    if (Test-EbkColorOutput) {
        Enable-EbkAnsiOutputRendering
        Write-EbkStdout ($script:EbInfoAnsi + (Format-EbkLogPrefix -Glyph $glyphs.Info -Label "INFO") + $script:EbReset + $bannerMessage + $script:EbReset)
    } else {
        Write-EbkStdout (Format-EbkLogLine -Glyph $glyphs.Info -Label "INFO" -Message $bannerMessage)
    }
}
