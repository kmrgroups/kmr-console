# Installs the KMR universal ERP bridge for the signed-in Windows user (the ERP's connections belong to that user), tests it, and makes it
# start by itself, hidden, every time this user signs in. The sync keys and ERP connections already set up for the older Sales Flow sync are reused.
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $env:LOCALAPPDATA 'KMR\ErpBridge'
$old = Join-Path $env:LOCALAPPDATA 'KMR\ErpSync'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
# stop an older sync or bridge that is running
foreach ($p in (Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match 'ErpSync|ErpBridge|erp-sync\.ps1' -and $_.ProcessId -ne $PID })) { try { [void]$p.Terminate() } catch { } }
foreach ($t in 'KMR ERP Sales Flow Sync', 'KMR ERP Sales Flow Sync Tray', 'KMR ERP Bridge') { try { & schtasks /Delete /TN $t /F 2>&1 | Out-Null } catch { } }
foreach ($f in 'bridge.ps1', 'tray.ps1', 'tray-hidden.vbs', 'config.txt') { Copy-Item (Join-Path $src $f) $dst -Force }
$units = Join-Path $dst 'units.txt'
if (-not (Test-Path $units)) {
  if (Test-Path (Join-Path $old 'units.txt')) {
    Copy-Item (Join-Path $old 'units.txt') $units -Force
    foreach ($f in (Get-ChildItem $old -Filter '*.dat')) { Copy-Item $f.FullName $dst -Force }
    'Reusing the ERP connections and keys of the older sync: ' + ((Get-Content $units | Where-Object { $_ -match '\|' } | ForEach-Object { $_.Split('|')[0] }) -join ', ')
  } else {
    $lines = @('# name | ERP connection on this PC | file that holds that unit''s sync key')
    $seen = @{}
    foreach ($root in 'HKCU:\SOFTWARE\ODBC\ODBC.INI', 'HKLM:\SOFTWARE\ODBC\ODBC.INI', 'HKLM:\SOFTWARE\Wow6432Node\ODBC\ODBC.INI') {
      if (Test-Path $root) { foreach ($k in (Get-ChildItem $root)) {
        if ($k.PSChildName -eq 'ODBC Data Sources') { continue }
        $p = Get-ItemProperty $k.PSPath; $db = "$($p.Database)$($p.DATABASE)"; if ($db -eq '' -or $seen.ContainsKey($k.PSChildName)) { continue }
        $seen[$k.PSChildName] = 1
        $guess = $(if ($db -match '3') { 'Unit-3' } elseif ($db -match '1') { 'Unit-1' } else { 'Unit-2' })
        $u = Read-Host ('ERP connection "' + $k.PSChildName + '" (database ' + $db + ') - which unit is it? Type Unit-1, Unit-2 or Unit-3 [' + $guess + '], or - to skip')
        if ($u -eq '') { $u = $guess }; if ($u -eq '-') { continue }
        $kf = 'key-' + $u.ToLower().Replace('-', '') + '.dat'
        $s = Read-Host ('Paste the sync key for ' + $u + ' (Sales Flow > Daily despatch > New key)') -AsSecureString
        if ($s.Length -gt 0) { $s | ConvertFrom-SecureString | Set-Content (Join-Path $dst $kf) }
        $lines += ($u + '|' + $k.PSChildName + '|' + $kf)
      } }
    }
    Set-Content $units $lines
  }
}
# 32-bit or 64-bit view of the ERP connections: use the one that works
$flag = Join-Path $dst 'use64.txt'
if (Test-Path (Join-Path $old 'use64.txt')) { Copy-Item (Join-Path $old 'use64.txt') $flag -Force } elseif ([IntPtr]::Size -eq 8 -and -not (Test-Path 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe')) { Set-Content $flag '64' }
$psx = 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'; if ((Test-Path $flag) -or -not (Test-Path $psx)) { $psx = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' }
''; 'Testing the ERP connection and the key. Nothing is sent yet...'
$out = Join-Path $src 'ERP_bridge_test_result.txt'
& $psx -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dst 'bridge.ps1') -Test 2>&1 | Tee-Object -FilePath $out
# starts by itself (hidden) whenever this Windows user signs in
$startup = [Environment]::GetFolderPath('Startup')
$sh = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'KMR ERP Bridge.lnk'))
$sh.TargetPath = 'wscript.exe'; $sh.Arguments = '//B "' + (Join-Path $dst 'tray-hidden.vbs') + '"'; $sh.WorkingDirectory = $dst; $sh.WindowStyle = 7; $sh.Save()
Start-Process 'wscript.exe' ('//B "' + (Join-Path $dst 'tray-hidden.vbs') + '"')
''; 'Done. Look near the clock (click the ^ arrow if it is hidden): a round icon - green = fine, amber = working now, red = a problem.'
'It starts by itself, hidden, every time this Windows user signs in. The first run reads the whole ERP history, so give it some time.'
'Please send ERP_bridge_test_result.txt.'
