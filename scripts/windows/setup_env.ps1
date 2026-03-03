# setup_env.ps1 - Windows equivalent of setup_env.sh
#
# This script automates the installation and configuration of commonly used
# developer tools on modern Windows (Windows 10/11) using winget.
#
# Usage: Run in PowerShell as Administrator:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\setup_env.ps1
#
# Pre-requisites:
#   - Windows 10/11 with winget (App Installer) installed
#     https://learn.microsoft.com/en-us/windows/package-manager/winget/
#   - Run PowerShell as Administrator for system-wide installations

# ============================================================
# CLI Tools - winget equivalents of brew formulae
# ============================================================
$cliTools = @(
    @{ Id = "Python.Python.3.13";    Description = "Python 3.13" },
    @{ Id = "Rustlang.Rustup";       Description = "Rust toolchain manager" },
    @{ Id = "astral-sh.uv";          Description = "Extremely fast Python package installer and resolver, written in Rust" },
    @{ Id = "jqlang.jq";             Description = "Lightweight and flexible command-line JSON processor" },
    @{ Id = "GitHub.cli";            Description = "GitHub command-line tool" },
    @{ Id = "Microsoft.AzureCLI";    Description = "Azure CLI" },
    @{ Id = "dbrgn.tealdeer";        Description = "tldr client (tealdeer)" },
    @{ Id = "eza-community.eza";     Description = "Modern replacement for the ls command" },
    @{ Id = "sharkdp.bat";           Description = "Clone of cat(1) with syntax highlighting and Git integration" },
    @{ Id = "OpenJS.NodeJS";         Description = "Cross-platform JavaScript runtime environment" },
    @{ Id = "JohnMacFarlane.Pandoc"; Description = "Swiss-army knife of markup format conversion" },
    @{ Id = "GitHub.Copilot.CLI";    Description = "GitHub Copilot CLI - AI pair-programmer in the terminal" },
    @{ Id = "Graphviz.Graphviz";     Description = "Convert dot files to images" }
)

# ============================================================
# CLI Tools NOT available on Windows (documented for reference)
# ============================================================
# - htop:     No direct equivalent.
#             Use Task Manager or `Get-Process | Sort-Object CPU -Descending` in PowerShell.
# - pipx:     Not in winget. Install via pip after Python is set up:
#             `pip install pipx`
# - maven:    Installed via .\scripts\maven_setup.ps1 (winget ID not reliable).
# - trash:    No direct equivalent.
#             Use the built-in Recycle Bin or the RecycleBin PowerShell module.
# - jenv:     Use JEnv-for-Windows (https://github.com/FelixSelter/JEnv-for-Windows).
#             Installed below. Run jenv_setup.ps1 after this script to register JDKs.
# - thefuck:  Not fully supported on Windows. Limited functionality only.
# - lnav:     Not available on Windows.
#             Consider BareTail (https://www.baremetalsoft.com/baretail/) or WSL.
# - llm:      Not in winget. Install via pip after Python is set up:
#             `pip install llm`
# - dockutil: macOS Dock-specific. No Windows equivalent needed.
# - tree:     Built-in Windows command (`tree /F`). No installation required.

# ============================================================
# GUI Apps - winget equivalents of brew casks
# ============================================================
$guiApps = @(
    @{ Id = "Microsoft.OpenJDK.11";              Description = "Microsoft OpenJDK 11 (for Fabric Runtime 1.3)" },
    @{ Id = "Microsoft.OpenJDK.17";              Description = "Microsoft OpenJDK 17 (for Apache Jena 5.4.x)" },
    @{ Id = "Microsoft.DotNet.SDK.9";            Description = ".NET SDK (for VS Code plugins related to Fabric and Synapse)" },
    @{ Id = "Git.GCM";                           Description = "Git Credential Manager (cross-platform Git credential storage)" },
    @{ Id = "JetBrains.IntelliJIDEA.Ultimate";   Description = "IntelliJ IDEA Ultimate" },
    @{ Id = "JetBrains.IntelliJIDEA.Community";  Description = "IntelliJ IDEA Community"; NoSilent = $true },
    @{ Id = "JetBrains.PyCharm.Professional";    Description = "PyCharm Professional" },
    @{ Id = "JetBrains.PyCharm.Community";       Description = "PyCharm Community"; NoSilent = $true },
    @{ Id = "Microsoft.VisualStudioCode";        Description = "Visual Studio Code" },
    @{ Id = "Microsoft.Azure.StorageExplorer";   Description = "Microsoft Azure Storage Explorer" },
    @{ Id = "JGraph.Draw";                       Description = "Draw.io - online diagram software" },
    @{ Id = "ZedIndustries.Zed";                 Description = "Zed - multiplayer code editor" },
    @{ Id = "Ollama.Ollama";                     Description = "Manage local LLMs" },
    @{ Id = "Microsoft.PowerShell";              Description = "PowerShell (latest stable version)"; SkipCommand = "pwsh" },
    @{ Id = "Obsidian.Obsidian";                 Description = "Note-taking app with Markdown support (fsnotes equivalent)" }
)

