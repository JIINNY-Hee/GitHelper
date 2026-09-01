@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0GitHelper.ps1"
echo.
echo PowerShell exit code: %ERRORLEVEL%
pause
