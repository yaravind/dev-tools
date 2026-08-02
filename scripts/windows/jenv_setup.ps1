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

function Get-JEnvRoot {
    $command = Get-Command "jenv" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return $null
    }

    $sourcePath = $command.Source
    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        $sourcePath = $command.Path
    }
    if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath)) {
        return $null
    }

    $parent = (Get-Item -LiteralPath $sourcePath).Directory
    if (-not $parent) {
        return $null
    }

    if (Test-Path -LiteralPath (Join-Path $parent.FullName "java.bat")) {
        return $parent.FullName
    }
    if ($parent.Name -eq "src" -and $parent.Parent -and (Test-Path -LiteralPath (Join-Path $parent.Parent.FullName "java.bat"))) {
        return $parent.Parent.FullName
    }

    return $parent.FullName
}

function Add-PathToFrontForSession {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $pathParts = @($env:Path -split ";" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_.TrimEnd("\") -ine $Path.TrimEnd("\")
    })
    $env:Path = (@($Path) + $pathParts) -join ";"
}

function Initialize-JEnvProcessPath {
    Write-Step "CONFIGURE Preparing JEnv PATH for this session"

    if ($DryRun) {
        Write-Info "DryRun: would prepend JEnv-for-Windows to this process PATH before running jenv commands."
        return
    }

    $jenvRoot = Get-JEnvRoot
    if ([string]::IsNullOrWhiteSpace($jenvRoot)) {
        Write-Warn "Could not determine JEnv-for-Windows root. If JEnv prompts for PATH changes, rerun PowerShell as administrator once or put JEnv first in PATH manually."
        return
    }

    Add-PathToFrontForSession -Path $jenvRoot
    Write-Ok "JEnv-for-Windows is first in this process PATH: $jenvRoot"
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
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    function Add-JdkCandidate {
        param([string]$PathPattern)

        if ([string]::IsNullOrWhiteSpace($PathPattern)) {
            return
        }

        $expandedPath = [Environment]::ExpandEnvironmentVariables($PathPattern.Trim())
        if ([string]::IsNullOrWhiteSpace($expandedPath)) {
            return
        }

        if ($expandedPath.IndexOfAny([char[]]"*?") -ge 0) {
            Get-Item -Path $expandedPath -ErrorAction SilentlyContinue | ForEach-Object {
                [void]$candidatePaths.Add($_.FullName)
            }
            return
        }

        $resolvedPath = Resolve-Path -LiteralPath $expandedPath -ErrorAction SilentlyContinue
        if ($resolvedPath) {
            [void]$candidatePaths.Add($resolvedPath.Path)
        }
    }

    function Add-RegistryJdkCandidates {
        $registryRoots = @(
            "HKLM:\SOFTWARE\JavaSoft\JDK",
            "HKLM:\SOFTWARE\JavaSoft\Java Development Kit",
            "HKLM:\SOFTWARE\Microsoft\JDK",
            "HKLM:\SOFTWARE\Eclipse Adoptium\JDK",
            "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\JDK",
            "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Development Kit",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\JDK",
            "HKLM:\SOFTWARE\WOW6432Node\Eclipse Adoptium\JDK"
        )

        foreach ($root in $registryRoots) {
            if (-not (Test-Path -LiteralPath $root)) {
                continue
            }

            Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $properties = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                foreach ($propertyName in @("JavaHome", "InstallationPath", "InstallLocation", "Path")) {
                    if ($properties -and $properties.$propertyName) {
                        Add-JdkCandidate -PathPattern $properties.$propertyName
                    }
                }
            }
        }
    }

    function Add-WingetJdkCandidates {
        if (-not (Test-CommandExists "winget")) {
            return
        }

        $wingetOutput = @(winget list --accept-source-agreements 2>$null)
        foreach ($line in $wingetOutput) {
            if ($line -match "Microsoft\.OpenJDK\.(\d+)") {
                Add-JdkCandidate -PathPattern ("C:\Program Files\Microsoft\jdk-{0}*" -f $Matches[1])
            } elseif ($line -match "EclipseAdoptium\.Temurin\.(\d+)\.JDK") {
                Add-JdkCandidate -PathPattern ("C:\Program Files\Eclipse Adoptium\jdk-{0}*" -f $Matches[1])
            } elseif ($line -match "Oracle\.JDK\.(\d+)") {
                Add-JdkCandidate -PathPattern ("C:\Program Files\Java\jdk-{0}*" -f $Matches[1])
            } elseif ($line -match "BellSoft\.LibericaJDK\.(\d+)") {
                Add-JdkCandidate -PathPattern ("C:\Program Files\BellSoft\LibericaJDK-{0}*" -f $Matches[1])
            }
        }
    }

    Add-JdkCandidate -PathPattern $env:JAVA_HOME
    Add-JdkCandidate -PathPattern "C:\Program Files\Microsoft\jdk-*"
    Add-JdkCandidate -PathPattern "C:\Program Files\Eclipse Adoptium\jdk-*"
    Add-JdkCandidate -PathPattern "C:\Program Files\Java\jdk-*"
    Add-JdkCandidate -PathPattern "C:\Program Files\BellSoft\LibericaJDK-*"
    Add-JdkCandidate -PathPattern "C:\Program Files\Zulu\zulu-*"
    Add-JdkCandidate -PathPattern "C:\Program Files\Amazon Corretto\jdk*"
    Add-RegistryJdkCandidates
    Add-WingetJdkCandidates

    $jdks = New-Object System.Collections.Generic.List[object]
    foreach ($path in ($candidatePaths | Sort-Object -Unique)) {
        $javaExe = Join-Path (Join-Path $path "bin") "java.exe"
        if (Test-Path -LiteralPath $javaExe) {
            [void]$jdks.Add((Get-Item -LiteralPath $path))
        }
    }

    return @($jdks | Sort-Object FullName -Unique)
}

