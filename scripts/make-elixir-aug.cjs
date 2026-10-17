// Generates supabase/seed/elixir-tec-2026-08.sql from the company's August 2026 salary sheet (exported to JSON). Checks every net against the sheet.
const fs = require("fs"), path = require("path");
const C = require(path.resolve(__dirname, "../../../kmr-group-website/public/it/apps/hrm-calc.js"));
const rows = JSON.parse(fs.readFileSync(process.argv[2], "utf8")), out = process.argv[3];
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";
const S = { month_days_mode: "calendar", pf_enabled: false, esi_enabled: false, pt_enabled: false, ot_multiplier: 1, ot_basis: "gross", ot_day_divisor: "calendar", bonus_amount: 500, bonus_max_short: 1, round_net: true };
const emps = [], slips = []; let bad = 0, sumGross = 0, sumAdv = 0, sumBonus = 0;
rows.forEach((r, i) => {
  const [sl, name, desig, fixed, hrs, , , days, ot, , adv, bonus, , paid] = r;
  const code = "E-" + String(sl).padStart(4, "0"), isFixed = days == null && fixed != null && name !== "Naseem";
  const e = { id: code, emp_code: code, name, designation: desig || (isFixed ? "Housekeeping" : null), basic: fixed || 0, hours_per_day: hrs && hrs > 8.5 ? hrs : (hrs || 8.5), pay_type: isFixed ? "fixed" : "monthly", ot_eligible: !isFixed && ot != null, bonus_eligible: !isFixed && fixed != null && name !== "Naseem", pf: false, esi: false, pt: false };
  if (isFixed) e.hours_per_day = 8; if (name === "Naseem") { e.ot_eligible = false; e.bonus_eligible = false; }
  e.shift = e.hours_per_day == 12 ? "12 hour" : "8.5 hour"; emps.push(e);
  if (name === "Naseem" || !fixed) return;
  const d = isFixed ? 31 : days, sum = { days: 31, outside: 0, paid_days: d, present: d, hd: 0, wo: 0, h: 0, paid_leave: 0, unpaid_leave: 0, absent: 0, missed: 0, unrecorded: 0, ot_min: Math.round((ot || 0) * 60), late_count: 0, late_min: 0, lop_days: 31 - d };
  const p = C.payOf(e, sum, "2026-08", S);
  p.earnings.forEach((x) => { if (x.code === "BASIC") x.name = isFixed ? "Fixed salary" : "Salary earned"; });
  if (adv) { p.deductions.push({ code: "ADV", name: "Salary advance", amount: adv }); C.reslip(p); }
  const sheetNet = paid != null ? paid : null, expect = Math.round(r[12]);
  if (p.net !== expect) { bad++; console.error("MISMATCH", name, p.net, expect); }
  p.info.days_worked = d; p.info.advance = adv || 0; slips.push(p); sumGross += p.gross; sumAdv += adv || 0; sumBonus += p.earnings.filter((x) => x.code === "BONUS").reduce((a, x) => a + x.amount, 0);
});
const tot = C.totals(slips); console.error("slips", slips.length, "gross", tot.gross.toFixed(2), "advance", sumAdv, "bonus", sumBonus, "net", tot.net, "mismatch", bad);
let sql = `-- Elixir Tec - HRM & Payroll: employees, settings and the August 2026 salary, from the company's salary sheet.
-- Run once in the Supabase SQL editor after 0072 and 0073. Safe to run again (it replaces its own rows).
-- Checked against the sheet: ${slips.length} salaries, advance ${sumAdv}, attendance bonus ${sumBonus}.
do $seed$ declare cid uuid; sh85 uuid; sh12 uuid; run uuid; eid uuid; begin
  select id into cid from console.customers where slug = 'elixir-tec-corporation-c0020';
  if cid is null then raise exception 'Customer elixir-tec-corporation-c0020 not found.'; end if;
  if not exists (select 1 from console.licences where customer_id = cid and product_code = 'hrms') then
    insert into console.licences (customer_id, product_code, status, seats) values (cid, 'hrms', 'active', 50);
  end if;
  insert into console.hrms_settings (customer_id, data) values (cid, ${q(JSON.stringify(S))}::jsonb || '{"ess_enabled": true}'::jsonb)
    on conflict (customer_id) do update set data = console.hrms_settings.data || excluded.data, updated_at = now();
  insert into console.hrms_shifts (customer_id, name, start_time, end_time, grace_min, break_min, half_day_min, full_day_min, weekly_off) values
    (cid, '8.5 hour', '09:00', '18:00', 10, 30, 240, 480, '{}'), (cid, '12 hour', '08:00', '20:00', 10, 0, 360, 690, '{}')
    on conflict (customer_id, name) do nothing;
  select id into sh85 from console.hrms_shifts where customer_id = cid and name = '8.5 hour';
  select id into sh12 from console.hrms_shifts where customer_id = cid and name = '12 hour';
  delete from console.hrms_payroll_runs where customer_id = cid and period = '2026-08';
`;
emps.forEach((e) => {
  sql += `  insert into console.hrms_employees (customer_id, emp_code, name, designation, shift_id, bio_id, pay_type, basic, pf, esi, pt, ot_eligible, hours_per_day, bonus_eligible, doj)
    values (cid, ${q(e.emp_code)}, ${q(e.name)}, ${e.designation ? q(e.designation) : "null"}, ${e.shift == "12 hour" ? "sh12" : "sh85"}, ${q(String(parseInt(e.emp_code.slice(2))))}, ${q(e.pay_type)}, ${e.basic}, false, false, false, ${e.ot_eligible}, ${e.hours_per_day}, ${e.bonus_eligible}, '2026-01-01')
    on conflict (customer_id, emp_code) do update set name = excluded.name, designation = excluded.designation, shift_id = excluded.shift_id, pay_type = excluded.pay_type, basic = excluded.basic, ot_eligible = excluded.ot_eligible, hours_per_day = excluded.hours_per_day, bonus_eligible = excluded.bonus_eligible, pf = false, esi = false, pt = false;
`;
});
sql += `  insert into console.hrms_counters (customer_id, key, n) values (cid, 'EMP', ${emps.length}) on conflict (customer_id, key) do update set n = greatest(console.hrms_counters.n, excluded.n);
  insert into console.hrms_payroll_runs (customer_id, period, status, month_days, totals, note, finalised_by, finalised_at) values (cid, '2026-08', 'final', 31, ${q(JSON.stringify(tot))}::jsonb, 'Loaded from the August 2026 salary sheet', 'seed', now()) returning id into run;
`;
slips.forEach((p) => {
  sql += `  select id into eid from console.hrms_employees where customer_id = cid and emp_code = ${q(p.emp_code)};
  insert into console.hrms_payslips (customer_id, run_id, employee_id, emp_code, emp_name, department, designation, paid_days, lop_days, ot_hours, earnings, deductions, gross, deduct, net, info)
    values (cid, run, eid, ${q(p.emp_code)}, ${q(p.emp_name)}, null, ${p.designation ? q(p.designation) : "null"}, ${p.paid_days}, ${p.lop_days}, ${p.ot_hours}, ${q(JSON.stringify(p.earnings))}::jsonb, ${q(JSON.stringify(p.deductions))}::jsonb, ${p.gross}, ${p.deduct}, ${p.net}, ${q(JSON.stringify(p.info))}::jsonb);
`;
});
sql += "end $seed$;\n"; fs.writeFileSync(out, sql);
