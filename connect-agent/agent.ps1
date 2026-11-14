# KMR Connect helper - runs hidden on the laptop / PC that is worked on from KMR Apps.
#  - tells the platform every 30 seconds that this computer is awake
#  - keeps a small private browser window open that shows the screen to the signed-in viewer (video goes straight between the two computers)
#  - does what the viewer asks on THIS computer: mouse, keyboard, files and folders, programs, clipboard
# It only listens on this computer itself (127.0.0.1) and only answers requests that carry this device's private key.
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $dir 'connect.log'; $statePath = Join-Path $dir 'state.txt'
$cfg = @{}; foreach ($l in (Get-Content (Join-Path $dir 'config.txt'))) { if ($l -match '^\s*([A-Za-z]+)\s*=\s*(.+?)\s*$') { $cfg[$matches[1]] = $matches[2] } }
$dev = Get-Content (Join-Path $dir 'device.json') -Raw | ConvertFrom-Json
$token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Get-Content (Join-Path $dir 'token.dat') | ConvertTo-SecureString)))
$secret = $dev.secret; $port = [int]$cfg.port; $dport = [int]$cfg.debugPort; $site = $dev.site
function Log($m) {
  try { if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1MB) { Move-Item $logPath ($logPath + '.old') -Force }; Add-Content $logPath ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m) } catch { }
}
function State($s) { try { Set-Content $statePath $s } catch { } }

