# run_tests.ps1 - Dry-run validation for Windows scripts
#
# Usage (PowerShell):
#   .\scripts\windows\run_tests.ps1

$brandingScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "branding.ps1"
if (Test-Path $brandingScript) {
    . $brandingScript
    Show-EbkBanner -ScriptName (Split-Path -Leaf $MyInvocation.MyCommand.Path)
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$resolvedRoot = Resolve-Path (Join-Path $scriptDir "..\..") -ErrorAction SilentlyContinue
if ($resolvedRoot) {
    $repoRoot = $resolvedRoot.Path
} else {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$script:SyntaxFailures = 0
$script:DryRunFailures = 0
$script:MissingScripts = 0
$script:MissingConfigs = 0
$script:Warnings = 0

function Add-Warning {
    param([string]$Message)
    $script:Warnings++
    Write-Warn $Message
}

function Add-DryRunFailure {
    param([string]$Message)
    $script:DryRunFailures++
    Write-Warn $Message
}

function Test-LastExitCode {
    param([string]$Label)

    if ($global:LASTEXITCODE -ne 0 -and $null -ne $global:LASTEXITCODE) {
        Add-DryRunFailure "$Label failed with exit code $global:LASTEXITCODE"
        return $false
    }

    Write-Ok "DryRun OK: $Label"
    return $true
}

function Require-Config {
    param(
        [string]$Label,
        [string]$Path
    )

    if (Test-Path $Path) {
        return $true
    }

    $script:MissingConfigs++
    Write-Warn "Config missing for ${Label}: $Path"
    return $false
}

Write-Step "Starting Windows script dry-run checks"

$scripts = @(
    "gen_taskbar_apps.ps1",
    "backup_codex.ps1",
    "clone_github_repos.ps1",
    "restore_codex.ps1",
    "setup_env.ps1",
    "setup_env_min.ps1",
    "setup_env_min_rollback.ps1",
    "git_setup.ps1",
    "launchpad.ps1",
    "powershell_profile_setup.ps1",
    "jenv_setup.ps1",
    "maven_setup.ps1",
    "taskbar_setup.ps1",
    "verify_codex_restore.ps1",
    "vscode_setup.ps1",
    "intellij_setup.ps1",
    "pycharm_setup.ps1",
    "run_taskbar_setup.ps1",
    "run_vscode_setup.ps1"
)

foreach ($script in $scripts) {
    $path = Join-Path $scriptDir $script
    if (-not (Test-Path $path)) {
        $script:MissingScripts++
        Write-Warn "Missing script: $path"
        continue
    }

    try {
        [ScriptBlock]::Create((Get-Content -Raw $path)) | Out-Null
        Write-Ok "Syntax OK: $script"
    } catch {
        $script:SyntaxFailures++
        Write-Warn "Syntax FAILED: $script - $_"
    }
}

$cmdWrappers = @(
    "launchpad.cmd",
    "setup_env.cmd"
)

foreach ($wrapper in $cmdWrappers) {
    $path = Join-Path $scriptDir $wrapper
    if (-not (Test-Path $path)) {
        $script:MissingScripts++
        Write-Warn "Missing launcher: $path"
        continue
    }

    $content = Get-Content -Raw $path
    if ($content -notmatch '(?i)-ExecutionPolicy\s+Bypass' -or $content -notmatch '(?i)-File\s+"%SCRIPT_DIR%') {
        $script:SyntaxFailures++
        Write-Warn "Launcher missing execution-policy bypass invocation: $wrapper"
    } else {
        Write-Ok "Launcher OK: $wrapper"
    }
}

$profileConfig = Join-Path $repoRoot "config"
$profileConfig = Join-Path $profileConfig "Microsoft.PowerShell_profile.ps1"
if (Require-Config -Label "powershell_profile_setup.ps1" -Path $profileConfig) {
    try {
        [ScriptBlock]::Create((Get-Content -Raw $profileConfig)) | Out-Null
        Write-Ok "Syntax OK: config/Microsoft.PowerShell_profile.ps1"
    } catch {
        $script:SyntaxFailures++
        Write-Warn "Syntax FAILED: config/Microsoft.PowerShell_profile.ps1 - $_"
    }

    try {
        Write-Info "DryRun: powershell_profile_setup.ps1"
        $tempProfile = Join-Path ([System.IO.Path]::GetTempPath()) "dev-tools-powershell-profile-test.ps1"
        & (Join-Path $scriptDir "powershell_profile_setup.ps1") -DryRun -ProfilePath $tempProfile -ConfigPath $profileConfig | Out-Null
        Test-LastExitCode "powershell_profile_setup.ps1" | Out-Null
    } catch {
        Add-DryRunFailure "DryRun FAILED: powershell_profile_setup.ps1 - $_"
    }
}

try {
    Write-Info "DryRun: launchpad.ps1"
    & (Join-Path $scriptDir "launchpad.ps1") -Profile ide-only -DryRun -Yes | Out-Null
    Test-LastExitCode "launchpad.ps1" | Out-Null
} catch {
    Add-DryRunFailure "DryRun FAILED: launchpad.ps1 - $_"
}

$repoListConfig = Join-Path $repoRoot "config"
$repoListConfig = Join-Path $repoListConfig "github-repos.txt"
if (Require-Config -Label "clone_github_repos.ps1" -Path $repoListConfig) {
    try {
        Write-Info "DryRun: launchpad.ps1 full profile with clone task"
        $cloneTarget = Join-Path ([System.IO.Path]::GetTempPath()) "dev-tools-launchpad-clone-test"
        & (Join-Path $scriptDir "launchpad.ps1") -Profile full -DryRun -Yes -CloneRepoList $repoListConfig -CloneDestination $cloneTarget | Out-Null
        Test-LastExitCode "launchpad.ps1 full profile" | Out-Null
    } catch {
        Add-DryRunFailure "DryRun FAILED: launchpad.ps1 full profile - $_"
    }

    try {
        Write-Info "DryRun: clone_github_repos.ps1"
        & (Join-Path $scriptDir "clone_github_repos.ps1") $repoListConfig "." -DryRun | Out-Null
        Test-LastExitCode "clone_github_repos.ps1" | Out-Null
    } catch {
        Add-DryRunFailure "DryRun FAILED: clone_github_repos.ps1 - $_"
    }
}

try {
    Write-Info "DryRun: backup_codex.ps1"
    $backupTarget = Join-Path ([System.IO.Path]::GetTempPath()) "dev-tools-codex-backup-test"
    & (Join-Path $scriptDir "backup_codex.ps1") $backupTarget -DryRun | Out-Null
    Test-LastExitCode "backup_codex.ps1" | Out-Null
} catch {
    Add-DryRunFailure "DryRun FAILED: backup_codex.ps1 - $_"
}

try {
    Write-Info "DryRun: restore_codex.ps1"
    $restoreSource = Join-Path ([System.IO.Path]::GetTempPath()) "dev-tools-codex-restore-source-test"
    & (Join-Path $scriptDir "restore_codex.ps1") $restoreSource -DryRun -Yes | Out-Null
    Test-LastExitCode "restore_codex.ps1" | Out-Null
} catch {
    Add-DryRunFailure "DryRun FAILED: restore_codex.ps1 - $_"
}

try {
    Write-Info "ReadOnly: verify_codex_restore.ps1"
    $missingCodex = Join-Path ([System.IO.Path]::GetTempPath()) "dev-tools-missing-codex-test"
    & (Join-Path $scriptDir "verify_codex_restore.ps1") -CodexDir $missingCodex -AllowMissing | Out-Null
    Test-LastExitCode "verify_codex_restore.ps1" | Out-Null
} catch {
    Add-DryRunFailure "ReadOnly FAILED: verify_codex_restore.ps1 - $_"
}

$taskbarConfig = Join-Path $repoRoot "config"
$taskbarConfig = Join-Path $taskbarConfig "taskbar_apps.txt"
if (-not $IsWindows) {
    Add-Warning "Skipping taskbar_setup.ps1 DryRun on non-Windows host."
} elseif (Require-Config -Label "taskbar_setup.ps1" -Path $taskbarConfig) {
    try {
        Write-Info "DryRun: taskbar_setup.ps1"
        & (Join-Path $scriptDir "taskbar_setup.ps1") -DryRun -Yes -ConfigPath $taskbarConfig | Out-Null
        Test-LastExitCode "taskbar_setup.ps1" | Out-Null
    } catch {
        Add-DryRunFailure "DryRun FAILED: taskbar_setup.ps1 - $_"
    }
}

try {
    Write-Info "DryRun: git_setup.ps1"
    & (Join-Path $scriptDir "git_setup.ps1") -DryRun -Yes | Out-Null
    Test-LastExitCode "git_setup.ps1" | Out-Null
} catch {
    Add-DryRunFailure "DryRun FAILED: git_setup.ps1 - $_"
}

try {
    Write-Info "DryRun: jenv_setup.ps1"
    $tempJdk = Join-Path ([System.IO.Path]::GetTempPath()) ("dev-tools-jdk-test-" + [Guid]::NewGuid().ToString("N"))
    $tempJdkBin = Join-Path $tempJdk "bin"
    $tempJava = Join-Path $tempJdkBin "java.exe"
    $previousJavaHome = $env:JAVA_HOME
    New-Item -ItemType Directory -Force -Path $tempJdkBin | Out-Null
    New-Item -ItemType File -Force -Path $tempJava | Out-Null
    $env:JAVA_HOME = $tempJdk

    try {
        $jenvOutput = @(& (Join-Path $scriptDir "jenv_setup.ps1") -DryRun -Yes *>&1)
        Test-LastExitCode "jenv_setup.ps1" | Out-Null
        $expectedName = Split-Path -Leaf $tempJdk
        $expectedAdd = "jenv add `"$expectedName`" `"$tempJdk`""
        $jenvOutputText = $jenvOutput -join "`n"
        if ($jenvOutputText -match "jenv add -path") {
            Add-DryRunFailure "jenv_setup.ps1 still uses invalid JEnv-for-Windows syntax: jenv add -path"
        } elseif ($jenvOutputText -notmatch [regex]::Escape($expectedAdd)) {
            Add-DryRunFailure "jenv_setup.ps1 did not emit expected JEnv-for-Windows syntax: $expectedAdd"
        }
    } finally {
        $env:JAVA_HOME = $previousJavaHome
        Remove-Item -LiteralPath $tempJdk -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Add-DryRunFailure "DryRun FAILED: jenv_setup.ps1 - $_"
}

$vscodeConfig = Join-Path $repoRoot "config"
$vscodeConfig = Join-Path $vscodeConfig "vscode.txt"
if (Require-Config -Label "vscode_setup.ps1" -Path $vscodeConfig) {
    try {
        Write-Info "DryRun: vscode_setup.ps1"
        & (Join-Path $scriptDir "vscode_setup.ps1") -DryRun -Yes -ConfigPath $vscodeConfig | Out-Null
        Test-LastExitCode "vscode_setup.ps1" | Out-Null
    } catch {
        Add-DryRunFailure "DryRun FAILED: vscode_setup.ps1 - $_"
    }
}

$intellijConfig = Join-Path $repoRoot "config"
$intellijConfig = Join-Path $intellijConfig "intellij.txt"
if (Require-Config -Label "intellij_setup.ps1" -Path $intellijConfig) {
    try {
        Write-Info "DryRun: intellij_setup.ps1"
        & (Join-Path $scriptDir "intellij_setup.ps1") -DryRun -Yes -ConfigPath $intellijConfig | Out-Null
        Test-LastExitCode "intellij_setup.ps1" | Out-Null
    } catch {
        Add-DryRunFailure "DryRun FAILED: intellij_setup.ps1 - $_"
    }
}

$pycharmConfig = Join-Path $repoRoot "config"
$pycharmConfig = Join-Path $pycharmConfig "pycharm.txt"
if (Require-Config -Label "pycharm_setup.ps1" -Path $pycharmConfig) {
    try {
        Write-Info "DryRun: pycharm_setup.ps1"
        & (Join-Path $scriptDir "pycharm_setup.ps1") -DryRun -Yes -ConfigPath $pycharmConfig | Out-Null
        Test-LastExitCode "pycharm_setup.ps1" | Out-Null
    } catch {
        Add-DryRunFailure "DryRun FAILED: pycharm_setup.ps1 - $_"
    }
}

try {
    $testScript = Join-Path $scriptDir "test_setup_env_min.ps1"
    if (Test-Path $testScript) {
        Write-Info "DryRun: setup_env_min.ps1 (via test harness)"
        & $testScript | Out-Null
        Test-LastExitCode "setup_env_min.ps1" | Out-Null
    } else {
        $minScript = Join-Path $scriptDir "setup_env_min.ps1"
        if (Test-Path $minScript) {
            Write-Info "DryRun: setup_env_min.ps1"
            & $minScript -DryRun | Out-Null
            Test-LastExitCode "setup_env_min.ps1" | Out-Null
        } else {
            $script:MissingScripts++
            Write-Warn "Missing: $minScript"
        }
    }
} catch {
    Add-DryRunFailure "DryRun FAILED: setup_env_min.ps1 - $_"
}

try {
    $rollScript = Join-Path $scriptDir "setup_env_min_rollback.ps1"
    if (Test-Path $rollScript) {
        Write-Info "DryRun: setup_env_min_rollback.ps1"
        & $rollScript -DryRun | Out-Null
        Test-LastExitCode "setup_env_min_rollback.ps1" | Out-Null
    } else {
        $script:MissingScripts++
        Write-Warn "Missing: $rollScript"
    }
} catch {
    Add-DryRunFailure "DryRun FAILED: setup_env_min_rollback.ps1 - $_"
}

Write-Step "Summary"
Write-Ok ("Scripts checked: {0}" -f $scripts.Count)
Write-Warn ("Missing scripts: {0}" -f $script:MissingScripts)
Write-Warn ("Syntax failures: {0}" -f $script:SyntaxFailures)
Write-Warn ("Missing configs: {0}" -f $script:MissingConfigs)
Write-Warn ("DryRun failures: {0}" -f $script:DryRunFailures)
Write-Warn ("Warnings: {0}" -f $script:Warnings)

Write-Step "Windows dry-run checks complete"

if (($script:MissingScripts + $script:SyntaxFailures + $script:MissingConfigs + $script:DryRunFailures) -gt 0) {
    exit 1
}
