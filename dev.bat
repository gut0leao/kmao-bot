@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Kmao.ps1" -Component bot
set "KMAO_EXIT_CODE=%ERRORLEVEL%"
if not "%KMAO_EXIT_CODE%"=="0" echo ERROR: Bot failed. See the error above and the application log.
pause
exit /b %KMAO_EXIT_CODE%
