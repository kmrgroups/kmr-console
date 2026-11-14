# Installs the KMR Connect helper for the signed-in Windows user: pairs this computer with the code shown in KMR Connect > Remote devices,
# then makes the helper start by itself, hidden, every time this user signs in to Windows.
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $env:LOCALAPPDATA 'KMR\Connect'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
foreach ($p in (Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match 'KMR\\Connect' -and $_.ProcessId -ne $PID })) { try { [void]$p.Terminate() } catch { } }
foreach ($f in 'agent.ps1', 'tray.ps1', 'tray-hidden.vbs', 'config.txt') { Copy-Item (Join-Path $src $f) $dst -Force }
$cfg = @{}; foreach ($l in (Get-Content (Join-Path $dst 'config.txt'))) { if ($l -match '^\s*([A-Za-z]+)\s*=\s*(.+?)\s*$') { $cfg[$matches[1]] = $matches[2] } }
''; 'KMR Connect helper setup'; '-------------------------'
'In KMR Apps open KMR Connect > Remote devices > + Add a laptop or PC. It shows a Device ID and a pairing code.'; ''
$id = (Read-Host 'Type the Device ID').Trim()
$code = (Read-Host 'Type the pairing code (like ABCD-2345)').Trim()
'Contacting KMR...'
$pc = Invoke-RestMethod -Uri ($cfg.site + '/it/console/api/public-config') -UseBasicParsing
$h = @{ apikey = $pc.key; Authorization = 'Bearer ' + $pc.key }
$url = $(if ($pc.url) { $pc.url } else { 'https://dehlcusptkzfhqvpfyjh.supabase.co' })
try {
  $r = Invoke-RestMethod -Method Post -Uri ($url + '/rest/v1/rpc/kmr_cn_agent_pair') -Headers $h -ContentType 'application/json' -Body (@{ p_device = $id; p_code = $code } | ConvertTo-Json) -UseBasicParsing
} catch {
  $msg = $_.ErrorDetails.Message; if ($msg) { try { $msg = ($msg | ConvertFrom-Json).message } catch { } } else { $msg = $_.Exception.Message }
  Write-Host ('Pairing failed: ' + $msg) -ForegroundColor Red; exit 1
}
if ($r.error) { Write-Host ('Pairing failed: ' + $r.error) -ForegroundColor Red; exit 1 }
@{ device = $r.device; name = $r.name; company = $r.company; secret = $r.secret; site = $cfg.site; url = $url; key = $pc.key } | ConvertTo-Json | Set-Content (Join-Path $dst 'device.json')
(ConvertTo-SecureString $r.token -AsPlainText -Force) | ConvertFrom-SecureString | Set-Content (Join-Path $dst 'token.dat')
('Paired as "' + $r.name + '" for ' + $r.company)
$psx = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$tr = '"' + $psx + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $dst 'tray.ps1') + '"'
$ok = $false
try { & schtasks /Create /TN 'KMR Connect' /TR $tr /SC ONLOGON /RL LIMITED /F 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $ok = $true } } catch { }
if ($ok) { try { & schtasks /Run /TN 'KMR Connect' 2>&1 | Out-Null } catch { $ok = $false } }
if (-not $ok) {
  $startup = [Environment]::GetFolderPath('Startup')
  $sh = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'KMR Connect.lnk'))
  $sh.TargetPath = 'wscript.exe'; $sh.Arguments = '//B "' + (Join-Path $dst 'tray-hidden.vbs') + '"'; $sh.WorkingDirectory = $dst; $sh.WindowStyle = 7; $sh.Save()
  Start-Process 'wscript.exe' ('//B "' + (Join-Path $dst 'tray-hidden.vbs') + '"')
}
''; 'Done. Look for the small KMR Connect icon next to the clock (it may be under the ^ arrow).'
'Open KMR Apps > KMR Connect > Remote devices: this computer shows Online within a minute.'
'It starts by itself whenever you sign in to Windows.'
