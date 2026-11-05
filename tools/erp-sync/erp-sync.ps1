# KMR ERP -> Sales Flow sync. Runs at the plant every few minutes under 32-bit PowerShell (the MySQL ODBC driver is 32-bit).
# It only reads from the ERP: single-table SELECTs, no joins, so people saving invoices are not held up.
#   -LocalPreview    read the ERP and print what would be sent; nothing leaves this PC
#   -ServerPreview   send it and get the matching report back; nothing is saved
param([switch]$LocalPreview, [switch]$ServerPreview, [switch]$Force)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Get-Content (Join-Path $here 'config.json') -Raw | ConvertFrom-Json
$statePath = Join-Path $here 'state.txt'; $keyPath = Join-Path $here 'key.dat'; $logPath = Join-Path $here 'erp-sync.log'
$inv = [Globalization.CultureInfo]::InvariantCulture

function Log($m) {
  $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $inv) + ' ' + $m
  if ($LocalPreview -or $ServerPreview) { $line }
  if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 2MB) { Move-Item $logPath "$logPath.old" -Force }
  Add-Content -Path $logPath -Value $line -Encoding UTF8
}
function Q($c, $sql) {
  $cmd = $c.CreateCommand(); $cmd.CommandText = $sql; $t = New-Object System.Data.DataTable
  (New-Object System.Data.Odbc.OdbcDataAdapter($cmd)).Fill($t) | Out-Null; , $t
}

try {
  # Look back over the last weeks so edited or cancelled invoices are corrected, never before the agreed start date.
  $start = [datetime]::ParseExact($cfg.startDate, 'yyyy-MM-dd', $inv)
  $from = (Get-Date).Date.AddDays(-[int]$cfg.lookbackDays); if ($from -lt $start) { $from = $start }
  $f = $from.ToString('yyyy-MM-dd', $inv)

  $c = New-Object System.Data.Odbc.OdbcConnection("DSN=$($cfg.dsn)"); $c.Open()
  try {
    $masters = Q $c "SELECT invno,invdate,custcode,CANCELL FROM invoicemaster WHERE invdate>='$f'"
    $details = Q $c "SELECT invno,prodcode,Desc1,uom1,rate,qty,CANCELL FROM invoicedetail WHERE invdate>='$f'"
    $labour  = Q $c "SELECT invno,prodcode,uom1,rate,qty FROM linvoicedetail WHERE invdate>='$f'"
    $custs   = Q $c "SELECT custcode,custname FROM customer"
    $prods   = Q $c "SELECT prodcode,prodname FROM product"
  } finally { $c.Close() }

  $custName = @{}; foreach ($r in $custs) { $custName["$($r.custcode)"] = "$($r.custname)".Trim() }
  $prodName = @{}; foreach ($r in $prods) { $prodName["$($r.prodcode)"] = "$($r.prodname)".Trim() }
  $live = @{}; foreach ($m in $masters) { if ("$($m.CANCELL)" -eq 'NO' -and $m.invdate -isnot [DBNull]) { $live["$($m.invno)"] = $m } }

  $rows = New-Object System.Collections.ArrayList
  foreach ($set in @($details, $labour)) {
    foreach ($d in $set) {
      $m = $live["$($d.invno)"]
      if (-not $m -or $d.qty -is [DBNull] -or [double]$d.qty -le 0 -or "$($d.prodcode)".Trim() -eq '') { continue }
      if ($d.Table.Columns.Contains('CANCELL') -and "$($d.CANCELL)" -ne 'NO') { continue }
      $code = "$($m.custcode)".Trim(); $part = "$($d.prodcode)".Trim()
      $rate = 0.0; if ($d.rate -isnot [DBNull]) { $rate = [double]$d.rate }
      [void]$rows.Add([ordered]@{ invno = "$($d.invno)"; invdate = ([datetime]$m.invdate).ToString('yyyy-MM-dd', $inv); custcode = $code; custname = $custName[$code]
        part_code = $part; part_name = $prodName["$($d.prodcode)"]; uom = "$($d.uom1)".Trim(); rate = $rate; qty = [double]$d.qty })
    }
  }
  $sorted = @($rows | Sort-Object { $_.invno }, { $_.part_code }, { $_.qty })
  $json = ConvertTo-Json -InputObject $sorted -Depth 3 -Compress
  $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($f + $json))) -replace '-', ''

  if ($LocalPreview) {
    Log "PREVIEW from $f : $($live.Count) live invoices, $($sorted.Count) lines"
    $sorted | Group-Object { $_.invdate } | Sort-Object Name | Select-Object -Last 8 | ForEach-Object { "  {0}: {1} lines, qty {2}" -f $_.Name, $_.Count, (($_.Group | ForEach-Object { $_.qty } | Measure-Object -Sum).Sum) }
    $sorted | Group-Object { $_.custcode } | Sort-Object Count -Descending | ForEach-Object { "  {0}: {1} lines" -f $_.Name, $_.Count }
    "  sample: " + (ConvertTo-Json -InputObject $sorted[0] -Compress)
    "  payload size: $([Math]::Round($json.Length / 1KB)) KB"
    exit 0
  }

  $changed = $ServerPreview -or $Force -or -not (Test-Path $statePath) -or ((Get-Content $statePath -Raw).Trim() -ne $sha)
  $key = (New-Object System.Net.NetworkCredential('', (Get-Content $keyPath -Raw | ConvertTo-SecureString))).Password
  $flags = ',"dryRun":' + $(if ($ServerPreview) { 'true' } else { 'false' }) + ',"force":' + $(if ($Force) { 'true' } else { 'false' })
  $body = if ($changed) { '{"from":"' + $f + '","rows":' + $json + $flags + '}' } else { '{"from":"' + $f + '","rows":null' + $flags + '}' }

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $res = Invoke-RestMethod -Method Post -Uri $cfg.url -Headers @{ 'x-sync-key' = $key } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 90
  if ($ServerPreview) { $res | ConvertTo-Json -Depth 5; exit 0 }
  if ($changed) { Set-Content -Path $statePath -Value $sha -Encoding ASCII }
  if ($changed -or $res.lines_review -gt 0) {
    Log "ok sent=$changed lines=$($sorted.Count) changed=$($res.invoices_changed) removed=$($res.invoices_removed) added=$($res.plan_lines_added) written=$($res.despatch_written) review=$($res.lines_review)"
  }
} catch {
  # Next run tries again. The key is never logged.
  Log ("FAILED: " + $_.Exception.Message)
  exit 1
}
