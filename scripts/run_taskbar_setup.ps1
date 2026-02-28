# run_taskbar_setup.ps1 - minimal runner for taskbar setup

Set-ExecutionPolicy Bypass -Scope Process -Force
& "$PSScriptRoot\taskbar_setup.ps1" -Yes

