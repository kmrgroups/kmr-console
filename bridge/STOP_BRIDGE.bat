@echo off
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\KMR ERP Bridge.lnk" >nul 2>&1
powershell -NoProfile -Command "Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match 'ErpBridge' } | ForEach-Object { $_.Terminate() | Out-Null }"
echo The KMR ERP bridge is stopped and will not start at sign-in. Run INSTALL_BRIDGE.bat to start it again.
pause

schtasks /Delete /TN "KMR ERP Bridge" /F >nul 2>&1
