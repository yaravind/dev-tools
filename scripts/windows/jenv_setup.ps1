# jenv_setup.ps1 - Discover installed JDKs and register them with JEnv-for-Windows
#
# Usage:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\windows\jenv_setup.ps1
#   .\scripts\windows\jenv_setup.ps1 -GlobalVersion 17.0.12
#   .\scripts\windows\jenv_setup.ps1 -DryRun -Yes

# Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$GlobalVersion,
    [switch]$Yes,
    [switch]$DryRun
)

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$script:ScriptStart = Get-Date
$script:FailCount = 0
$script:AddedCount = 0
$script:DiscoveredCount = 0
$script:SelectedVersion = ""
$script:InstallAttempted = 0

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Record-Failure {
    param([string]$Message)
    Write-EbkError $Message
    $script:FailCount++
}

function Refresh-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @($env:Path, $machinePath, $userPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $env:Path = ($parts -join ";")
}

function Install-JEnv {
    Write-Step "DISCOVER Checking for JEnv-for-Windows"

    if (Test-CommandExists "jenv") {
        Write-Ok "jenv is already installed."
        return $true
    }

    $script:InstallAttempted = 1
    $installerUrls = @(
        "https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/jenv.ps1",
        "https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/bin/jenv.ps1"
    )

    if ($DryRun) {
        foreach ($url in $installerUrls) {
            Write-Info "DryRun: would try JEnv-for-Windows installer: $url"
        }
        return $true
    }

    foreach ($url in $installerUrls) {
        try {
            Write-Info "Fetching installer: $url"
            $installer = Invoke-WebRequest -UseBasicParsing -Uri $url -ErrorAction Stop
            Invoke-Expression $installer.Content
            Refresh-SessionPath
            if (Test-CommandExists "jenv") {
                Write-Ok "JEnv-for-Windows installed successfully."
                return $true
            }
            Write-Warn "Installer completed but jenv was not found in PATH yet."
        } catch {
            Write-Warn "Could not install JEnv-for-Windows from $url. $_"
        }
    }

    Record-Failure "JEnv-for-Windows installer could not be completed. Install manually and rerun this script."
    return $false
}

function Get-InstalledJdks {
    $searchPaths = @(
        "C:\Program Files\Microsoft\jdk-*",
        "C:\Program Files\Eclipse Adoptium\jdk-*",
        "C:\Program Files\Java\jdk-*",
        "C:\Program Files\BellSoft\LibericaJDK-*"
    )

    $jdks = @()
    foreach ($pattern in $searchPaths) {
        $found = Get-Item -Path $pattern -ErrorAction SilentlyContinue
        if ($found) {
            $jdks += $found
        }
    }

    return @($jdks | Sort-Object FullName -Unique)
}

