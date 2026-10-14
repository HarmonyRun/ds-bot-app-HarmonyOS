@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-plugin.ps1"
set "dsbot_result=%errorlevel%"
if not "%dsbot_result%"=="0" echo Preparation failed. No DSH files were changed.
pause
exit /b %dsbot_result%
