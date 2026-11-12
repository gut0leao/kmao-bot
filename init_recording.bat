@echo off
REM Application directories and configuration are initialized by the PowerShell script.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0activity_logger.ps1"
set "KMAO_EXIT_CODE=%ERRORLEVEL%"
if not "%KMAO_EXIT_CODE%"=="0" echo ERROR: Recording failed. See the error above and the application log.
pause
exit /b %KMAO_EXIT_CODE%
