# KMR universal ERP bridge: reads the ERP (READ ONLY, SELECT only) and sends it to KMR, where it is loaded into the matching apps
# (Sales Flow despatch, Sales Invoicing, Material Movement production, Delivery Challan & GRN, Operations Master, Calibration Hub).
# Nothing is ever duplicated: the server skips whatever is already loaded. Runs under 32-bit PowerShell (the MySQL ODBC driver is 32-bit).
#   -Test    check the ERP connection and the key; nothing is sent
#   -Full    read everything again from the beginning (safe to repeat)
param([switch]$Test, [switch]$Full)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$inv = [Globalization.CultureInfo]::InvariantCulture
$logPath = Join-Path $here 'erp-bridge.log'; $statusPath = Join-Path $here 'status.txt'
$created = $false; $mutex = New-Object System.Threading.Mutex($true, 'Local\KMRErpBridgeRun', [ref]$created); if (-not $created) { exit 0 }

function Log($m) {
  $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $inv) + ' ' + $m
  if ($Test) { $line }
  if ((Test-Path $logPath) -and ((Get-Item $logPath).Length -gt 3000000)) { Move-Item $logPath ($logPath + '.old') -Force }
  Add-Content -Path $logPath -Value $line
}
$script:status = @{}
if (Test-Path $statusPath) { foreach ($l in (Get-Content $statusPath)) { $i = $l.IndexOf(': '); if ($i -gt 0) { $script:status[$l.Substring(0, $i)] = $l.Substring($i + 2) } } }
function SetStatus($k, $v) { $script:status[$k] = $v; Set-Content -Path $statusPath -Value (($script:status.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Name + ': ' + $_.Value })) }
function J([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $c = [int]$ch
    if ($c -eq 34) { [void]$sb.Append('\"') } elseif ($c -eq 92) { [void]$sb.Append('\\') }
    elseif ($c -lt 32 -or $c -gt 126) { [void]$sb.Append('\u' + $c.ToString('x4')) } else { [void]$sb.Append($ch) }
  }
  '"' + $sb.ToString() + '"'
}
function N($x) { ([double]$x).ToString('0.######', $inv) }
function CellJ($v) {
  if ($null -eq $v -or $v -is [DBNull]) { return '""' }
  if ($v -is [DateTime]) { if ($v.Year -lt 1990) { return '""' }; return '"' + $v.ToString('yyyy-MM-dd', $inv) + '"' }
  if ($v -is [IFormattable]) { return (J ($v.ToString($null, $inv))) }
  J ("$v")
}
function FindDriver {
  foreach ($root in 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Drivers', 'HKLM:\SOFTWARE\Wow6432Node\ODBC\ODBCINST.INI\ODBC Drivers') {
    if (Test-Path $root) { $p = Get-ItemProperty $root; foreach ($n in ($p.PSObject.Properties | Where-Object { $_.Name -match 'MySQL' -and $_.Name -notmatch '^PS' })) { return $n.Name } }
  }
  $null
}
function BuildConn($file) {
  $sec = ((Get-Content (Join-Path $here $file)) | Out-String).Trim() | ConvertTo-SecureString
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  $p = $plain.Split([char]1)
  $drv = FindDriver; if (-not $drv) { throw 'MySQL ODBC driver not found on this PC' }
  'DRIVER={' + $drv + '};SERVER=' + $p[0] + ';PORT=' + $p[1] + ';DATABASE=' + $p[2] + ';UID=' + $p[3] + ';PWD={' + $p[4].Replace('}', '}}') + '};OPTION=3;'
}
function GzBytes([string]$s) {
  $b = [Text.Encoding]::UTF8.GetBytes($s); $ms = New-Object IO.MemoryStream
  $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress); $gz.Write($b, 0, $b.Length); $gz.Close()
  , $ms.ToArray()
}
function Post($url, $key, $body, [bool]$gzip) {   # WinHTTP, so it works with TLS 1.2 even on Windows 7
  $r = New-Object -ComObject WinHttp.WinHttpRequest.5.1
  try { [void]$r.GetType().InvokeMember('Option', [Reflection.BindingFlags]::SetProperty, $null, $r, @(9, 2688)) } catch { }
  $r.SetTimeouts(15000, 15000, 60000, 600000)
  $r.Open('POST', $url, $false)
  $r.SetRequestHeader('x-sync-key', $key)
  if ($gzip) { $r.SetRequestHeader('Content-Type', 'application/octet-stream'); $r.SetRequestHeader('x-body-gzip', '1'); $r.Send([byte[]](GzBytes $body)) }
  else { $r.SetRequestHeader('Content-Type', 'application/json'); $r.Send($body) }
  $script:httpStatus = [int]$r.Status; $script:httpText = [string]$r.ResponseText
}
function Short($s, $n) { if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }
function Sha($s) { [BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes($s))) -replace '-', '' }

