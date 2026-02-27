# setup_env.ps1 — Windows equivalent of setup_env.sh
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
# CLI Tools — winget equivalents of brew formulae
# ============================================================
$cliTools = @(
    @{ Id = "Python.Python.3.13";    Description = "Python 3.13" },
    @{ Id = "Rustlang.Rustup";       Description = "Rust toolchain manager" },
    @{ Id = "astral-sh.uv";          Description = "Extremely fast Python package installer and resolver, written in Rust" },
    @{ Id = "jqlang.jq";             Description = "Lightweight and flexible command-line JSON processor" },
    @{ Id = "GitHub.cli";            Description = "GitHub command-line tool" },
    @{ Id = "Microsoft.AzureCLI";    Description = "Azure CLI" },
    @{ Id = "tldr-pages.tldr";       Description = "Simplified and community-driven man pages" },
    @{ Id = "eza-community.eza";     Description = "Modern replacement for the ls command" },
    @{ Id = "sharkdp.bat";           Description = "Clone of cat(1) with syntax highlighting and Git integration" },
    @{ Id = "OpenJS.NodeJS";         Description = "Cross-platform JavaScript runtime environment" },
    @{ Id = "JohnMacFarlane.Pandoc"; Description = "Swiss-army knife of markup format conversion" },
    @{ Id = "Graphviz.Graphviz";     Description = "Convert dot files to images" },
    @{ Id = "Apache.Maven";          Description = "Project management and comprehension tool" }
)

# ============================================================
# CLI Tools NOT available on Windows (documented for reference)
# ============================================================
# - htop:     No direct equivalent.
#             Use Task Manager or `Get-Process | Sort-Object CPU -Descending` in PowerShell.
# - pipx:     Not in winget. Install via pip after Python is set up:
#             `pip install pipx`
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
# GUI Apps — winget equivalents of brew casks
# ============================================================
$guiApps = @(
    @{ Id = "Microsoft.OpenJDK.11";              Description = "Microsoft OpenJDK 11 (for Fabric Runtime 1.3)" },
    @{ Id = "Microsoft.OpenJDK.17";              Description = "Microsoft OpenJDK 17 (for Apache Jena 5.4.x)" },
    @{ Id = "Microsoft.DotNet.SDK.9";            Description = ".NET SDK (for VS Code plugins related to Fabric and Synapse)" },
    @{ Id = "Microsoft.GitCredentialManager";    Description = "Cross-platform Git credential storage for multiple hosting providers" },
    @{ Id = "JetBrains.IntelliJIDEA.Ultimate";   Description = "IntelliJ IDEA Ultimate (use JetBrains.IntelliJIDEA.Community for free edition)" },
    @{ Id = "JetBrains.PyCharm.Professional";    Description = "PyCharm Professional (use JetBrains.PyCharm.Community for free edition)" },
    @{ Id = "Microsoft.VisualStudioCode";        Description = "Visual Studio Code" },
    @{ Id = "Microsoft.AzureStorageExplorer";    Description = "Microsoft Azure Storage Explorer" },
    @{ Id = "JGraph.Draw";                       Description = "Draw.io — online diagram software" },
    @{ Id = "Zed.Zed";                           Description = "Zed — multiplayer code editor" },
    @{ Id = "Ollama.Ollama";                     Description = "Manage local LLMs" },
    @{ Id = "Logitech.LogiOptionsPlus";          Description = "Software for Logitech devices" },
    @{ Id = "Microsoft.PowerShell";              Description = "PowerShell (latest stable version)" },
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

# Verify winget is available before proceeding
function Assert-Winget {
    if (-not (Test-CommandExists "winget")) {
        Write-Host "ERROR: winget (App Installer) is not installed." -ForegroundColor Red
        Write-Host "Install it from the Microsoft Store:" -ForegroundColor Red
        Write-Host "  https://www.microsoft.com/store/productId/9NBLGGH4NNS1" -ForegroundColor Yellow
        exit 1
    }
}

# Install a package via winget (idempotent — skips if already installed)
function Install-WingetApp {
    param(
        [string]$Id,
        [string]$Description
    )
    Write-Info "Installing: $Description ($Id)..."
    winget install --id "$Id" --exact --accept-source-agreements --accept-package-agreements --silent
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Installed: $Description"
    } elseif ($LASTEXITCODE -eq -1978335189) {
        # 0x8A150023 = APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
        Write-Warn "Already installed: $Description — skipping."
    } else {
        Write-Warn "Could not install $Description ($Id). Exit code: $LASTEXITCODE"
    }
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

# Install JEnv-for-Windows (https://github.com/FelixSelter/JEnv-for-Windows)
function Install-JEnv {
    Write-Step "Installing JEnv-for-Windows..."
    if ($null -ne (Get-Command "jenv" -ErrorAction SilentlyContinue)) {
        Write-Warn "jenv is already installed — skipping."
    } else {
        # NOTE: Review the installer script before running in sensitive environments:
        # https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/jenv.ps1
        iwr -useb "https://raw.githubusercontent.com/FelixSelter/JEnv-for-Windows/main/jenv.ps1" | iex
        Write-Ok "JEnv-for-Windows installed. Run .\scripts\jenv_setup.ps1 to register your JDKs."
    }
}

# Verify that key tools installed correctly
function Invoke-Verify {
    Write-Step "Start verification"

    Write-Info "All installed packages (via winget list)..."
    winget list

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

    Write-Warn "*** Add `Set-Alias cat bat` to your PowerShell profile for bat-as-cat ***"
    Write-Warn "*** Run `notepad `$PROFILE` to open your PowerShell profile for editing ***"
}

# ============================================================
# Main script execution
# ============================================================
Write-Step "Starting Windows developer environment setup..."

Assert-Winget

Write-Info "Updating winget sources..."
winget source update

Write-Step "Installing CLI tools..."
foreach ($tool in $cliTools) {
    Install-WingetApp -Id $tool.Id -Description $tool.Description
}

Write-Step "Installing GUI applications..."
foreach ($app in $guiApps) {
    Install-WingetApp -Id $app.Id -Description $app.Description
}

# Refresh PATH in the current session so winget-installed tools (e.g. Python/pip) are visible
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

Install-PipTools

Install-JEnv

Set-JavaHome

Invoke-Verify

Write-Host "`n`n👌 Awesome, all set." -ForegroundColor Green
