@echo off
cd /d "%~dp0"
set PS=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe
if not exist "%PS%" set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