$cfg = @{}
foreach ($l in (Get-Content (Join-Path $here 'config.txt'))) { if ($l -match '^\s*([A-Za-z]+)\s*=\s*(.+?)\s*$') { $cfg[$matches[1]] = $matches[2] } }
function Cfg($k, $d) { if ($cfg.ContainsKey($k)) { [int]$cfg[$k] } else { $d } }

# ---- which columns of each ERP table are sent (only what the converters need); the window column tells how far back an ordinary run reads
$W = @{
  invoicemaster = 'invno,invdate,pono,podate,custcode,dcno,dcdate,transth,transmode,Deliverytrm,Paytrm,Remarks,CGSTAMT,SGSTAMT,IGSTAMT,TcsAmt,gtotal,CANCELL'
  invoicedetail = 'invno,LINENO,prodcode,Desc1,Hsncode,uom1,qty,rate,Discounta,CGSTTAX,IGSTTAX,Taxablev,value,CGSTAMT,SGSTAMT,IGSTAMT,packing'
  customer = 'custcode,custname,address,CITY,Statecode,Billgstno,billpin,Country1'
  toolchanging = 'refno,refdate,prodcode,shift,machineno,operatorno,process,rmcode,batchno,hours,qtyprod,cycletime,barsused,scrap,EFFCY1,totalidlehrs,totalmchrs,plannedhrs,drea1,drea2,drea3,drea4,drea5,drea6,drea7,reasons'
  product = 'prodcode,prodname'
  dc = 'DCNO,DCDATE,DESCP11,QTY,DRGNO,DRGNO1,drgnodc,DESCP,REMARKS,DCBAL,unit1,HSNCode,Value1,Rate1,SUPPNAME,SUPPCODE,SUPPADD,GSTNo,TIN,vichicleno,modeofdsp,DRGNO11,PONO,PODATE'
  grn = 'INVNO,GRNDATE,PONO,SUPPLIER,SUPPCODE,QTY,REJQTY,ACCQTY,rmname,RMCODE,RATE,BATCH,RMTYPE,REASONREJ,poqty,pobal,grnstatus,GRN,TOTALAMT'
  grnno = 'GRNNO,GRNDATE,SINVNO,INVNO,GRNSTATUS,invdate'
  grndc = 'GRNNO,DCNO'
  suppliercm = 'suppcode,suppname,address,contactperson,contactno,panno,HIDE1'
  instruments = 'INSTCODE,DESCP,CALIBRATION1,SCRAP1,INSTSTATUS,LOCATION1,MAKE1,IDSLNO,RANGE1,LEASTCOUNT1,CUSTCODE,PURDATE,REFNO,SCRAPDATE,calibdate,duedate,PONO'
  calibstock = 'instcode,calibdate,duedate'
  receiptcalib = 'INSTCODE,ISSDATE,SUBCONTCODE'
  inhousecalib = 'INSTCODE,ISSDATE'
  historycard = 'instcode,recfromcalib,instdate,certificateno,remarks'
  subcontractor = 'subcontcode,subcontname'
  supplier = 'suppcode,suppname'
}
# reads one table: returns @{ cols = actual column names; rows = JSON row texts; k1 / k2 = values of two key columns for grouping }
function ReadTable($c, $sql, $name, $key1, $key2) {
  $cmd = $c.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 600
  $rd = $cmd.ExecuteReader()
  $want = @{}; foreach ($w in $W[$name].Split(',')) { $want[$w.ToLower()] = $true }
  $idx = @(); $cols = @(); $i1 = -1; $i2 = -1
  for ($i = 0; $i -lt $rd.FieldCount; $i++) {
    $n = $rd.GetName($i)
    if ($want.ContainsKey($n.ToLower())) { $idx += $i; $cols += $n }
    if ($key1 -and $n.ToLower() -eq $key1.ToLower()) { $i1 = $i }
    if ($key2 -and $n.ToLower() -eq $key2.ToLower()) { $i2 = $i }
  }
  $rows = New-Object System.Collections.ArrayList; $k1 = New-Object System.Collections.ArrayList; $k2 = New-Object System.Collections.ArrayList
  while ($rd.Read()) {
    $sb = New-Object System.Text.StringBuilder; [void]$sb.Append('[')
    $first = $true
    foreach ($i in $idx) { $v = $null; try { $v = $rd.GetValue($i) } catch { $v = $null }; if (-not $first) { [void]$sb.Append(',') }; $first = $false; [void]$sb.Append((CellJ $v)) }
    [void]$sb.Append(']'); [void]$rows.Add($sb.ToString())
    if ($i1 -ge 0) { $v = $null; try { $v = $rd.GetValue($i1) } catch { }; [void]$k1.Add("$v".Trim()) }
    if ($i2 -ge 0) { $v = $null; try { $v = $rd.GetValue($i2) } catch { }; [void]$k2.Add("$v".Trim().ToUpper()) }
  }
  $rd.Close()
  @{ cols = $cols; rows = $rows; k1 = $k1; k2 = $k2 }
}
function TableJson($t, $from, $to) {   # rows from..to-1 of a table read by ReadTable
  $c = ($t.cols | ForEach-Object { J $_ }) -join ','
  $r = if ($to -gt $from) { [string]::Join(',', ($t.rows.GetRange($from, $to - $from).ToArray())) } else { '' }
  '{"c":[' + $c + '],"r":[' + $r + ']}'
}
function TableJsonList($t, $list) { $c = ($t.cols | ForEach-Object { J $_ }) -join ','; '{"c":[' + $c + '],"r":[' + [string]::Join(',', @($list)) + ']}' }
function Body($kind, $unit, $tablesJson) { '{"kind":"' + $kind + '","unit":' + (J $unit) + ',"dryRun":false,"tables":{' + $tablesJson + '}}' }

