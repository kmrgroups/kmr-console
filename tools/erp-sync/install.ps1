# Installs the ERP sync for the signed-in Windows user (the ERP's ODBC connection belongs to that user).
# Run in a normal PowerShell window at the plant. It asks for the key from Sales Flow > Daily despatch > ERP sync.
#   -NoSchedule : copy files and store the key, but do not start the 5-minute task yet (use this to preview first).
param([string]$StartDate = '2026-11-01', [string]$Dsn = 'ESBEE', [int]$Minutes = 5, [switch]$NoSchedule)
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $env:LOCALAPPDATA 'KMR\ErpSync'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
foreach ($f in 'erp-sync.ps1', 'run-hidden.vbs') { Copy-Item (Join-Path $src $f) $dst -Force }

$cfg = Get-Content (Join-Path $src 'config.example.json') -Raw | ConvertFrom-Json
$cfg.dsn = $Dsn; $cfg.startDate = $StartDate
$cfg | ConvertTo-Json | Set-Content (Join-Path $dst 'config.json') -Encoding ASCII

# Stored encrypted so that only this Windows user on this PC can read it.
$secure = Read-Host 'Paste the ERP sync key' -AsSecureString
$secure | ConvertFrom-SecureString | Set-Content (Join-Path $dst 'key.dat') -Encoding ASCII

if ($NoSchedule) { "Installed in $dst. The task was not started."; exit 0 }
schtasks.exe /Create /TN 'KMR ERP Sales Flow Sync' /SC MINUTE /MO $Minutes /TR "wscript.exe //B `"$dst\run-hidden.vbs`"" /RL LIMITED /F | Out-Null
"Installed in $dst. Runs every $Minutes minutes while you are signed in to Windows. Log: $dst\erp-sync.log"
"To stop it: schtasks /Delete /TN `"KMR ERP Sales Flow Sync`" /F"