function New-JEnvNameFromJdkPath {
    param([string]$JdkPath)

    $normalizedPath = $JdkPath.TrimEnd("\", "/")
    $name = Split-Path -Leaf $normalizedPath
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "jdk"
    }

    $name = $name -replace '[^A-Za-z0-9._-]', '-'
    return $name
}

function Add-JdkToJenv {
    param([string]$JdkPath)

    if (-not (Test-Path -LiteralPath $JdkPath)) {
        Record-Failure "JDK path does not exist or is not a directory: $JdkPath"
        return
    }

    $jenvName = New-JEnvNameFromJdkPath -JdkPath $JdkPath

    if ($DryRun) {
        Write-Info "DryRun: would run jenv add `"$jenvName`" `"$JdkPath`""
        $script:AddedCount++
        return
    }

    Write-Info "Processing JDK: $JdkPath as $jenvName"
    $output = @(jenv add "$jenvName" "$JdkPath" 2>&1)
    $exitCode = $LASTEXITCODE
    $joinedOutput = ($output -join "`n")
    if ($joinedOutput -match "Theres already a JEnv with the name") {
        Write-Warn "JDK already registered in jenv as $jenvName; skipping."
        return
    }

    if ($exitCode -eq 0) {
        Write-Ok "Successfully added ${jenvName}: $JdkPath"
        $script:AddedCount++
    } else {
        foreach ($line in $output) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Warn $line
            }
        }
        Record-Failure "Failed to add: $JdkPath (exit code: $exitCode)"
    }
}

