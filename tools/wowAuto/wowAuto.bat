@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0wowAuto.ps1"
if errorlevel 1 (
    echo.
    echo Script stopped or encountered an error.
    pause
)
endlocal
