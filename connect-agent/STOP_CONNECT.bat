@echo off
for /f "tokens=2 delims=," %%p in ('wmic process where "commandline like '%%KMR\\Connect%%'" get processid /format:csv ^| findstr /r "[0-9]"') do taskkill /PID %%p /F >nul 2>&1
schtasks /End /TN "KMR Connect" >nul 2>&1
echo KMR Connect helper stopped. It starts again when you sign in to Windows (or run INSTALL_CONNECT.bat).
pause
