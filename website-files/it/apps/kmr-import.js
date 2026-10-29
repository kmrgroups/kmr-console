/* KMR invoice / despatch file reader - shared by Sales Flow (and any app that needs to pull quantities from an ERP report).
   It does NOT depend on one fixed layout. It finds, by itself:
     - the header row (Part no, Qty, Customer, Date ... in any order, any wording, any column);
     - customer names, either in a Customer column or as "CUSTOMER : xyz" lines above each block (block reports);
     - the report period ("FROM 01-10-2026 TO 24-10-2026") or a date on every invoice row.
   If it cannot find something, the screen lets the user point to the column and the same reader is re-run (override "ov").
   Works in the browser (window.KMRImport) and in Node (module.exports) so it can be tested. */
(function (root) {
  'use strict';
  var STOP = { limited: 1, ltd: 1, pvt: 1, private: 1, llp: 1, co: 1, company: 1, corp: 1, corporation: 1, inc: 1, the: 1, and: 1, of: 1, india: 1, m: 1, s: 1, ms: 1 };
  var MON = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12 };
  var p2 = function (n) { return (n < 10 ? '0' : '') + n; };
  var norm = function (s) { return String(s == null ? '' : s).toUpperCase().replace(/[^A-Z0-9]/g, ''); };       // "F 002 B13 180" = "F002B13180"
  var hnorm = function (s) { return String(s == null ? '' : s).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim(); };
  function txt(v) { if (v == null) return ''; if (typeof v === 'number') return isFinite(v) ? (Math.abs(v - Math.round(v)) < 1e-9 ? String(Math.round(v)) : String(v)) : ''; return String(v).replace(/\s+/g, ' ').trim(); }
  function num(v) {
    if (typeof v === 'number') return isFinite(v) ? v : null;
    if (typeof v !== 'string') return null;
    var s = v.replace(/[,\s]/g, ''), neg = /^\(.*\)$/.test(s); s = s.replace(/[()]/g, '');
    return /^-?\d+(\.\d+)?$/.test(s) ? (neg ? -1 : 1) * parseFloat(s) : null;
  }
  function ymd(y, m, d) {
    y = +y; m = +m; d = +d; if (y < 100) y += 2000; if (y < 1990 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    var dt = new Date(Date.UTC(y, m - 1, d)); return dt.getUTCMonth() === m - 1 ? y + '-' + p2(m) + '-' + p2(d) : null;
  }
  /* any common date style -> YYYY-MM-DD (day first, as used in India); numbers are Excel date serials */
  function dateOf(v, allowSerial) {
    if (v == null || v === '') return null;
    if (v instanceof Date) return isNaN(v) ? null : ymd(v.getUTCFullYear(), v.getUTCMonth() + 1, v.getUTCDate());
    if (typeof v === 'number') { if (!allowSerial || v < 30000 || v > 80000) return null; var d = new Date(Date.UTC(1899, 11, 30) + Math.floor(v) * 864e5); return ymd(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()); }
    var s = String(v).trim().replace(/[T ]\d{1,2}:\d{2}(:\d{2})?.*$/, ''), m;
    if ((m = /^(\d{4})[-\/.](\d{1,2})[-\/.](\d{1,2})$/.exec(s))) return ymd(m[1], m[2], m[3]);
    if ((m = /^(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{2,4})$/.exec(s))) return ymd(m[3], m[2], m[1]);
    if ((m = /^(\d{1,2})[-\/. ]([A-Za-z]{3,9})[-\/., ]+(\d{2,4})$/.exec(s))) { var mn = MON[m[2].slice(0, 3).toLowerCase()]; if (mn) return ymd(m[3], mn, m[1]); }
    return null;
  }
  /* what is this header cell? */
  function kind(h) {
    h = hnorm(h); if (!h) return null;
    if (/\b(customer|buyer|party|consignee|client|sold to|bill to|ship to)\b/.test(h)) return /\b(code|gst|gstin|address|id|no)\b/.test(h) ? null : 'cust';
    if (/\b(name|desc|description)\b/.test(h)) return 'name';
    var c = h.replace(/ /g, '');
    if (/^(part|item|material|product|article|component|drawing|drg|sku)( (no|number|code|id))?$/.test(h) || /\b(part|item|material|product|drg|drawing|article)\b.*\b(no|number|code|id)\b/.test(h) || /^(partno|itemcode|itemno|partcode|partnumber|materialcode|productcode|drgno)$/.test(c)) return 'part';
    if (/\b(qty|quantity|nos|pcs|units?)\b/.test(h) && !/rate|price|value|amount|uom|pending|balance|order|ordered|schedule|plan|stock/.test(h)) return 'qty';
    if (/(^|\b)(date|dt)\b/.test(h) && !/due|delivery|expiry|mfg|manufactur|order|po\b/.test(h)) return 'date';
    return null;
  }
  var CUSTLABEL = /^(customer|buyer|party|consignee|client|sold to|bill to|ship to)(\s*name)?\s*[:\-]\s*(.*)$/i, CUSTONLY = /^(customer|buyer|party|consignee|client|sold to|bill to|ship to)(\s*name)?\s*$/i;

  function headerMap(row) {
    var m = {}, qs = -1;
    for (var i = 0; i < row.length; i++) {
      var raw = txt(row[i]); if (!raw) continue; var k = kind(raw); if (!k) continue;
      if (k === 'qty') { var sc = /inv|disp|desp|bill|ship|sale|sold/i.test(raw) ? 2 : 1; if (sc > qs) { m.qty = i; qs = sc; } }
      else if (m[k] == null) m[k] = i;
    }
    return m.part != null && m.qty != null ? m : null;
  }
  function colName(i) { var s = ''; i++; while (i > 0) { var r = (i - 1) % 26; s = String.fromCharCode(65 + r) + s; i = Math.floor((i - 1) / 26); } return s; }

  /* rows = array of arrays (sheet_to_json header:1). ov (optional) = { headerRow:0-based, part, name, qty, customer, date : column index or null } */
  function parseSheet(rows, ov) {
    var out = { records: [], period: null, title: '', cols: null, headerRow: -1, mode: 'cumulative', warnings: [], rowCount: rows.length }, cols = null, cust = '', alias = [], firstHdr = -1, i, j;
    ov = ov || {};
    if (ov.headerRow != null) { cols = { part: ov.part, name: ov.name, qty: ov.qty, cust: ov.customer, date: ov.date }; firstHdr = ov.headerRow; }
    else for (i = 0; i < rows.length; i++) if (headerMap(rows[i] || [])) { firstHdr = i; break; }
    out.headerRow = firstHdr;
    var top = Math.min(firstHdr < 0 ? 12 : firstHdr, 15), ds = [];
    for (i = 0; i < top; i++) for (j = 0; j < (rows[i] || []).length; j++) {
      var c = rows[i][j]; if (typeof c !== 'string') continue;
      if (!out.title && /[A-Za-z]{3,}/.test(c) && !/report|from|^to$/i.test(c) && !CUSTLABEL.test(c) && !CUSTONLY.test(c.trim())) out.title = txt(c);
      var d = dateOf(c, false); if (d) ds.push(d);
    }
    if (ds.length) { ds.sort(); out.period = { from: ds.length > 1 ? ds[0] : null, to: ds[ds.length - 1] }; }
    for (i = 0; i < rows.length; i++) {
      var row = rows[i] || [];
      if (ov.headerRow != null) { if (i <= ov.headerRow) continue; }
      else { var hm = headerMap(row); if (hm) { cols = { part: hm.part, name: hm.name, qty: hm.qty, cust: hm.cust, date: hm.date }; out.cols = out.cols || cols; continue; } }
      var found = false;                                                                  /* "CUSTOMER : name" line above a block */
      for (j = 0; j < row.length && !found; j++) {
        var t = txt(row[j]), mm = CUSTLABEL.exec(t), only = !mm && CUSTONLY.exec(t);
        if (mm || only) {
          var names = []; if (mm && mm[3]) names.push(mm[3]);
          for (var k = j + 1; k < row.length; k++) { var u = txt(row[k]); if (u && num(u) === null) names.push(u); }
          if (names.length) { cust = names[0]; alias = names.slice(1); found = true; }
        }
      }
      if (found || !cols) continue;
      var part = txt(row[cols.part]), q = num(row[cols.qty]);
      if (!part || q === null || q === 0 || /^(grand\s*)?total/i.test(part) || num(part) !== null && cols.part === cols.qty) continue;
      var rec = { customer: cols.cust != null ? (txt(row[cols.cust]) || cust) : cust, alias: cols.cust != null ? [] : alias, part: part, name: cols.name != null ? txt(row[cols.name]) : '', qty: q, date: cols.date != null ? dateOf(row[cols.date], true) : null, row: i + 1 };
      if (cols.date != null && !rec.date && txt(row[cols.date])) out.warnings.push('Row ' + (i + 1) + ': date "' + txt(row[cols.date]) + '" not understood');
      out.records.push(rec);
    }
    if (!out.cols) out.cols = cols;
    out.mode = out.records.some(function (r) { return r.date; }) ? 'daily' : 'cumulative';
    return out;
  }

  /* ---------- matching file rows to the sales plan ---------- */
  function toks(s) { return hnorm(s).split(' ').filter(function (t) { return t && !STOP[t]; }); }
  function sim(a, b) {
    if (!a.length || !b.length) return 0; var c = 0;
    a.forEach(function (x) { if (b.some(function (y) { return x === y || (x.length >= 5 && y.length >= 5 && x.slice(0, 5) === y.slice(0, 5)); })) c++; });
    return c / Math.min(a.length, b.length);
  }
  function custScore(rec, name) {
    var names = [rec.customer].concat(rec.alias || []).filter(Boolean); if (!names.length) return 1;
    var tb = toks(name); return Math.max.apply(null, names.map(function (n) { return sim(toks(n), tb); }));
  }
  /* lines = plan lines of the month {id,buyer_name,buyer_code,part_code}; parts = Operations Master parts (optional)
     status: ok | check (part found but customer differs / unclear) | new (in Operations Master, not in this month's plan) | none */
  function matchRecord(rec, lines, parts) {
    var key = norm(rec.part), cl = lines.filter(function (l) { return norm(l.part_code) === key; }), r = { rec: rec, status: 'none', line: null, cands: cl, part: null };
    if (cl.length) {
      var sc = cl.map(function (l) { return { l: l, s: custScore(rec, l.buyer_name) }; }).sort(function (a, b) { return b.s - a.s; });
      r.line = sc[0].l; r.cands = sc.map(function (x) { return x.l; });
      r.status = sc[0].s > 0 && (sc.length < 2 || sc[0].s > sc[1].s || !rec.customer) ? 'ok' : 'check'; return r;
    }
    var pl = (parts || []).filter(function (p) { return norm(p.part_code) === key; });
    if (pl.length) {
      var ps = pl.map(function (p) { return { p: p, s: custScore(rec, p.buyer_name) }; }).sort(function (a, b) { return b.s - a.s; });
      if (ps[0].s > 0) { r.part = ps[0].p; r.status = 'new'; }
    }
    return r;
  }

  /* ---------- turning quantities into despatch entries ----------
     items: [{line_id, qty, date, from, to, mode}]  desp: {line_id:{day:qty}}  opt: {month:'YYYY-MM', today:'YYYY-MM-DD'}
     daily       : the quantity is that day's despatch (rows of the same day add up; the day's entry is replaced - so a second upload never doubles).
     cumulative  : the quantity is the total for from..to. What is already entered for earlier days of that period is kept,
                   and only the difference goes on the "to" date - so uploading the same file again changes nothing, and a later file (to a later date) just tops up. */
  function buildWrites(items, desp, opt) {
    var rows = [], issues = [], per = {}, by = {}, mo = opt.month;
    items.forEach(function (it) { (by[it.line_id] = by[it.line_id] || []).push(it); });
    Object.keys(by).forEach(function (id) {
      var shadow = {}, mine = desp[id] || {}; Object.keys(mine).forEach(function (d) { shadow[d] = +mine[d]; });
      var before = 0; Object.keys(shadow).forEach(function (d) { if (d.slice(0, 7) === mo) before += shadow[d]; });
      var dayq = {}, cum = {};
      by[id].forEach(function (it) {
        if (it.mode === 'daily') { if (!it.date || it.date.slice(0, 7) !== mo) { per[id] = per[id] || {}; per[id].skipped = (per[id].skipped || 0) + 1; return; } dayq[it.date] = (dayq[it.date] || 0) + it.qty; }
        else { var k = it.from + '|' + it.to + '|' + (it.replace ? 1 : 0); cum[k] = cum[k] || { from: it.from, to: it.to, qty: 0, replace: !!it.replace }; cum[k].qty += it.qty; }
      });
      Object.keys(dayq).sort().forEach(function (d) {
        if (d > opt.today) { issues.push('Date ' + d + ' is in the future - skipped.'); return; }
        if (dayq[d] < 0) { issues.push('Negative quantity for ' + d + ' - skipped.'); return; }
        rows.push({ line_id: id, day: d, qty: dayq[d], before: shadow[d] || 0 }); shadow[d] = dayq[d];
      });
      Object.keys(cum).sort().forEach(function (k) {
        var c = cum[k];
        if (!c.to || c.to.slice(0, 7) !== mo) { issues.push('Report date ' + (c.to || '?') + ' is not in the month shown.'); return; }
        if (c.to > opt.today) { issues.push('Report date ' + c.to + ' is in the future - skipped.'); return; }
        var others = 0;
        Object.keys(shadow).forEach(function (d) {
          if (d >= c.from && d < c.to && shadow[d]) {
            if (c.replace) { rows.push({ line_id: id, day: d, qty: 0, before: shadow[d] }); shadow[d] = 0; } else others += shadow[d];   /* "replace": the file is the master for the whole period */
          }
        });
        var delta = Math.round((c.qty - others) * 1e6) / 1e6;
        if (delta < 0) { per[id] = per[id] || {}; per[id].low = others; return; }           /* entries already made exceed the file: change nothing, flag it */
        rows.push({ line_id: id, day: c.to, qty: delta, before: shadow[c.to] || 0 }); shadow[c.to] = delta;
      });
      var after = 0; Object.keys(shadow).forEach(function (d) { if (d.slice(0, 7) === mo) after += shadow[d]; });
      per[id] = per[id] || {}; per[id].before = before; per[id].after = after;
    });
    return { rows: rows, per: per, issues: issues };
  }

  var api = { norm: norm, dateOf: dateOf, parseSheet: parseSheet, matchRecord: matchRecord, buildWrites: buildWrites, colName: colName, kind: kind, custScore: custScore, headerMap: headerMap };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.KMRImport = api;
})(typeof window !== 'undefined' ? window : globalThis);