Add-Type -AssemblyName System.Windows.Forms, Microsoft.VisualBasic
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KW {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [StructLayout(LayoutKind.Sequential)] public struct MI { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct KI { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct IU { [FieldOffset(0)] public MI mi; [FieldOffset(0)] public KI ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public IU u; }
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] i, int size);
  public static void Uni(char c) {
    INPUT[] a = new INPUT[2]; a[0].type = 1; a[0].u.ki.wScan = c; a[0].u.ki.dwFlags = 4; a[1] = a[0]; a[1].u.ki.dwFlags = 6;
    SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Key(int vk, bool down, bool ext) {
    uint f = (down ? 0u : 2u) | (ext ? 1u : 0u); keybd_event((byte)vk, (byte)MapVirtualKey((uint)vk, 0), f, UIntPtr.Zero);
  }
}
'@
[void][KW]::SetProcessDPIAware()
$script:sessionWho = ''

# ---------- what the viewer can ask for ----------
function Out-Items($path) {
  if (-not $path) {
    $items = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { @{ name = ($_.Name + ':\'); dir = $true; size = $null; mtime = $null } })
    return @{ path = ''; items = $items }
  }
  $p = (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
  $all = @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Sort-Object @{ e = { -not $_.PSIsContainer } }, Name | Select-Object -First 2000)
  $items = @($all | ForEach-Object { @{ name = $_.Name; dir = [bool]$_.PSIsContainer; size = $(if ($_.PSIsContainer) { $null } else { $_.Length }); mtime = $_.LastWriteTime.ToString('s') } })
  return @{ path = $p; items = $items }
}
function Handle($o) {
  switch ($o.op) {
    'info' {
      return @{ w = [KW]::GetSystemMetrics(0); h = [KW]::GetSystemMetrics(1); left = 0; top = 0; user = $env:USERNAME; host = $env:COMPUTERNAME; os = [Environment]::OSVersion.VersionString }
    }
    'mouse' {
      [void][KW]::SetCursorPos([int]$o.x, [int]$o.y)
      $b = [int]$o.b; $dn = @(2, 0x20, 8)[$b]; $up = @(4, 0x40, 0x10)[$b]
      if ($o.a -eq 'down') { [KW]::mouse_event($dn, 0, 0, 0, [UIntPtr]::Zero) }
      elseif ($o.a -eq 'up') { [KW]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero) }
      elseif ($o.a -eq 'wheel') { [KW]::mouse_event(0x800, 0, 0, [int](-1.2 * [double]$o.dy), [UIntPtr]::Zero) }
      return @{ ok = $true }
    }
    'key' { [KW]::Key([int]$o.vk, [bool]$o.down, [bool]$o.ext); return @{ ok = $true } }
    'char' { [KW]::Uni([char]([string]$o.ch)[0]); return @{ ok = $true } }
    'text' { foreach ($c in ([string]$o.s).ToCharArray()) { if ($c -eq "`n") { [KW]::Key(13, $true, $false); [KW]::Key(13, $false, $false) } elseif ($c -ne "`r") { [KW]::Uni($c) } }; Log ('typed ' + ([string]$o.s).Length + ' characters'); return @{ ok = $true } }
    'ls' { Log ('list ' + $o.path); return (Out-Items ([string]$o.path)) }
    'read' {
      $fs = [IO.File]::Open([string]$o.path, 'Open', 'Read', 'ReadWrite')
      try {
        [void]$fs.Seek([int64]$o.off, 'Begin'); $n = [int]$o.len; $buf = New-Object byte[] $n; $got = $fs.Read($buf, 0, $n)
        if ([int64]$o.off -eq 0) { Log ('download ' + $o.path) }
        return @{ b64 = [Convert]::ToBase64String($buf, 0, $got); size = $fs.Length; eof = (([int64]$o.off + $got) -ge $fs.Length) }
      } finally { $fs.Dispose() }
    }
    'write' {
      $mode = $(if ($o.first) { 'Create' } else { 'OpenOrCreate' })
      $fs = [IO.File]::Open([string]$o.path, $mode, 'Write', 'Read')
      try { [void]$fs.Seek([int64]$o.off, 'Begin'); $b = [Convert]::FromBase64String([string]$o.b64); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
      if ($o.first) { Log ('upload ' + $o.path) }
      return @{ ok = $true }
    }
    'mkdir' { Log ('new folder ' + $o.path); [void](New-Item -ItemType Directory -Force -LiteralPath ([string]$o.path)); return @{ ok = $true } }
    'ren' { Log ('rename ' + $o.path + ' -> ' + $o.to); Rename-Item -LiteralPath ([string]$o.path) -NewName ([string]$o.to) -ErrorAction Stop; return @{ ok = $true } }
    'del' {
      Log ('delete (recycle bin) ' + $o.path); $p = [string]$o.path
      if (Test-Path -LiteralPath $p -PathType Container) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin') }
      else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin') }
      return @{ ok = $true }
    }
    'start' { Log ('open ' + $o.path); $a = @{ FilePath = [string]$o.path }; if ($o.args) { $a.ArgumentList = [string]$o.args }; Start-Process @a -ErrorAction Stop; return @{ ok = $true } }
    'run' {
      Log ('run [' + $o.shell + '] ' + $o.cmd)
      $psi = New-Object Diagnostics.ProcessStartInfo
      if ($o.shell -eq 'cmd') { $psi.FileName = 'cmd.exe'; $psi.Arguments = '/c ' + [string]$o.cmd }
      else { $psi.FileName = 'powershell.exe'; $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + '"' + ([string]$o.cmd).Replace('"', '\"') + '"' }
      $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
      $pr = [Diagnostics.Process]::Start($psi); $so = $pr.StandardOutput.ReadToEndAsync(); $se = $pr.StandardError.ReadToEndAsync()
      $t = [Math]::Min([int]$o.timeout, 80); if ($t -lt 1) { $t = 30 }
      if (-not $pr.WaitForExit($t * 1000)) { try { $pr.Kill() } catch { }; return @{ out = ''; err = 'Stopped: it ran longer than ' + $t + ' seconds.'; code = -1 } }
      $out = $so.Result; $err = $se.Result; if ($out.Length -gt 200000) { $out = $out.Substring(0, 200000) + "`n[cut]" }
      return @{ out = $out; err = $err; code = $pr.ExitCode }
    }
    'ps' { $it = @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 150 | ForEach-Object { @{ id = $_.Id; name = $_.ProcessName; mb = [Math]::Round($_.WorkingSet64 / 1MB); title = $_.MainWindowTitle } }); return @{ items = $it } }
    'clip_get' { return @{ text = [string](Get-Clipboard -Raw) } }
    'clip_set' { Set-Clipboard -Value ([string]$o.text); Log 'clipboard set'; return @{ ok = $true } }
    'session' {
      if ($o.on) { $script:sessionWho = [string]$o.who; Log ('SESSION START - viewer ' + $script:sessionWho); State ('session|' + $script:sessionWho) }
      else { Log 'SESSION END'; State 'online'; $script:sessionWho = '' }
      return @{ ok = $true }
    }
    default { throw ('Unknown request: ' + $o.op) }
  }
}

# ---------- the local door (127.0.0.1 only) ----------
$listener = New-Object Net.HttpListener
$listener.Prefixes.Add('http://127.0.0.1:' + $port + '/')
try { $listener.Start() } catch { Log ('FAILED to listen on port ' + $port + ': ' + $_.Exception.Message); State 'problem|port busy'; exit 2 }
function Reply($ctx, $obj, $code) {
  $r = $ctx.Response; $r.StatusCode = $code
  $r.Headers.Add('Access-Control-Allow-Origin', $site); $r.Headers.Add('Access-Control-Allow-Private-Network', 'true'); $r.Headers.Add('Access-Control-Allow-Headers', '*'); $r.Headers.Add('Access-Control-Allow-Methods', 'POST, OPTIONS')
  $b = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 6 -Compress)); $r.ContentType = 'application/json'; $r.ContentLength64 = $b.Length
  try { $r.OutputStream.Write($b, 0, $b.Length) } catch { }; try { $r.Close() } catch { }
}
function Serve($ctx) {
  $rq = $ctx.Request
  if ($rq.HttpMethod -eq 'OPTIONS') { Reply $ctx @{ ok = $true } 200; return }
  $org = $rq.Headers['Origin']
  if ($rq.UserHostName -notmatch '^(127\.0\.0\.1|localhost)(:\d+)?$' -or ($org -and $org -ne $site)) { Reply $ctx @{ error = 'Not allowed.' } 403; return }
  try {
    $sr = New-Object IO.StreamReader($rq.InputStream, [Text.Encoding]::UTF8); $o = $sr.ReadToEnd() | ConvertFrom-Json
    if ($o.key -ne $secret) { Reply $ctx @{ error = 'Wrong key.' } 403; return }
    Reply $ctx (Handle $o) 200
  } catch { Log ('ERROR ' + $_.Exception.Message); Reply $ctx @{ error = $_.Exception.Message } 200 }
}

# ---------- the private screen window ----------
$script:edge = $null; $script:edgeAt = [DateTime]::MinValue; $script:kick = [DateTime]::MinValue
function BrowserPath {
  foreach ($p in "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") { if (Test-Path $p) { return $p } }
  return $null
}
function StartBrowser {
  $exe = BrowserPath; if (-not $exe) { Log 'FAILED: Microsoft Edge or Google Chrome was not found.'; State 'problem|no browser'; return }
  $url = $site + '/it/connect-host.html#k=' + $secret + '&a=' + $port + '&n=' + [Uri]::EscapeDataString([string]$dev.name)
  $args = @('--app=' + $url, '--user-data-dir=' + (Join-Path $dir 'profile'), '--lang=en-US', '--no-first-run', '--no-default-browser-check', '--auto-select-desktop-capture-source=Entire screen',
    '--remote-debugging-port=' + $dport, '--remote-allow-origins=*', '--window-position=-3000,-3000', '--window-size=420,300',
    '--disable-features=LocalNetworkAccessChecks,PrivateNetworkAccessSendPreflights,BlockInsecurePrivateNetworkRequests,CalculateNativeWinOcclusion', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--disable-background-timer-throttling')
  $script:edge = Start-Process $exe -ArgumentList $args -WindowStyle Minimized -PassThru; $script:edgeAt = Get-Date; $script:kick = (Get-Date).AddSeconds(8); Log 'screen window started'
}
function StopBrowser { try { if ($script:edge -and -not $script:edge.HasExited) { $script:edge.Kill() } } catch { }; foreach ($p in (Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match [regex]::Escape((Join-Path $dir 'profile')) })) { try { [void]$p.Terminate() } catch { } }; $script:edge = $null }
# the browser only lets a page start screen sharing after a click: this makes that click for the private window (Chrome DevTools protocol)
function Cdp($expr) {
  try {
    $pages = Invoke-RestMethod ('http://127.0.0.1:' + $dport + '/json') -TimeoutSec 3; $pg = $pages | Where-Object { $_.type -eq 'page' -and $_.url -match 'connect-host' } | Select-Object -First 1; if (-not $pg) { return $null }
    $ws = New-Object Net.WebSockets.ClientWebSocket; $ct = New-Object Threading.CancellationTokenSource 8000
    $ws.ConnectAsync([Uri]$pg.webSocketDebuggerUrl, $ct.Token).Wait()
    $msg = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; userGesture = $true; awaitPromise = $true; returnByValue = $true } } | ConvertTo-Json -Depth 5 -Compress
    $b = [Text.Encoding]::UTF8.GetBytes($msg); $ws.SendAsync((New-Object ArraySegment[byte] (, $b)), 'Text', $true, $ct.Token).Wait()
    $buf = New-Object byte[] 65536; $r = $ws.ReceiveAsync((New-Object ArraySegment[byte] (, $buf)), $ct.Token); $r.Wait(); $txt = [Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)
    try { $ws.CloseAsync('NormalClosure', '', $ct.Token).Wait() } catch { }; return $txt
  } catch { return $null }
}