function Add-JdkToJenv {
    param([string]$JdkPath)

    if (-not (Test-Path -LiteralPath $JdkPath)) {
        Record-Failure "JDK path does not exist or is not a directory: $JdkPath"
        return
    }

    if ($DryRun) {
        Write-Info "DryRun: would run jenv add -path `"$JdkPath`""
        $script:AddedCount++
        return
    }

    Write-Info "Processing JDK: $JdkPath"
    jenv add -path "$JdkPath"
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Successfully added: $JdkPath"
        $script:AddedCount++
    } else {
        Record-Failure "Failed to add: $JdkPath (exit code: $LASTEXITCODE)"
    }
}

function Get-ManagedJenvVersions {
    if ($DryRun -or -not (Test-CommandExists "jenv")) {
        return @()
    }

    $output = @(jenv list 2>$null)
    $versions = New-Object System.Collections.Generic.List[string]
    foreach ($line in $output) {
        $value = ($line -replace '^[\*\s]+', '').Trim()
        if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '^Available') {
            [void]$versions.Add($value)
        }
    }
    return @($versions)
}

function Select-GlobalVersion {
    $versions = Get-ManagedJenvVersions

    if ($DryRun) {
        if ($GlobalVersion) {
            Write-Info "DryRun: would validate and use global Java version: $GlobalVersion"
            $script:SelectedVersion = $GlobalVersion
        } else {
            Write-Info "DryRun: would prompt for global Java version after listing jenv versions."
        }
        return
    }

    Write-Step "DISCOVER Available Java versions managed by jenv"
    jenv list

    if ($GlobalVersion) {
        if ($versions -contains $GlobalVersion) {
            $script:SelectedVersion = $GlobalVersion
        } else {
            Record-Failure "Version '$GlobalVersion' is not managed by jenv. Choose one from the list above."
            return
        }
    } elseif ($Yes -or -not [Environment]::UserInteractive) {
        Write-Warn "No -GlobalVersion provided in non-interactive mode; skipping global Java version selection."
        return
    } else {
        while ($true) {
            $entered = Read-Host "Choose the version (from above) to set as global version"
            if ([string]::IsNullOrWhiteSpace($entered)) {
                Write-Warn "No version entered."
                continue
            }
            if ($versions -contains $entered) {
                $script:SelectedVersion = $entered
                break
            }
            Write-Warn "Version '$entered' is not managed by jenv. Choose one from the list above."
        }
    }

    if (-not $script:SelectedVersion) {
        return
    }

    jenv use "$script:SelectedVersion"
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Set global Java version to $script:SelectedVersion."
    } else {
        Record-Failure "Could not switch to version '$script:SelectedVersion'. Check the version name and try: jenv use <version>."
    }
}

function Verify-JEnvState {
    Write-Step "VERIFY Verifying Java setup"

    if ($DryRun) {
        Write-Info "DryRun: would run java -version and inspect JAVA_HOME."
        return
    }

    if (Test-CommandExists "java") {
        java -version
    } else {
        Record-Failure "java is not available in PATH after jenv setup."
    }

    if ($env:JAVA_HOME) {
        Write-Ok "JAVA_HOME=$env:JAVA_HOME"
    } else {
        Write-Warn "JAVA_HOME is not set in this session. Restart PowerShell if JEnv-for-Windows changed user environment variables."
    }
}

function Format-Duration {
    param([TimeSpan]$Duration)

    if ($Duration.TotalHours -ge 1) {
        return ("{0}h {1}m {2}s" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds)
    }
    if ($Duration.TotalMinutes -ge 1) {
        return ("{0}m {1}s" -f [int]$Duration.TotalMinutes, $Duration.Seconds)
    }
    return ("{0}s" -f [int]$Duration.TotalSeconds)
}

function Print-StructuredReport {
    param([string]$StatusLabel)

    Write-Host ""
    Write-Host "Final Status Report" -ForegroundColor $script:EbPhase
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
    Write-Host ("  {0,-24} {1}" -f "Script", "JEnv Setup (Windows)")
    Write-Host ("  {0,-24} {1}" -f "Status", $StatusLabel)
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
    Write-Host ("  {0,-24} {1}" -f "Install attempted", $script:InstallAttempted)
    Write-Host ("  {0,-24} {1}" -f "JDKs discovered", $script:DiscoveredCount)
    Write-Host ("  {0,-24} {1}" -f "JDKs added", $script:AddedCount)
    Write-Host ("  {0,-24} {1}" -f "Selected version", $(if ($script:SelectedVersion) { $script:SelectedVersion } else { "not changed" }))
    Write-Host ("  {0,-24} {1}" -f "Failures", $script:FailCount)
    Write-Host ("  {0,-24} {1}" -f "Duration", (Format-Duration -Duration ((Get-Date) - $script:ScriptStart)))
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor $script:EbPhase
}

Write-Step "Starting jenv setup for Windows"

$ok = Install-JEnv

$jdks = Get-InstalledJdks
$script:DiscoveredCount = $jdks.Count
if ($jdks.Count -eq 0) {
    if ($DryRun) {
        Write-Warn "DryRun: no JDKs found in standard Windows installation directories on this host."
    } else {
        Record-Failure "No JDKs found in standard installation directories. Install a JDK first, then rerun this script."
    }
} else {
    Write-Step "CONFIGURE Adding discovered JDKs to jenv"
    foreach ($jdk in $jdks) {
        Add-JdkToJenv -JdkPath $jdk.FullName
    }
}

if ($ok -and ($DryRun -or (Test-CommandExists "jenv"))) {
    Select-GlobalVersion
    Verify-JEnvState
}

$finalStatus = "SUCCESS"
if ($script:FailCount -gt 0) {
    $finalStatus = "FAILED"
} elseif ($DryRun) {
    $finalStatus = "DRY RUN"
}

Write-Step "SUMMARY Compiling final run report"
Print-StructuredReport -StatusLabel $finalStatus

if ($script:FailCount -gt 0) {
    Write-EbkError ("Completed with {0} error(s)." -f $script:FailCount)
    exit 1
}

Write-Ok "jenv setup complete."
