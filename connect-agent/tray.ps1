# KMR Connect helper - status icon next to the clock. Starts the helper hidden, restarts it if it stops, starts with Windows, no window.
# Green = ready, red = someone is working on this computer now, amber = starting, grey-red = a problem.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\KMRConnectTray', [ref]$created)
if (-not $created) { exit }
$ps = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$logPath = Join-Path $dir 'connect.log'; $statePath = Join-Path $dir 'state.txt'
function MakeIcon($color) {
  $bmp = New-Object System.Drawing.Bitmap 16, 16
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $color), 1, 1, 13, 13)
  $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 1), 1, 1, 13, 13)
  $g.Dispose(); [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$iGreen = MakeIcon ([System.Drawing.Color]::FromArgb(34, 160, 80)); $iRed = MakeIcon ([System.Drawing.Color]::FromArgb(214, 48, 49)); $iAmber = MakeIcon ([System.Drawing.Color]::FromArgb(240, 160, 20))
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $iAmber; $tray.Visible = $true; $tray.Text = 'KMR Connect: starting...'
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$mStatus = $menu.Items.Add('KMR Connect'); $mStatus.Enabled = $false
[void]$menu.Items.Add('-')
$mLog = $menu.Items.Add('Open log'); $mRe = $menu.Items.Add('Restart the helper'); $mExit = $menu.Items.Add('Exit (stop the helper)')
$tray.ContextMenuStrip = $menu
$script:proc = $null; $script:last = ''
function StartAgent {
  if ($script:proc -and -not $script:proc.HasExited) { return }
  $script:proc = Start-Process $ps -ArgumentList @('-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $dir 'agent.ps1') + '"')) -WindowStyle Hidden -PassThru
}
function StopAgent {
  try { if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill() } } catch { }
  foreach ($p in (Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match [regex]::Escape((Join-Path $dir 'profile')) -or $_.CommandLine -match 'KMR\\Connect\\agent\.ps1' })) { try { [void]$p.Terminate() } catch { } }
}
$poll = New-Object System.Windows.Forms.Timer; $poll.Interval = 2000
$poll.Add_Tick({
  if (-not $script:proc -or $script:proc.HasExited) { $tray.Icon = $iAmber; $tray.Text = 'KMR Connect: restarting...'; StartAgent; return }
  $s = ''; if (Test-Path $statePath) { $s = (Get-Content $statePath -ErrorAction SilentlyContinue | Select-Object -First 1) }
  if ($s -eq $script:last) { return }; $script:last = $s
  if ($s -like 'session|*') { $who = $s.Substring(8); $tray.Icon = $iRed; $tray.Text = 'KMR Connect: ' + $who + ' is working on this computer'; $mStatus.Text = 'In use by ' + $who; $tray.ShowBalloonTip(6000, 'KMR Connect', $who + ' is now working on this computer.', 'Info') }
  elseif ($s -like 'problem|*') { $tray.Icon = $iRed; $tray.Text = 'KMR Connect problem: ' + $s.Substring(8); $mStatus.Text = 'Problem: ' + $s.Substring(8) }
  elseif ($s -eq 'online') { $tray.Icon = $iGreen; $tray.Text = 'KMR Connect: ready'; $mStatus.Text = 'Ready' }
  else { $tray.Icon = $iAmber; $tray.Text = 'KMR Connect: starting...'; $mStatus.Text = 'Starting...' }
})
$mLog.Add_Click({ if (Test-Path $logPath) { Start-Process notepad.exe $logPath } })
$mRe.Add_Click({ StopAgent; $script:proc = $null; StartAgent })
$mExit.Add_Click({ $poll.Stop(); StopAgent; $tray.Visible = $false; [System.Windows.Forms.Application]::Exit() })
StartAgent; $poll.Start()
[System.Windows.Forms.Application]::Run()