# ---- per unit state: when each kind last ran, and the fingerprint of what was sent
function LoadState($path) { $s = @{}; if (Test-Path $path) { foreach ($l in (Get-Content $path)) { $p = $l.Split('|'); if ($p.Count -ge 4) { $s[$p[0]] = @($p[1], $p[2], $p[3]) } } }; $s }
function SaveState($path, $s) { Set-Content -Path $path -Value ($s.GetEnumerator() | ForEach-Object { $_.Name + '|' + $_.Value[0] + '|' + $_.Value[1] + '|' + $_.Value[2] }) }
$nowTicks = [DateTime]::UtcNow.Ticks
function Due($s, $kind, $minutes) { if ($Full -or -not $s.ContainsKey($kind)) { return $true }; (($nowTicks - [int64]$s[$kind][0]) -ge ([int64]$minutes * 600000000)) }
function NeedFull($s, $kind) { if ($Full -or -not $s.ContainsKey($kind)) { return $true }; (($nowTicks - [int64]$s[$kind][2]) -ge ([int64](Cfg 'fullEveryDays' 30) * 864000000000)) }

function SendKind($tag, $key, $kind, $unit, $bodies, $s, $statePath) {
  $all = [string]::Join('', $bodies); $sha = Sha $all
  $old = $null; if ($s.ContainsKey($kind)) { $old = $s[$kind] }
  $lastFull = $nowTicks; if ($old -and -not $script:wasFull) { $lastFull = $old[2] }
  if ($old -and $old[1] -eq $sha -and -not $Full) { $s[$kind] = @($nowTicks, $sha, $old[2]); SaveState $statePath $s; SetStatus ($unit + ' ' + $kind) ('unchanged ' + (Get-Date).ToString('HH:mm')); return $true }
  $n = 0; $last = ''
  foreach ($b in $bodies) {
    Post (Url) $key $b $true
    if ($script:httpStatus -ne 200 -or $script:httpText -notmatch '"ok"\s*:\s*true') { throw ($kind + ': server answered ' + $script:httpStatus + ' ' + (Short $script:httpText 300)) }
    $n++; $last = $script:httpText
  }
  $s[$kind] = @($nowTicks, $sha, $lastFull); SaveState $statePath $s
  Log ($tag + $kind + ' sent ' + $n + ' part(s): ' + (Short $last 300))
  SetStatus ($unit + ' ' + $kind) ('sent ' + (Get-Date).ToString('HH:mm') + ' (' + $n + ' parts)')
  $true
}
function Url { $cfg['bridgeUrl'] }