# ============================================================
# GUI Apps NOT available on Windows (documented for reference)
# ============================================================
# - appcleaner: macOS-specific. Use Windows built-in Programs and Features,
#               or Revo Uninstaller (https://www.revouninstaller.com/).
# - fsnotes:    macOS-specific. Obsidian (included above) is a cross-platform alternative.
# - go2shell:   macOS-specific. Windows 11 has "Open in Terminal" natively
#               in File Explorer (right-click context menu).
# - zed:        Zed is now available via winget (ZedIndustries.Zed).

# ============================================================
# Helper Functions
# ============================================================

function Write-Step {
    param([string]$Message)
    Write-Host "===> $Message" -ForegroundColor Magenta
}

function Write-Info {
    param([string]$Message)
    Write-Host "===> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "===> $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "===> $Message" -ForegroundColor Yellow
}

# Check if a command exists in the current PATH
function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Verify a winget install by querying the package list (with short retries)
function Test-WingetInstalled {
    param(
        [string]$Id,
        [string]$Name
    )
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $listOutput = & $script:WingetExe list --id $Id --exact 2>$null
        if ($listOutput -and ($listOutput | Select-String -SimpleMatch $Id)) {
            return $true
        }
        if ($Name) {
            $listOutput = & $script:WingetExe list --name $Name 2>$null
            if ($listOutput -and ($listOutput | Select-String -SimpleMatch $Name)) {
                return $true
            }
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

# Verify winget is available before proceeding
function Assert-Winget {
    if (-not (Test-CommandExists "winget")) {
        Write-Host "ERROR: winget (App Installer) is not installed." -ForegroundColor Red
        Write-Host "Install it from the Microsoft Store:" -ForegroundColor Red
        Write-Host "  https://www.microsoft.com/store/productId/9NBLGGH4NNS1" -ForegroundColor Yellow
        exit 1
    }

    $script:WingetExe = (Get-Command winget -ErrorAction Stop).Source
}

# Run winget install with consistent arguments
function Invoke-WingetInstall {
    param(
        [string]$Id,
        [string]$Source,
        [switch]$NoSilent,
        [switch]$UseName
    )

    $args = @("install")
    if ($UseName) {
        $args += @("--name", $Id)
    } else {
        $args += @("--id", $Id, "--exact")
    }
    if ($Source) {
        $args += @("--source", $Source)
    }
    $args += @("--accept-source-agreements", "--accept-package-agreements")
    if (-not $NoSilent) {
        $args += "--silent"
    }

    & $script:WingetExe @args
    return $LASTEXITCODE
}

# Install a package via winget (idempotent - skips if already installed)
function Install-WingetApp {
    param(
        [string]$Id,
        [string]$Description,
        [string]$Source,
        [string]$FallbackName,
        [string]$SkipCommand,
        [switch]$NoSilent
    )
    if ($SkipCommand -and (Test-CommandExists $SkipCommand)) {
        Write-Warn "$SkipCommand already available. Skipping $Description."
        return
    }
    Write-Info "Installing: $Description ($Id)..."

    $exitCode = Invoke-WingetInstall -Id $Id -Source $Source -NoSilent:$NoSilent
    if ($exitCode -eq 0) {
        Write-Ok "Installed: $Description"
        return
    }
    if ($exitCode -eq -1978335189) {
        # 0x8A150023 = APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
        Write-Warn "Already installed: $Description - skipping."
        return
    }
    if ($exitCode -eq 3010 -or $exitCode -eq 1641) {
        Write-Warn "Installed: $Description (reboot required)."
        return
    }

    if ($exitCode -eq -1978335212 -and $FallbackName) {
        Write-Warn "Package not found for ID $Id. Trying by name: $FallbackName"
        $fallbackExit = Invoke-WingetInstall -Id $FallbackName -Source $Source -NoSilent:$NoSilent -UseName
        if ($fallbackExit -eq 0) {
            Write-Ok "Installed: $Description"
            return
        }
        if ($fallbackExit -eq -1978335189) {
            Write-Warn "Already installed: $Description - skipping."
            return
        }
        if ($fallbackExit -eq 3010 -or $fallbackExit -eq 1641) {
            Write-Warn "Installed: $Description (reboot required)."
            return
        }
        if (Test-WingetInstalled -Id $Id -Name $FallbackName) {
            Write-Ok "Installed: $Description (verified by winget list)"
            return
        }
        Write-Warn "Could not install $Description (name: $FallbackName). Exit code: $fallbackExit"
        return
    }

    if ($exitCode -eq -1978335230 -and -not $NoSilent) {
        Write-Warn "Install failed with --silent. Retrying without --silent..."
        $retryExit = Invoke-WingetInstall -Id $Id -Source $Source -NoSilent -UseName:$false
        if ($retryExit -eq 0) {
            Write-Ok "Installed: $Description"
            return
        }
        if ($retryExit -eq -1978335189) {
            Write-Warn "Already installed: $Description - skipping."
            return
        }
        if ($retryExit -eq 3010 -or $retryExit -eq 1641) {
            Write-Warn "Installed: $Description (reboot required)."
            return
        }
        if (Test-WingetInstalled -Id $Id -Name $FallbackName) {
            Write-Ok "Installed: $Description (verified by winget list)"
            return
        }
        Write-Warn "Could not install $Description ($Id). Exit code: $retryExit"
        return
    }

    if (Test-WingetInstalled -Id $Id -Name $FallbackName) {
        Write-Ok "Installed: $Description (verified by winget list)"
        return
    }

    Write-Warn "Could not install $Description ($Id). Exit code: $exitCode"
}

function Install-Maven {
    $scriptDir = if ($PSScriptRoot) {
        $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path) {
        Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        Split-Path -Parent $PSCommandPath
    }
    if (-not $scriptDir) {
        Write-Warn "Could not resolve script directory for Maven installer lookup."
        return
    }
    $mavenScript = Join-Path $scriptDir "maven_setup.ps1"
    if (-not (Test-Path $mavenScript)) {
        Write-Warn "Maven installer not found at $mavenScript"
        return
    }
    & $mavenScript
}

# Install pip-based tools that have no winget package (pipx and llm)
function Install-PipTools {
    Write-Step "Installing pip-based tools (pipx and llm)..."
    $pip = if (Test-CommandExists "pip") { "pip" } elseif (Test-CommandExists "pip3") { "pip3" } else { $null }
    if ($pip) {
        Write-Info "Installing pipx via $pip..."
        & $pip install pipx
        Write-Info "Installing llm via $pip..."
        & $pip install llm
    } else {
        Write-Warn "pip not found. winget-installed Python may require a terminal restart."
        Write-Warn "After restarting, run: pip install pipx llm"
    }
}

function Refresh-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# Set JAVA_HOME to the most recent JDK found on the system
function Set-JavaHome {
    Write-Step "Setting up JAVA_HOME..."

    $jdkSearchPaths = @(
        "C:\Program Files\Microsoft\jdk-*",
        "C:\Program Files\Eclipse Adoptium\jdk-*",
        "C:\Program Files\Java\jdk-*"
    )

    $latestJdk = $null
    foreach ($searchPath in $jdkSearchPaths) {
        $found = Get-Item -Path $searchPath -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($found) {
            $latestJdk = $found.FullName
            break
        }
    }

    if ($latestJdk) {
        Write-Info "Found JDK at: $latestJdk"
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $latestJdk, "User")
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $jdkBin = "$latestJdk\bin"
        if ($currentPath -notlike "*$jdkBin*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$jdkBin", "User")
        }
        Write-Ok "JAVA_HOME set to: $latestJdk"
        Write-Warn "Restart your terminal to apply the JAVA_HOME change."
    } else {
        Write-Warn "No JDK found in standard locations. Set JAVA_HOME manually after installing a JDK."
        Write-Warn "Example: [Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Microsoft\jdk-17.x.x.x', 'User')"
    }
}

