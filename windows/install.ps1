# ZCode Widget — Windows installer
# Creates a venv, installs PySide6, and drops a Start Menu shortcut.
# Run from PowerShell:  .\install.ps1
# Optional (launch on login): .\install.ps1 -AddToStartup

param(
    [switch]$AddToStartup
)

$ErrorActionPreference = "Stop"
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Dir

# 1. Python check
try {
    $pyVersion = python --version 2>&1
} catch {
    Write-Error "Python not found. Install Python 3.10+ from https://www.python.org/downloads/ (tick 'Add python.exe to PATH')." 
}
Write-Host "Using $pyVersion"

# 2. Venv + dependencies
if (-not (Test-Path "$Dir\.venv")) {
    python -m venv "$Dir\.venv"
}
& "$Dir\.venv\Scripts\python.exe" -m pip install --upgrade pip --quiet
& "$Dir\.venv\Scripts\python.exe" -m pip install -r "$Dir\requirements.txt" --quiet
Write-Host "Dependencies installed."

# 3. Shortcuts
$Wsh = New-Object -ComObject WScript.Shell
$startMenu = [Environment]::GetFolderPath("StartMenu")
$lnk = $Wsh.CreateShortcut("$startMenu\Programs\ZCode Widget.lnk")
$lnk.TargetPath = "$Dir\.venv\Scripts\pythonw.exe"
$lnk.Arguments = "-m zcode_widget"
$lnk.WorkingDirectory = $Dir
$lnk.IconLocation = "$Dir\.venv\Scripts\pythonw.exe"
$lnk.Description = "ZCode Widget (token stats, skills, plugins, providers)"
$lnk.Save()
Write-Host "Start Menu shortcut created."

if ($AddToStartup) {
    $startup = [Environment]::GetFolderPath("Startup")
    $lnk2 = $Wsh.CreateShortcut("$startup\ZCode Widget.lnk")
    $lnk2.TargetPath = "$Dir\.venv\Scripts\pythonw.exe"
    $lnk2.Arguments = "-m zcode_widget"
    $lnk2.WorkingDirectory = $Dir
    $lnk2.Save()
    Write-Host "Startup shortcut created (widget launches on login)."
}

Write-Host ""
Write-Host "Done. Launch via the Start Menu shortcut, or run .\run.cmd"