# ---- the Sales Flow despatch feed (same rules as before: invoices of the last weeks; the server adds them to what was typed)
function SyncDespatch($c, $tag, $key, $statePath) {
  $start = [datetime]::ParseExact($cfg['despatchStartDate'], 'yyyy-MM-dd', $inv)
  $from = (Get-Date).Date.AddDays(-(Cfg 'despatchLookbackDays' 40)); if ($from -lt $start) { $from = $start }; $f = $from.ToString('yyyy-MM-dd', $inv)
  function QD($sql) { $cmd = $c.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 120; $t = New-Object System.Data.DataTable; [void](New-Object System.Data.Odbc.OdbcDataAdapter($cmd)).Fill($t); , $t }
  $masters = QD "SELECT invno,invdate,custcode,CANCELL FROM invoicemaster WHERE invdate>='$f'"
  $details = QD "SELECT invno,prodcode,Desc1,uom1,rate,qty,CANCELL FROM invoicedetail WHERE invdate>='$f'"
  $labour = QD "SELECT invno,prodcode,uom1,rate,qty FROM linvoicedetail WHERE invdate>='$f'"
  $custs = QD 'SELECT custcode,custname FROM customer'; $prods = QD 'SELECT prodcode,prodname FROM product'
  $custName = @{}; foreach ($r in $custs.Rows) { $custName["$($r['custcode'])"] = "$($r['custname'])".Trim() }
  $prodName = @{}; foreach ($r in $prods.Rows) { $prodName["$($r['prodcode'])"] = "$($r['prodname'])".Trim() }
  $live = @{}; foreach ($m in $masters.Rows) { if ("$($m['CANCELL'])" -eq 'NO' -and $m['invdate'] -isnot [DBNull]) { $live["$($m['invno'])"] = $m } }
  $rows = @()
  foreach ($set in @($details, $labour)) {
    foreach ($d in $set.Rows) {
      $m = $live["$($d['invno'])"]
      if (-not $m -or $d['qty'] -is [DBNull] -or [double]$d['qty'] -le 0 -or "$($d['prodcode'])".Trim() -eq '') { continue }
      if ($set.Columns.Contains('CANCELL') -and "$($d['CANCELL'])" -ne 'NO') { continue }
      $code = "$($m['custcode'])".Trim(); $part = "$($d['prodcode'])".Trim(); $rate = 0.0; if ($d['rate'] -isnot [DBNull]) { $rate = [double]$d['rate'] }
      $json = '{"invno":' + (J "$($d['invno'])") + ',"invdate":"' + ([datetime]$m['invdate']).ToString('yyyy-MM-dd', $inv) + '","custcode":' + (J $code) + ',"custname":' + (J $custName[$code]) +
        ',"part_code":' + (J $part) + ',"part_name":' + (J $prodName["$($d['prodcode'])"]) + ',"uom":' + (J "$($d['uom1'])".Trim()) + ',"rate":' + (N $rate) + ',"qty":' + (N $d['qty']) + '}'
      $rows += New-Object PSObject -Property @{ invno = "$($d['invno'])"; part = $part; qty = [double]$d['qty']; json = $json }
    }
  }
  $sorted = @($rows | Sort-Object invno, part, qty)
  $arr = '[' + (($sorted | ForEach-Object { $_.json }) -join ',') + ']'
  $sha = Sha ($f + $arr)
  $old = ''; if (Test-Path $statePath) { $old = ((Get-Content $statePath) | Out-String).Trim() }
  $changed = ($Full -or $old -ne $sha)
  $body = if ($changed) { '{"from":"' + $f + '","rows":' + $arr + ',"dryRun":false,"force":false}' } else { '{"from":"' + $f + '","rows":null,"dryRun":false,"force":false}' }
  Post $cfg['despatchUrl'] $key $body $false
  if ($script:httpStatus -ne 200) { throw ('despatch: server answered ' + $script:httpStatus + ' ' + (Short $script:httpText 300)) }
  if ($changed) { Set-Content -Path $statePath -Value $sha; Log ($tag + 'despatch sent ' + $sorted.Count + ' lines: ' + (Short $script:httpText 250)) }
  SetStatus ($tag.Trim('[', ']', ' ') + ' despatch') ('ok ' + (Get-Date).ToString('HH:mm'))
}

