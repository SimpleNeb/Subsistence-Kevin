@echo off
setlocal
title Kevin Companion - Install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Kevin.ps1"
set "KevinExitCode=%errorlevel%"
echo.
if not "%KevinExitCode%"=="0" echo Kevin was not installed. Please read the message above.
pause
exit /b %KevinExitCode%
