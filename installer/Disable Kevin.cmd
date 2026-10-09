@echo off
setlocal
title Kevin Companion - Disable
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-Kevin.ps1"
set "KevinExitCode=%errorlevel%"
echo.
if not "%KevinExitCode%"=="0" echo Kevin could not be disabled completely. Please read the message above.
pause
exit /b %KevinExitCode%
