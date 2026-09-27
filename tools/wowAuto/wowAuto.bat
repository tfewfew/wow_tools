@echo off
setlocal
start "" powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0wowAuto.ps1"
endlocal