# Install Git if not already present
function Install-Git {
    Write-Step "Checking for Git..."
    if (Test-CommandExists "git") {
        Write-Warn "git is already installed - skipping."
    } else {
        Write-Info "git not found. Installing Git for Windows..."
        Install-WingetApp -Id "Git.Git" -Description "Git for Windows"
        Write-Warn "Restart your terminal for git to be available in PATH."
    }
}

# Install JEnv-for-Windows (https://github.com/FelixSelter/JEnv-for-Windows)
function Install-JEnv {
    Write-Step "Installing JEnv-for-Windows..."
    if ($null -ne (Get-Command "jenv" -ErrorAction SilentlyContinue)) {
        Write-Warn "jenv is already installed - skipping."
    } else {
        # NOTE: Review the installer script before running in sensitive environments:
        $installerUrls = @(
            "https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/jenv.ps1",
            "https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/bin/jenv.ps1"
        )

        $installed = $false
        foreach ($url in $installerUrls) {
            try {
                Write-Info "Fetching installer: $url"
                iwr -useb $url | iex
                $installed = $true
                break
            } catch {
                Write-Warn "Could not download installer from $url"
            }
        }

        if ($installed) {
            Write-Ok "JEnv-for-Windows installed. Run .\scripts\jenv_setup.ps1 to register your JDKs."
        } else {
            Write-Warn "JEnv-for-Windows installer could not be downloaded."
            Write-Warn "Install manually: https://github.com/FelixSelter/JEnv-for-Windows"
        }
    }
}

