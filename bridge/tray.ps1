# KMR universal ERP bridge - status icon next to the clock. Runs the bridge every 5 minutes, starts with Windows, no window.
# Green = fine, amber = working now, red = a problem. Right-click: Show status / Run now / Read everything again / Open log / Exit.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\KMRErpBridgeTray', [ref]$created)
if (-not $created) { exit }
$ps = 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if ((Test-Path (Join-Path $dir 'use64.txt')) -or -not (Test-Path $ps)) { $ps = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' }
$logPath = Join-Path $dir 'erp-bridge.log'; $statusPath = Join-Path $dir 'status.txt'

function MakeIcon($color) {
  $bmp = New-Object System.Drawing.Bitmap 16, 16
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $color), 1, 1, 13, 13)
  $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 1), 1, 1, 13, 13)
  $g.Dispose(); [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$iGreen = MakeIcon ([System.Drawing.Color]::FromArgb(34, 160, 80)); $iRed = MakeIcon ([System.Drawing.Color]::FromArgb(214, 48, 49)); $iAmber = MakeIcon ([System.Drawing.Color]::FromArgb(240, 160, 20))

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $iAmber; $tray.Visible = $true; $tray.Text = 'KMR ERP bridge: starting...'
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$mStatus = $menu.Items.Add('KMR ERP bridge'); $mStatus.Enabled = $false
[void]$menu.Items.Add('-')
$mShow = $menu.Items.Add('Show status'); $mNow = $menu.Items.Add('Run now'); $mFull = $menu.Items.Add('Read everything again'); $mLog = $menu.Items.Add('Open log'); $mExit = $menu.Items.Add('Exit (stops the bridge)')
$tray.ContextMenuStrip = $menu

$script:proc = $null; $script:state = ''
function StartRun($full) {
  if ($script:proc -and -not $script:proc.HasExited) { return }
  $tray.Icon = $iAmber; $tray.Text = 'KMR ERP bridge: working...'; $mStatus.Text = 'Working...'
  $a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $dir 'bridge.ps1') + '"')); if ($full) { $a += '-Full' }
  $script:proc = Start-Process $ps -ArgumentList $a -WindowStyle Hidden -PassThru
  $null = $script:proc.Handle
}
function Short($s) { if ($s.Length -gt 62) { $s.Substring(0, 62) } else { $s } }
function StatusText { if (Test-Path $statusPath) { ((Get-Content $statusPath) -join "`n") } else { 'No run yet.' } }
$poll = New-Object System.Windows.Forms.Timer; $poll.Interval = 1000
$poll.Add_Tick({
  if ($script:proc -and $script:proc.HasExited) {
    $code = $script:proc.ExitCode; $script:proc = $null; $t = (Get-Date).ToString('HH:mm')
    if ($code -eq 0) { $tray.Icon = $iGreen; $tray.Text = Short ('KMR ERP bridge OK - last run ' + $t); $mStatus.Text = 'OK - last run ' + $t; $script:state = 'ok' }
    else {
      $why = ''; if (Test-Path $logPath) { $why = (Get-Content $logPath -Tail 8 | Where-Object { $_ -match 'FAILED' } | Select-Object -Last 1) }
      $tray.Icon = $iRed; $tray.Text = Short ('KMR ERP bridge problem at ' + $t + ' - see log'); $mStatus.Text = 'Problem at ' + $t
      if ($script:state -ne 'fail') { $tray.ShowBalloonTip(8000, 'KMR ERP bridge', $(if ($why) { $why } else { 'Open the log for details.' }), 'Warning') }
      $script:state = 'fail'
    }
  }
})
$every = New-Object System.Windows.Forms.Timer; $every.Interval = 300000; $every.Add_Tick({ StartRun $false })
$first = New-Object System.Windows.Forms.Timer; $first.Interval = 4000; $first.Add_Tick({ $first.Stop(); StartRun $false })
$mNow.Add_Click({ StartRun $false }); $mFull.Add_Click({ StartRun $true }); $mLog.Add_Click({ if (Test-Path $logPath) { Start-Process notepad.exe $logPath } })
$mShow.Add_Click({ $tray.ShowBalloonTip(15000, 'KMR ERP bridge', (StatusText), 'Info') })
$tray.Add_DoubleClick({ $tray.ShowBalloonTip(15000, 'KMR ERP bridge', (StatusText), 'Info') })
$mExit.Add_Click({ $tray.Visible = $false; $tray.Dispose(); [System.Windows.Forms.Application]::Exit() })
$poll.Start(); $every.Start(); $first.Start()
[System.Windows.Forms.Application]::Run()
