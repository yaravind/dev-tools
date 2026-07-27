# dev-tools shared PowerShell profile

# ============================================================
# 1. SHELL MANAGEMENT
# ============================================================
function Edit-Profile { notepad $PROFILE }
function Reload-Profile {
    . $PROFILE
    Write-Host "Done"
}
Set-Alias -Name profile -Value Edit-Profile
Set-Alias -Name reload -Value Reload-Profile
Set-Alias -Name c -Value Clear-Host
$env:EDITOR = if ($env:EDITOR) { $env:EDITOR } else { "notepad" }

# ============================================================
# 2. NAVIGATION
# ============================================================
function .. { Set-Location .. }
function ... { Set-Location ..\..\.. }
function .... { Set-Location ..\..\..\.. }
function ..... { Set-Location ..\..\..\..\.. }
function up {
    param([int]$Levels = 1)
    if ($Levels -lt 1) { $Levels = 1 }
    $target = ".."
    for ($i = 2; $i -le $Levels; $i++) {
        $target = Join-Path $target ".."
    }
    Set-Location $target
}

# ============================================================
# 3. FILE LISTING
# ============================================================
function ltr {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -l -t modified -r -F -h --color=always
    } else {
        Get-ChildItem | Sort-Object LastWriteTime -Descending
    }
}
function lta {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -a -l -F -h --color=always
    } else {
        Get-ChildItem -Force
    }
}
function ld { Get-ChildItem -Directory }
function lf { Get-ChildItem -File }
function lfa { Get-ChildItem -File -Force }
function l. { Get-ChildItem -Force | Where-Object { $_.Name.StartsWith(".") } }
function o { Invoke-Item . }

# ============================================================
# 4. FILE OPERATIONS
# ============================================================
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Set-Alias -Name cat -Value bat -Option AllScope
}
function cpwd {
    (Get-Location).Path | Set-Clipboard
}
function usage {
    Get-ChildItem -Force | Measure-Object -Property Length -Sum
}
function totalusage {
    Get-PSDrive -PSProvider FileSystem
}
function most {
    Get-ChildItem -Force |
        Sort-Object Length -Descending |
        Select-Object -First 10 Name, Length
}

# ============================================================
# 5. NETWORK
# ============================================================
function myip { Invoke-RestMethod https://ipinfo.io/json }
function ipe { (Invoke-RestMethod https://ipinfo.io/ip).Trim() }
function ipi { Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.254.*" } }

# ============================================================
# 6. SYSTEM INFO
# ============================================================
function path { $env:Path -split ';' }
function meminfo { Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory }
function cpuinfo { Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors }
function gpumeminfo { Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, DriverVersion }

# ============================================================
# 7. PROCESS MONITOR
# ============================================================
function psmem { Get-Process | Sort-Object WorkingSet64 -Descending }
function psmem10 { Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 }
function pscpu { Get-Process | Sort-Object CPU -Descending }
function pscpu10 { Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 }

# ============================================================
# 8. HISTORY
# ============================================================
function h { Get-History }
function h1 { Get-History -Count 10 }
function h2 { Get-History -Count 20 }
function h3 { Get-History -Count 30 }
function hs {
    param([Parameter(Mandatory = $true)][string]$Pattern)
    Get-History | Where-Object { $_.CommandLine -match $Pattern }
}

# ============================================================
# 9. SEARCH & TEXT
# ============================================================
function json {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)
    process {
        $InputObject | ConvertFrom-Json | ConvertTo-Json -Depth 100
    }
}

# ============================================================
# 10. GIT
# ============================================================
function gi { git init @args }
function gs { git status @args }
function ga { git add @args }
function gb { git branch @args }
function gc { git commit -m @args }
function gca { git commit --amend -m @args }
function gp { git push origin (git branch --show-current) }
function gd { git diff @args }
function gco { git checkout @args }
function gl { git log --pretty=format:"%h %ad %s [%cn]" --date=short --decorate @args }
function gld { git log --pretty=format:"%h %ad %s" --date=short --all @args }
function gsl { git shortlog @args }
function gslu { git log --format="%aN" | Sort-Object -Unique }
function gslc { git shortlog -sn @args }
function glf {
    param([Parameter(Mandatory = $true)][string]$Pattern)
    git log --all --grep="$Pattern"
}

# ============================================================
# 11. GITHUB CLI
# ============================================================
function ghr { gh repo view --web @args }
function ghpr { gh pr list @args }
function ghprc { gh pr create @args }
function ghprv { gh pr view --web @args }
function ghis { gh issue list @args }
function ghisc { gh issue create @args }

# ============================================================
# 12. CONFIG EDITORS
# ============================================================
function hosts { Start-Process notepad "$env:WINDIR\System32\drivers\etc\hosts" -Verb RunAs }
function gitconfig { notepad "$HOME\.gitconfig" }
function sshconfig { notepad "$HOME\.ssh\config" }

# ============================================================
# 13. JAVA / MAVEN
# ============================================================
function jdks {
    Get-ChildItem "C:\Program Files\Microsoft\jdk-*", "C:\Program Files\Eclipse Adoptium\jdk-*", "C:\Program Files\Java\jdk-*" -ErrorAction SilentlyContinue |
        Select-Object FullName
}
function mvni { mvn clean install @args }
function mvnc { mvn clean compile @args }
function mvnp { mvn clean package @args }

# ============================================================
# 14. TOOLS & INTEGRATIONS
# ============================================================
if (Get-Command tlrc -ErrorAction SilentlyContinue) {
    Set-Alias -Name tldr -Value tlrc
}