# Verify that key tools installed correctly
function Invoke-Verify {
    Write-Step "Start verification"

    Write-Info "All installed packages (via winget list)..."
    & $script:WingetExe list

    Write-Info "Verify Git..."
    if (Test-CommandExists "git") { git --version } else { Write-Warn "git not found in PATH. Restart your terminal." }

    Write-Info "Verify Java..."
    if (Test-CommandExists "java") { java -version } else { Write-Warn "java not found in PATH. Restart your terminal." }

    Write-Info "Verify Maven..."
    if (Test-CommandExists "mvn") { mvn -version } else { Write-Warn "mvn not found in PATH. Restart your terminal." }

    Write-Info "Verify Python..."
    if (Test-CommandExists "python") { python --version }
    elseif (Test-CommandExists "python3") { python3 --version }
    else { Write-Warn "python not found in PATH." }

    Write-Info "Verify Node.js..."
    if (Test-CommandExists "node") { node --version } else { Write-Warn "node not found in PATH. Restart your terminal." }

    Write-Info "Verify GitHub Copilot CLI..."
    if (Test-CommandExists "copilot") {
        try {
            copilot --version
        } catch {
            Write-Warn "copilot found but '--version' failed: $_"
        }
    } else {
        Write-Warn "copilot not found in PATH. To use Copilot CLI, install GitHub Copilot CLI or run the corresponding installer."
    }

    Write-Warn '*** Add `Set-Alias cat bat` to your PowerShell profile for bat-as-cat ***'
    Write-Warn '*** Run `notepad $PROFILE` to open your PowerShell profile for editing ***'
}

# ============================================================
# Main script execution
# ============================================================
Write-Step "Starting Windows developer environment setup..."

Assert-Winget

Write-Info "Updating winget sources..."
& $script:WingetExe source update

Write-Step "Installing CLI tools..."
foreach ($tool in $cliTools) {
    Install-WingetApp -Id $tool.Id -Description $tool.Description -Source $tool.Source -FallbackName $tool.FallbackName -SkipCommand $tool.SkipCommand -NoSilent:$tool.NoSilent
}

Write-Step "Installing GUI applications..."
foreach ($app in $guiApps) {
    Install-WingetApp -Id $app.Id -Description $app.Description -Source $app.Source -FallbackName $app.FallbackName -SkipCommand $app.SkipCommand -NoSilent:$app.NoSilent
}

# Refresh PATH in the current session so winget-installed tools (e.g. Python/pip) are visible
Refresh-SessionPath

Install-PipTools

Install-Maven

Refresh-SessionPath

Install-Git

Install-JEnv

Set-JavaHome

Invoke-Verify

Write-Host "`n`nAwesome, all set!" -ForegroundColor Green
