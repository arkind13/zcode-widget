@echo off
rem ZCode Widget launcher — uses the venv created by install.ps1 when
rem present, otherwise the system Python. pythonw.exe = no console window.
setlocal
set "DIR=%~dp0"

if exist "%DIR%.venv\Scripts\pythonw.exe" (
    set "PYW=%DIR%.venv\Scripts\pythonw.exe"
    set "PY=%DIR%.venv\Scripts\python.exe"
) else (
    set "PYW=pythonw.exe"
    set "PY=python.exe"
)

if "%~1"=="--console" (
    cd /d "%DIR%" && "%PY%" -m zcode_widget
) else (
    cd /d "%DIR%" && start "" "%PYW%" -m zcode_widget
)
endlocal