function Get-ManagedJenvVersions {
    if ($DryRun -or -not (Test-CommandExists "jenv")) {
        return @()
    }

    $output = @(jenv list 2>$null)
    $versions = New-Object System.Collections.Generic.List[object]
    $inGlobalList = $false
    foreach ($line in $output) {
        $value = ($line -replace '^[\*\s]+', '').Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }
        if ($value -match '^All available versions of java') {
            $inGlobalList = $true
            continue
        }
        if ($value -match '^All locally specified versions') {
            break
        }
        if (-not $inGlobalList -or $value -match '^name\s+' -or $value -match '^-+\s+-+') {
            continue
        }

        $name = $value
        $path = ""
        if ($value -match '^(\S+)\s+(.+)$') {
            $name = $Matches[1]
            $path = $Matches[2].Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($name) -and $name -ne "-path") {
            [void]$versions.Add([PSCustomObject]@{
                Name = $name
                Path = $path
            })
        }
    }
    return @($versions | Sort-Object Name -Unique)
}

function Resolve-JEnvVersionSelection {
    param(
        [string]$Selection,
        [object[]]$Versions,
        [switch]$RequireIndex
    )

    $value = $Selection.Trim()
    if ($value -match '^\d+$') {
        $index = [int]$value
        if ($index -ge 1 -and $index -le $Versions.Count) {
            return $Versions[$index - 1].Name
        }

        return $null
    }

    if ($RequireIndex) {
        return $null
    }

    $exactName = @($Versions | Where-Object { $_.Name -eq $value })
    if ($exactName.Count -eq 1) {
        return $exactName[0].Name
    }

    $normalizedValue = $value.TrimEnd("\", "/")
    $exactPath = @($Versions | Where-Object { $_.Path -and $_.Path.TrimEnd("\", "/") -eq $normalizedValue })
    if ($exactPath.Count -eq 1) {
        return $exactPath[0].Name
    }

    return $null
}

function Show-ManagedJenvChoices {
    param([object[]]$Versions)

    Write-Step "DISCOVER Available Java versions managed by jenv"
    if ($Versions.Count -eq 0) {
        Write-Warn "No managed JEnv versions were returned by 'jenv list'."
        return
    }

    $index = 1
    foreach ($version in $Versions) {
        if ($version.Path) {
            Write-Host ("  {0,2}. {1,-28} {2}" -f $index, $version.Name, $version.Path)
        } else {
            Write-Host ("  {0,2}. {1}" -f $index, $version.Name)
        }
        $index++
    }
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

    Show-ManagedJenvChoices -Versions $versions

    if ($GlobalVersion) {
        $resolvedVersion = Resolve-JEnvVersionSelection -Selection $GlobalVersion -Versions $versions
        if ($resolvedVersion) {
            $script:SelectedVersion = $resolvedVersion
        } else {
            Record-Failure "Selection '$GlobalVersion' is not a valid JEnv choice. Use the numbered list above or pass an exact JEnv name/path."
            return
        }
    } elseif ($Yes -or -not [Environment]::UserInteractive) {
        Write-Warn "No -GlobalVersion provided in non-interactive mode; skipping global Java version selection."
        return
    } else {
        $attempts = 0
        while ($attempts -lt 5) {
            $entered = Read-Host "Enter the number of the Java version to set as global"
            $attempts++
            if ([string]::IsNullOrWhiteSpace($entered)) {
                Write-Warn "No selection entered."
                continue
            }
            $resolvedVersion = Resolve-JEnvVersionSelection -Selection $entered -Versions $versions -RequireIndex
            if ($resolvedVersion) {
                $script:SelectedVersion = $resolvedVersion
                break
            }
            Write-Warn "Selection '$entered' is not a valid number from the list above."
        }

        if (-not $script:SelectedVersion) {
            Record-Failure "No valid JEnv version number was selected after 5 attempts."
            return
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
if ($ok) {
    Initialize-JEnvProcessPath
}

$jdks = Get-InstalledJdks
$script:DiscoveredCount = $jdks.Count
if ($jdks.Count -eq 0) {
    if ($DryRun) {
        Write-Warn "DryRun: no JDKs found from JAVA_HOME, registry, winget, or standard Windows installation directories on this host."
    } else {
        Record-Failure "No JDKs found from JAVA_HOME, registry, winget, or standard Windows installation directories. Install a JDK first, then rerun this script."
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