function SyncUnit($name, $dsn, $keyfile) {
  $tag = '[' + $name + '] '; $key0 = $keyfile.Replace('.dat', ''); $statePath = Join-Path $here ('state-' + $key0 + '.txt'); $dsPath = Join-Path $here ('state-despatch-' + $key0 + '.txt')
  $failed = 0
  try {
    $key = ((Get-Content (Join-Path $here $keyfile)) | Out-String).Trim() | ConvertTo-SecureString
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($key))
    $cs = $(if ($dsn.StartsWith('CONN:')) { BuildConn $dsn.Substring(5) } else { 'DSN=' + $dsn }); $c = New-Object System.Data.Odbc.OdbcConnection($cs); $c.Open()
  } catch { Log ($tag + 'FAILED to connect: ' + $_.Exception.Message); SetStatus $name 'cannot connect'; return 1 }
  try {
    if ($Test) {
      Post (Url) $key ('{"kind":"ping","unit":' + (J $name) + ',"tables":{}}') $false
      Log ($tag + 'key check: ' + $script:httpStatus + ' ' + (Short $script:httpText 200))
      foreach ($t in 'invoicemaster', 'toolchanging', 'grn', 'dc', 'instruments') { try { $m = $c.CreateCommand(); $m.CommandText = 'SELECT COUNT(*) FROM ' + $t; Log ($tag + $t + ': ' + $m.ExecuteScalar() + ' rows') } catch { Log ($tag + $t + ': not found') } }
      return 0
    }
    $s = LoadState $statePath
    $kinds = @('despatch', 'invoices', 'production', 'purchase', 'opsmaster', 'calibration')
    foreach ($kind in $kinds) {
      try {
        $script:wasFull = $false
        if ($kind -eq 'despatch') { SyncDespatch $c $tag $key $dsPath; continue }
        $mins = $(switch ($kind) { 'invoices' { Cfg 'everyMinutesInvoices' 15 } 'production' { Cfg 'everyMinutesProduction' 30 } 'purchase' { Cfg 'everyMinutesPurchase' 360 } 'opsmaster' { Cfg 'everyMinutesOpsMaster' 720 } default { Cfg 'everyMinutesCalibration' 720 } })
        if (-not (Due $s $kind $mins)) { continue }
        $fullNow = NeedFull $s $kind; $script:wasFull = $fullNow
        $bodies = @()
        if ($kind -eq 'invoices') {
          $since = $(if ($fullNow) { '1990-01-01' } else { (Get-Date).Date.AddDays(-(Cfg 'invoiceLookbackDays' 60)).ToString('yyyy-MM-dd', $inv) })
          $m = ReadTable $c "SELECT * FROM invoicemaster WHERE invdate>='$since'" 'invoicemaster' 'invno' 'custcode'
          $d = ReadTable $c "SELECT * FROM invoicedetail WHERE invdate>='$since'" 'invoicedetail' 'invno' $null
          $cu = ReadTable $c 'SELECT * FROM customer' 'customer' 'custcode' $null
          $byInv = @{}; for ($i = 0; $i -lt $d.rows.Count; $i++) { $k = $d.k1[$i]; if (-not $byInv.ContainsKey($k)) { $byInv[$k] = New-Object System.Collections.ArrayList }; [void]$byInv[$k].Add($d.rows[$i]) }
          $byCu = @{}; for ($i = 0; $i -lt $cu.rows.Count; $i++) { $byCu[$cu.k1[$i].ToUpper()] = $cu.rows[$i] }
          for ($a = 0; $a -lt $m.rows.Count; $a += 250) {
            $b = [Math]::Min($a + 250, $m.rows.Count); $dl = New-Object System.Collections.ArrayList; $cl = New-Object System.Collections.ArrayList; $seen = @{}
            for ($i = $a; $i -lt $b; $i++) { if ($byInv.ContainsKey($m.k1[$i])) { [void]$dl.AddRange($byInv[$m.k1[$i]]) }; $cc = $m.k2[$i]; if (-not $seen.ContainsKey($cc) -and $byCu.ContainsKey($cc)) { $seen[$cc] = 1; [void]$cl.Add($byCu[$cc]) } }
            $bodies += (Body 'invoices' $name ('"invoicemaster":' + (TableJson $m $a $b) + ',"invoicedetail":' + (TableJsonList $d $dl) + ',"customer":' + (TableJsonList $cu $cl)))
          }
        }
        elseif ($kind -eq 'production') {
          $since = $(if ($fullNow) { '1990-01-01' } else { (Get-Date).Date.AddDays(-(Cfg 'productionLookbackDays' 45)).ToString('yyyy-MM-dd', $inv) })
          $pr = ReadTable $c 'SELECT * FROM product' 'product' $null $null
          $tc = ReadTable $c "SELECT * FROM toolchanging WHERE refdate>='$since'" 'toolchanging' $null $null
          $sets = @(); $sets += , @('toolchanging', $tc)
          if ($fullNow) { try { $to = ReadTable $c 'SELECT * FROM toolchangingold' 'toolchanging' $null $null; $sets += , @('toolchangingold', $to) } catch { Log ($tag + 'toolchangingold not found, skipped') } }
          foreach ($st in $sets) { $t = $st[1]; for ($a = 0; $a -lt $t.rows.Count; $a += 4000) { $b = [Math]::Min($a + 4000, $t.rows.Count); $bodies += (Body 'production' $name ('"' + $st[0] + '":' + (TableJson $t $a $b) + ',"product":' + (TableJson $pr 0 $pr.rows.Count))) } }
        }
        elseif ($kind -eq 'purchase') {
          $t = ''
          foreach ($n in 'dc', 'grn', 'grnno', 'grndc', 'suppliercm') { $x = ReadTable $c ('SELECT * FROM ' + $n) $n $null $null; if ($t -ne '') { $t += ',' }; $t += '"' + $n + '":' + (TableJson $x 0 $x.rows.Count) }
          $bodies += (Body 'purchase' $name $t)
        }
        elseif ($kind -eq 'opsmaster') {
          $t = ''
          foreach ($n in 'customer', 'pomaster', 'tpomaster', 'tcustprod', 'product', 'subcontractor', 'supplier', 'machine', 'trawmaterial', 'rawmaterial', 'tproduct') { $x = ReadTable $c ('SELECT * FROM ' + $n) $n $null $null; if ($t -ne '') { $t += ',' }; $t += '"' + $n + '":' + (TableJson $x 0 $x.rows.Count) }
          $bodies += (Body 'opsmaster' $name $t)
        }
        else {
          $t = ''
          foreach ($n in 'instruments', 'calibstock', 'receiptcalib', 'inhousecalib', 'historycard', 'subcontractor', 'supplier') { $x = ReadTable $c ('SELECT * FROM ' + $n) $n $null $null; if ($t -ne '') { $t += ',' }; $t += '"' + $n + '":' + (TableJson $x 0 $x.rows.Count) }
          $g = ReadTable $c 'SELECT * FROM grn WHERE RATE>0' 'grn' $null $null; $t += ',"grn":' + (TableJson $g 0 $g.rows.Count)
          $bodies += (Body 'calibration' $name $t)
        }
        [void](SendKind $tag $key $kind $name $bodies $s $statePath)
      } catch { $failed++; Log ($tag + $kind + ' FAILED: ' + $_.Exception.Message); SetStatus ($name + ' ' + $kind) ('FAILED ' + (Get-Date).ToString('HH:mm') + ' - ' + (Short $_.Exception.Message 120)) }
    }
  } finally { $c.Close() }
  $failed
}

$bad = 0
foreach ($l in (Get-Content (Join-Path $here 'units.txt'))) {
  if ($l.Trim() -eq '' -or $l.Trim().StartsWith('#')) { continue }
  $p = $l.Split('|')
  $bad += [int](SyncUnit $p[0].Trim() $p[1].Trim() $p[2].Trim() | Select-Object -Last 1)
}
if ($bad -gt 0) { exit 1 }