# ---------- tell the platform we are awake ----------
$script:lastPing = [DateTime]::MinValue; $script:fails = 0
function Ping {
  $script:lastPing = Get-Date
  try {
    $h = @{ apikey = $dev.key; Authorization = 'Bearer ' + $dev.key }
    $info = @{ host = $env:COMPUTERNAME; user = $env:USERNAME; os = [Environment]::OSVersion.VersionString; v = '1.0' }
    $r = Invoke-RestMethod -Method Post -Uri ($dev.url + '/rest/v1/rpc/kmr_cn_agent_ping') -Headers $h -ContentType 'application/json' -Body (@{ p_device = $dev.device; p_token = $token; p_info = $info } | ConvertTo-Json -Depth 4) -TimeoutSec 20
    $script:fails = 0
    if (-not $r.ok) { Log ('platform says: ' + $r.reason); if ($r.reason -eq 'disabled') { StopBrowser; State 'problem|switched off by the administrator' } else { StopBrowser; State 'problem|not paired any more' }; return }
    if ($r.secret -and $r.secret -ne $secret) { Log 'channel key changed'; $script:secret = $r.secret; StopBrowser }
    if (-not $script:sessionWho) { State 'online' }
    if (-not $script:edge -or $script:edge.HasExited) { if (((Get-Date) - $script:edgeAt).TotalSeconds -gt 10) { StartBrowser } }
  } catch { $script:fails++; if ($script:fails -ge 3) { State 'problem|no internet' }; Log ('ping failed: ' + $_.Exception.Message) }
}

Log ('KMR Connect helper started for "' + $dev.name + '"'); State 'starting'
Ping
$wait = $null
while ($true) {
  if (-not $wait) { $wait = $listener.BeginGetContext($null, $null) }
  if ($wait.AsyncWaitHandle.WaitOne(500)) { $ctx = $listener.EndGetContext($wait); $wait = $null; Serve $ctx }
  if (((Get-Date) - $script:lastPing).TotalSeconds -ge 30) { Ping }
  if ($script:edge -and -not $script:edge.HasExited -and -not $script:sessionWho -and (Get-Date) -gt $script:kick) {
    $res = Cdp "(function(){var b=document.getElementById('go');if(b&&!b.hidden){window.kmrStart();return 'started'}return 'ok'})()"
    $script:kick = (Get-Date).AddSeconds($(if ($res -match 'started') { 4 } else { 20 }))
  }
}
