-- =====================================================================
-- KMR platform — Operations Master sample data (M7c). Needs 0015 and 0016. Safe to re-run.
--  One consistent sample plant for all 13 lists (163 records): the Capacity Planner's 12 machines, 16 parts and
--  43 cycle times and its plant standards, plus customers, suppliers, raw materials, rate contracts, gauges, tools,
--  consumables, CFT team and IATF 16949 documents that refer to each other.
--  • KMR Apps › Operations Master › Load sample data / Flush sample data (Operations Master administrators).
--  • Every sample record is tagged (ops_records.sample). Flush deletes only tagged records.
--  • Load never overwrites: a code that already exists is skipped, and sample plant standards are skipped when
--    the company already has its own.
--  • Editing or importing over a sample record makes it the company's own record; Flush then leaves it alone.
--  • Dates (calibration, contracts, document reviews) are set relative to the day the sample is loaded.
-- =====================================================================
do $$ begin
  if to_regprocedure('public.kmr_capacity_masters(uuid)') is null then raise exception 'Run 0016_capacity_masters.sql first.'; end if;
end $$;

alter table console.ops_records add column if not exists sample boolean not null default false;
create index if not exists ops_records_sample on console.ops_records (customer_id) where sample;

-- The sample plant. Dates are "@<days from today>".
create or replace function console.ops_sample() returns jsonb
language sql immutable set search_path = console, public as $fn$
  select $sample$[
{"kind":"customers","code":"CUS-001","name":"Orion Motors Pvt Ltd","data":{"gstin":"29AAACO1234F1Z5","city":"Hosur","country":"India","contact":"Purchase — S. Ramesh","email":"purchase@orion-motors.example","phone":"+91 80000 10001","payment_terms":"60 days"}},
{"kind":"customers","code":"CUS-002","name":"Sunrise Tractors Ltd","data":{"gstin":"33AABCS5678K1Z2","city":"Chennai","country":"India","contact":"SQA — P. Latha","email":"sqa@sunrise-tractors.example","phone":"+91 80000 10002","payment_terms":"45 days"}},
{"kind":"customers","code":"CUS-003","name":"Vega Commercial Vehicles Ltd","data":{"gstin":"27AACCV9012M1Z8","city":"Pune","country":"India","contact":"Buyer — A. Kulkarni","email":"buyer@vega-cv.example","phone":"+91 80000 10003","payment_terms":"60 days"}},
{"kind":"customers","code":"CUS-004","name":"Nordhaus Hydraulics GmbH","data":{"city":"Stuttgart","country":"Germany","contact":"Supply chain — K. Weber","email":"scm@nordhaus.example","phone":"+49 711 000 0004","payment_terms":"90 days, EXW"}},
{"kind":"suppliers","code":"SUP-001","name":"Deccan Steel Bars Pvt Ltd","data":{"category":"Raw material","gstin":"29AACS4100Q1Z1","city":"Bengaluru","contact":"Sales desk","email":"sales1@supplier.example","phone":"+91 80000 20001","approved":"Yes","rating":92}},
{"kind":"suppliers","code":"SUP-002","name":"Kaveri Forgings Ltd","data":{"category":"Raw material","gstin":"29AACD4101Q1Z2","city":"Hosur","contact":"Key account","email":"sales2@supplier.example","phone":"+91 80000 20002","approved":"Yes","rating":88}},
{"kind":"suppliers","code":"SUP-003","name":"Trident Castings Pvt Ltd","data":{"category":"Raw material","gstin":"29AACK4102Q1Z3","city":"Coimbatore","contact":"Marketing","email":"sales3@supplier.example","phone":"+91 80000 20003","approved":"Conditional","rating":74}},
{"kind":"suppliers","code":"SUP-004","name":"Precise Heat Treaters","data":{"category":"Outsourced process","gstin":"29AACT4103Q1Z4","city":"Bengaluru","contact":"Plant head","email":"sales4@supplier.example","phone":"+91 80000 20004","approved":"Yes","rating":90}},
{"kind":"suppliers","code":"SUP-005","name":"Surface Finish Platers","data":{"category":"Outsourced process","gstin":"29AACP4104Q1Z5","city":"Bengaluru","contact":"Owner","email":"sales5@supplier.example","phone":"+91 80000 20005","approved":"Yes","rating":85}},
{"kind":"suppliers","code":"SUP-006","name":"Carbide Tooling Solutions","data":{"category":"Tooling","gstin":"29AACM4105Q1Z6","city":"Bengaluru","contact":"Sales engineer","email":"sales6@supplier.example","phone":"+91 80000 20006","approved":"Yes","rating":94}},
{"kind":"suppliers","code":"SUP-007","name":"Metrology Calibration Labs (NABL)","data":{"category":"Gauges & calibration","gstin":"29AACC4106Q1Z7","city":"Bengaluru","contact":"Lab manager","email":"sales7@supplier.example","phone":"+91 80000 20007","approved":"Yes","rating":96}},
{"kind":"suppliers","code":"SUP-008","name":"Coolant & Lubes Traders","data":{"category":"Consumables","gstin":"29AACL4107Q1Z8","city":"Bengaluru","contact":"Sales","email":"sales8@supplier.example","phone":"+91 80000 20008","approved":"Yes","rating":82}},
{"kind":"raw_materials","code":"RM-EN8-40","name":"EN8 bright bar Ø40","data":{"grade":"EN8 (080M40)","specification":"IS 1570 / BS 970","form":"Bar","size":"Ø40 × 3 m","supplier":"SUP-001","rate_per_kg":68}},
{"kind":"raw_materials","code":"RM-EN8-65","name":"EN8 bright bar Ø65","data":{"grade":"EN8 (080M40)","specification":"IS 1570 / BS 970","form":"Bar","size":"Ø65 × 3 m","supplier":"SUP-001","rate_per_kg":67}},
{"kind":"raw_materials","code":"RM-EN19-45","name":"EN19 bar Ø45","data":{"grade":"EN19 (42CrMo4)","specification":"BS 970 709M40","form":"Bar","size":"Ø45 × 3 m","supplier":"SUP-001","rate_per_kg":92}},
{"kind":"raw_materials","code":"RM-20MNCR5-F","name":"20MnCr5 gear blank forging","data":{"grade":"20MnCr5","specification":"DIN 17210","form":"Forging","size":"Ø110 × 38","supplier":"SUP-002","rate_per_kg":105}},
{"kind":"raw_materials","code":"RM-EN353-F","name":"EN353 shaft forging","data":{"grade":"EN353 (15NiCr1)","specification":"BS 970","form":"Forging","size":"Ø55 × 260","supplier":"SUP-002","rate_per_kg":112}},
{"kind":"raw_materials","code":"RM-FG260-C","name":"Grey iron casting FG260","data":{"grade":"FG260","specification":"IS 210","form":"Casting","size":"As per drawing","supplier":"SUP-003","rate_per_kg":78}},
{"kind":"raw_materials","code":"RM-SG500-C","name":"SG iron casting SG500/7","data":{"grade":"SG500/7","specification":"IS 1865","form":"Casting","size":"As per drawing","supplier":"SUP-003","rate_per_kg":96}},
{"kind":"parts","code":"DP-1101","name":"Drive Flange","data":{"customer":"CUS-001","drawing_no":"DRG-1101-A","revision":"C","material":"RM-EN8-65","weight_kg":1.8,"annual_volume":99600,"status":"Production"}},
{"kind":"parts","code":"DP-1102","name":"Wheel Hub","data":{"customer":"CUS-001","drawing_no":"DRG-1102-A","revision":"B","material":"RM-SG500-C","weight_kg":3.4,"annual_volume":67200,"status":"Production"}},
{"kind":"parts","code":"DP-1103","name":"Input Shaft","data":{"customer":"CUS-002","drawing_no":"DRG-1103-A","revision":"B","material":"RM-EN353-F","weight_kg":2.1,"annual_volume":116400,"status":"Production"}},
{"kind":"parts","code":"DP-1104","name":"Gear Blank 42T","data":{"customer":"CUS-002","drawing_no":"DRG-1104-A","revision":"C","material":"RM-20MNCR5-F","weight_kg":1.2,"annual_volume":15600,"status":"Production"}},
{"kind":"parts","code":"DP-1105","name":"Pump Housing","data":{"customer":"CUS-004","drawing_no":"DRG-1105-A","revision":"B","material":"RM-FG260-C","weight_kg":4.6,"annual_volume":54000,"status":"Production"}},
{"kind":"parts","code":"DP-1106","name":"Steering Knuckle Bush","data":{"customer":"CUS-001","drawing_no":"DRG-1106-A","revision":"B","material":"RM-EN8-40","weight_kg":0.4,"annual_volume":15600,"status":"Production"}},
{"kind":"parts","code":"DP-1107","name":"Brake Caliper Bracket","data":{"customer":"CUS-003","drawing_no":"DRG-1107-A","revision":"C","material":"RM-SG500-C","weight_kg":2.7,"annual_volume":33600,"status":"Production"}},
{"kind":"parts","code":"DP-1108","name":"Output Shaft","data":{"customer":"CUS-002","drawing_no":"DRG-1108-A","revision":"B","material":"RM-EN353-F","weight_kg":2.4,"annual_volume":38400,"status":"Production"}},
{"kind":"parts","code":"DP-1109","name":"Timing Pulley","data":{"customer":"CUS-003","drawing_no":"DRG-1109-A","revision":"B","material":"RM-20MNCR5-F","weight_kg":0.9,"annual_volume":42000,"status":"Production"}},
{"kind":"parts","code":"DP-1110","name":"Valve Body","data":{"customer":"CUS-004","drawing_no":"DRG-1110-A","revision":"C","material":"RM-FG260-C","weight_kg":3.1,"annual_volume":26400,"status":"Production"}},
{"kind":"parts","code":"DP-1111","name":"Spline Coupling","data":{"customer":"CUS-003","drawing_no":"DRG-1111-A","revision":"B","material":"RM-20MNCR5-F","weight_kg":1.1,"annual_volume":18000,"status":"Production"}},
{"kind":"parts","code":"DP-1112","name":"Bearing Cap","data":{"customer":"CUS-001","drawing_no":"DRG-1112-A","revision":"B","material":"RM-EN8-65","weight_kg":0.8,"annual_volume":99600,"status":"Production"}},
{"kind":"parts","code":"DP-1113","name":"Planet Carrier","data":{"customer":"CUS-002","drawing_no":"DRG-1113-A","revision":"C","material":"RM-SG500-C","weight_kg":3.8,"annual_volume":38400,"status":"Production"}},
{"kind":"parts","code":"DP-1114","name":"Axle Spacer","data":{"customer":"CUS-003","drawing_no":"DRG-1114-A","revision":"B","material":"RM-EN8-40","weight_kg":0.3,"annual_volume":28800,"status":"Production"}},
{"kind":"parts","code":"DP-1115","name":"Clutch Hub","data":{"customer":"CUS-002","drawing_no":"DRG-1115-A","revision":"B","material":"RM-20MNCR5-F","weight_kg":1.0,"annual_volume":32400,"status":"Production"}},
{"kind":"parts","code":"DP-1116","name":"Rocker Arm Pivot","data":{"customer":"CUS-004","drawing_no":"DRG-1116-A","revision":"C","material":"RM-EN19-45","weight_kg":0.5,"annual_volume":37200,"status":"PPAP"}},
{"kind":"machines","code":"CNC-T01","name":"CNC turning centre 01","data":{"type":"CNC Turning","make":"Ace Micromatic","model":"Jobber XL","cell":"CNC Turning","status":"Running"}},
{"kind":"machines","code":"CNC-T02","name":"CNC turning centre 02","data":{"type":"CNC Turning","make":"Ace Micromatic","model":"Jobber XL","cell":"CNC Turning","status":"Running"}},
{"kind":"machines","code":"CNC-T03","name":"CNC turning centre 03","data":{"type":"CNC Turning","make":"Ace Micromatic","model":"Jobber XL","cell":"CNC Turning","status":"Running"}},
{"kind":"machines","code":"CNC-T04","name":"CNC turning centre 04","data":{"type":"CNC Turning","make":"Ace Micromatic","model":"Jobber XL","cell":"CNC Turning","status":"Running"}},
{"kind":"machines","code":"VMC-M01","name":"Vertical machining centre 01","data":{"type":"VMC","make":"BFW","model":"BMV 45 TC20","cell":"VMC Milling","status":"Running"}},
{"kind":"machines","code":"VMC-M02","name":"Vertical machining centre 02","data":{"type":"VMC","make":"BFW","model":"BMV 45 TC20","cell":"VMC Milling","status":"Running"}},
{"kind":"machines","code":"VMC-M03","name":"Vertical machining centre 03","data":{"type":"VMC","make":"BFW","model":"BMV 45 TC20","cell":"VMC Milling","status":"Running"}},
{"kind":"machines","code":"HMC-H01","name":"Horizontal machining centre 01","data":{"type":"HMC","make":"Makino","model":"a51nx","cell":"HMC Machining","status":"Running"}},
{"kind":"machines","code":"GRD-G01","name":"Cylindrical grinder 01","data":{"type":"Grinding","make":"Micromatic Grinding","model":"Cylindrical 300","cell":"Grinding","status":"Running"}},
{"kind":"machines","code":"GRD-G02","name":"Cylindrical grinder 02","data":{"type":"Grinding","make":"Micromatic Grinding","model":"Cylindrical 300","cell":"Grinding","status":"Running","remarks":"Spindle overhaul due"}},
{"kind":"machines","code":"HOB-01","name":"Gear hobbing machine 01","data":{"type":"Gear Hobbing","make":"Liebherr","model":"LC 180","cell":"Gear Hobbing","status":"Running"}},
{"kind":"machines","code":"BRO-01","name":"Broaching machine 01","data":{"type":"Broaching","make":"Arkay","model":"HB 10T","cell":"Broaching","status":"Running"}},
{"kind":"cycle_times","code":"DP-1101 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1101","machine":"CNC-T01","cycle_time_sec":34.0,"alternates":"CNC-T02","setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1101 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1101","machine":"CNC-T04","cycle_time_sec":58.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1101 · PCD Drilling","name":"PCD Drilling","data":{"part_no":"DP-1101","machine":"VMC-M01","cycle_time_sec":145.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1102 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1102","machine":"CNC-T02","cycle_time_sec":113.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1102 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1102","machine":"CNC-T04","cycle_time_sec":71.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1102 · PCD Drilling","name":"PCD Drilling","data":{"part_no":"DP-1102","machine":"VMC-M03","cycle_time_sec":78.0,"alternates":"VMC-M01","setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1103 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1103","machine":"CNC-T02","cycle_time_sec":72.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1103 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1103","machine":"CNC-T03","cycle_time_sec":23.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1103 · Spline Hobbing","name":"Spline Hobbing","data":{"part_no":"DP-1103","machine":"HOB-01","cycle_time_sec":83.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1103 · Cylindrical Grinding","name":"Cylindrical Grinding","data":{"part_no":"DP-1103","machine":"GRD-G01","cycle_time_sec":58.0,"setup_min":40,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1104 · Blank Turning","name":"Blank Turning","data":{"part_no":"DP-1104","machine":"CNC-T04","cycle_time_sec":27.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1104 · Gear Hobbing","name":"Gear Hobbing","data":{"part_no":"DP-1104","machine":"HOB-01","cycle_time_sec":53.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1104 · Keyway Broaching","name":"Keyway Broaching","data":{"part_no":"DP-1104","machine":"BRO-01","cycle_time_sec":188.0,"setup_min":20,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1105 · Face Milling","name":"Face Milling","data":{"part_no":"DP-1105","machine":"HMC-H01","cycle_time_sec":158.0,"setup_min":60,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1105 · Boring & Tapping","name":"Boring & Tapping","data":{"part_no":"DP-1105","machine":"VMC-M03","cycle_time_sec":78.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1106 · Turning","name":"Turning","data":{"part_no":"DP-1106","machine":"CNC-T01","cycle_time_sec":100.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1106 · ID Grinding","name":"ID Grinding","data":{"part_no":"DP-1106","machine":"GRD-G02","cycle_time_sec":113.0,"setup_min":40,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1107 · Face Milling","name":"Face Milling","data":{"part_no":"DP-1107","machine":"HMC-H01","cycle_time_sec":118.0,"setup_min":60,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1107 · Boring & Tapping","name":"Boring & Tapping","data":{"part_no":"DP-1107","machine":"VMC-M02","cycle_time_sec":129.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1108 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1108","machine":"CNC-T01","cycle_time_sec":47.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1108 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1108","machine":"CNC-T04","cycle_time_sec":71.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1108 · Spline Hobbing","name":"Spline Hobbing","data":{"part_no":"DP-1108","machine":"HOB-01","cycle_time_sec":31.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1108 · Cylindrical Grinding","name":"Cylindrical Grinding","data":{"part_no":"DP-1108","machine":"GRD-G02","cycle_time_sec":203.0,"alternates":"GRD-G01","setup_min":40,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1109 · Blank Turning","name":"Blank Turning","data":{"part_no":"DP-1109","machine":"CNC-T04","cycle_time_sec":41.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1109 · Gear Hobbing","name":"Gear Hobbing","data":{"part_no":"DP-1109","machine":"HOB-01","cycle_time_sec":71.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1109 · Keyway Broaching","name":"Keyway Broaching","data":{"part_no":"DP-1109","machine":"BRO-01","cycle_time_sec":121.0,"setup_min":20,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1110 · Face Milling","name":"Face Milling","data":{"part_no":"DP-1110","machine":"HMC-H01","cycle_time_sec":118.0,"setup_min":60,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1110 · Boring & Tapping","name":"Boring & Tapping","data":{"part_no":"DP-1110","machine":"VMC-M03","cycle_time_sec":139.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1111 · Blank Turning","name":"Blank Turning","data":{"part_no":"DP-1111","machine":"CNC-T03","cycle_time_sec":169.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1111 · Gear Hobbing","name":"Gear Hobbing","data":{"part_no":"DP-1111","machine":"HOB-01","cycle_time_sec":83.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1111 · Keyway Broaching","name":"Keyway Broaching","data":{"part_no":"DP-1111","machine":"BRO-01","cycle_time_sec":31.0,"setup_min":20,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1112 · Turning OP10","name":"Turning OP10","data":{"part_no":"DP-1112","machine":"CNC-T01","cycle_time_sec":100.0,"alternates":"CNC-T02","setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1112 · Turning OP20","name":"Turning OP20","data":{"part_no":"DP-1112","machine":"CNC-T03","cycle_time_sec":116.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1112 · PCD Drilling","name":"PCD Drilling","data":{"part_no":"DP-1112","machine":"VMC-M02","cycle_time_sec":84.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1113 · Face Milling","name":"Face Milling","data":{"part_no":"DP-1113","machine":"HMC-H01","cycle_time_sec":118.0,"setup_min":60,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1113 · Boring & Tapping","name":"Boring & Tapping","data":{"part_no":"DP-1113","machine":"VMC-M02","cycle_time_sec":84.0,"setup_min":45,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1114 · Turning","name":"Turning","data":{"part_no":"DP-1114","machine":"CNC-T02","cycle_time_sec":59.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1114 · ID Grinding","name":"ID Grinding","data":{"part_no":"DP-1114","machine":"GRD-G01","cycle_time_sec":288.0,"alternates":"GRD-G02","setup_min":40,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1115 · Blank Turning","name":"Blank Turning","data":{"part_no":"DP-1115","machine":"CNC-T03","cycle_time_sec":79.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1115 · Gear Hobbing","name":"Gear Hobbing","data":{"part_no":"DP-1115","machine":"HOB-01","cycle_time_sec":61.0,"setup_min":90,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1115 · Keyway Broaching","name":"Keyway Broaching","data":{"part_no":"DP-1115","machine":"BRO-01","cycle_time_sec":99.0,"setup_min":20,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1116 · Turning","name":"Turning","data":{"part_no":"DP-1116","machine":"CNC-T03","cycle_time_sec":37.0,"setup_min":30,"parts_per_cycle":1}},
{"kind":"cycle_times","code":"DP-1116 · ID Grinding","name":"ID Grinding","data":{"part_no":"DP-1116","machine":"GRD-G02","cycle_time_sec":203.0,"setup_min":40,"parts_per_cycle":1}},
{"kind":"plant_standards","code":"PLANT-1","name":"Plant 1 — machining","data":{"oee":80,"hoursPerDay":22,"daysPerMonth":25,"weeklyOff":"Sunday","warnPct":90,"transferLagHours":2,"lotSize":100,"levelTargetPct":100}},
{"kind":"rate_contracts","code":"RC-S-001","name":"Deccan Steel Bars Pvt Ltd","data":{"party_type":"Supplier","item":"RM-EN8-40","rate":68,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-002","name":"Deccan Steel Bars Pvt Ltd","data":{"party_type":"Supplier","item":"RM-EN8-65","rate":67,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-003","name":"Deccan Steel Bars Pvt Ltd","data":{"party_type":"Supplier","item":"RM-EN19-45","rate":92,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-004","name":"Kaveri Forgings Ltd","data":{"party_type":"Supplier","item":"RM-20MNCR5-F","rate":105,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-005","name":"Kaveri Forgings Ltd","data":{"party_type":"Supplier","item":"RM-EN353-F","rate":112,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Price linked to steel index, revised quarterly"}},
{"kind":"rate_contracts","code":"RC-S-006","name":"Trident Castings Pvt Ltd","data":{"party_type":"Supplier","item":"RM-FG260-C","rate":78,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Fixed for 12 months, freight extra"}},
{"kind":"rate_contracts","code":"RC-S-007","name":"Trident Castings Pvt Ltd","data":{"party_type":"Supplier","item":"RM-SG500-C","rate":96,"currency":"INR","uom":"kg","valid_from":"@-90","valid_to":"@275","terms":"Fixed for 12 months, freight extra"}},
{"kind":"rate_contracts","code":"RC-S-008","name":"Precise Heat Treaters","data":{"party_type":"Supplier","item":"Case carburising & hardening","rate":38,"currency":"INR","uom":"kg","valid_from":"@-60","valid_to":"@305","terms":"Minimum lot 200 kg, 5-day turnaround"}},
{"kind":"rate_contracts","code":"RC-C-001","name":"Orion Motors Pvt Ltd","data":{"party_type":"Customer","item":"DP-1101","rate":412,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-002","name":"Orion Motors Pvt Ltd","data":{"party_type":"Customer","item":"DP-1102","rate":685,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-003","name":"Sunrise Tractors Ltd","data":{"party_type":"Customer","item":"DP-1103","rate":598,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-004","name":"Sunrise Tractors Ltd","data":{"party_type":"Customer","item":"DP-1104","rate":356,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-005","name":"Nordhaus Hydraulics GmbH","data":{"party_type":"Customer","item":"DP-1105","rate":18.4,"currency":"EUR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-006","name":"Vega Commercial Vehicles Ltd","data":{"party_type":"Customer","item":"DP-1107","rate":540,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-007","name":"Nordhaus Hydraulics GmbH","data":{"party_type":"Customer","item":"DP-1110","rate":12.9,"currency":"EUR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"rate_contracts","code":"RC-C-008","name":"Orion Motors Pvt Ltd","data":{"party_type":"Customer","item":"DP-1112","rate":238,"currency":"INR","uom":"pcs","valid_from":"@-120","valid_to":"@245","terms":"As per purchase order; annual price review in April"}},
{"kind":"gauges","code":"GA-VC-001","name":"Digital vernier caliper 0–150","data":{"type":"Vernier","range":"0–150 mm","least_count":"0.01 mm","make":"Mitutoyo","cal_freq_months":6,"last_calibrated":"@-40","next_due":"@140","location":"CNC Turning"}},
{"kind":"gauges","code":"GA-VC-002","name":"Digital vernier caliper 0–300","data":{"type":"Vernier","range":"0–300 mm","least_count":"0.01 mm","make":"Mitutoyo","cal_freq_months":6,"last_calibrated":"@-150","next_due":"@30","location":"Quality lab"}},
{"kind":"gauges","code":"GA-MC-001","name":"Outside micrometer 25–50","data":{"type":"Micrometer","range":"25–50 mm","least_count":"0.001 mm","make":"Mitutoyo","cal_freq_months":6,"last_calibrated":"@-20","next_due":"@160","location":"Grinding"}},
{"kind":"gauges","code":"GA-MC-002","name":"Outside micrometer 50–75","data":{"type":"Micrometer","range":"50–75 mm","least_count":"0.001 mm","make":"Mitutoyo","cal_freq_months":6,"last_calibrated":"@-100","next_due":"@80","location":"Grinding"}},
{"kind":"gauges","code":"GA-BG-001","name":"Bore gauge 35–60","data":{"type":"Bore gauge","range":"35–60 mm","least_count":"0.001 mm","make":"Baker","cal_freq_months":6,"last_calibrated":"@-60","next_due":"@120","location":"VMC Milling"}},
{"kind":"gauges","code":"GA-PG-001","name":"Plug gauge Ø25H7 GO/NOGO","data":{"type":"Plug gauge","range":"Ø25 H7","least_count":"—","make":"Precise Gauges","cal_freq_months":12,"last_calibrated":"@-200","next_due":"@160","location":"VMC Milling"}},
{"kind":"gauges","code":"GA-PG-002","name":"Thread plug gauge M10×1.5 6H","data":{"type":"Plug gauge","range":"M10×1.5","least_count":"—","make":"Precise Gauges","cal_freq_months":12,"last_calibrated":"@-340","next_due":"@20","location":"HMC Machining"}},
{"kind":"gauges","code":"GA-RG-001","name":"Ring gauge Ø30h6 GO/NOGO","data":{"type":"Ring gauge","range":"Ø30 h6","least_count":"—","make":"Precise Gauges","cal_freq_months":12,"last_calibrated":"@-90","next_due":"@270","location":"Grinding"}},
{"kind":"gauges","code":"GA-HG-001","name":"Digital height gauge 0–300","data":{"type":"Height gauge","range":"0–300 mm","least_count":"0.01 mm","make":"Mitutoyo","cal_freq_months":12,"last_calibrated":"@-30","next_due":"@330","location":"Quality lab"}},
{"kind":"gauges","code":"GA-DI-001","name":"Dial indicator 0–10","data":{"type":"Dial","range":"0–10 mm","least_count":"0.01 mm","make":"Baker","cal_freq_months":6,"last_calibrated":"@-175","next_due":"@5","location":"Gear Hobbing"}},
{"kind":"gauges","code":"GA-SG-001","name":"Spline plug gauge 21T","data":{"type":"Plug gauge","range":"21T module 1.25","least_count":"—","make":"Precise Gauges","cal_freq_months":12,"last_calibrated":"@-120","next_due":"@240","location":"Gear Hobbing"}},
{"kind":"gauges","code":"GA-CMM-001","name":"CMM bridge type 700×1000×600","data":{"type":"CMM","range":"700×1000×600 mm","least_count":"0.0015 mm","make":"Zeiss","cal_freq_months":12,"last_calibrated":"@-45","next_due":"@315","location":"Quality lab"}},
{"kind":"tools","code":"TL-INS-001","name":"Turning insert CNMG 120408","data":{"type":"Insert","size":"CNMG 120408 · P25","make":"Sandvik","tool_life":350,"cost":620,"stock":120}},
{"kind":"tools","code":"TL-INS-002","name":"Finishing insert VNMG 160404","data":{"type":"Insert","size":"VNMG 160404 · P15","make":"Sandvik","tool_life":450,"cost":680,"stock":80}},
{"kind":"tools","code":"TL-INS-003","name":"Grooving insert 3 mm","data":{"type":"Insert","size":"3 mm · P30","make":"Iscar","tool_life":600,"cost":540,"stock":40}},
{"kind":"tools","code":"TL-DRL-001","name":"Solid carbide drill Ø8.5","data":{"type":"Drill","size":"Ø8.5 × 5D","make":"Guhring","tool_life":2500,"cost":3400,"stock":12}},
{"kind":"tools","code":"TL-DRL-002","name":"Solid carbide drill Ø10.2","data":{"type":"Drill","size":"Ø10.2 × 5D","make":"Guhring","tool_life":2200,"cost":3900,"stock":10}},
{"kind":"tools","code":"TL-TAP-001","name":"Spiral flute tap M10×1.5","data":{"type":"Tap","size":"M10×1.5 6H","make":"Yamawa","tool_life":1500,"cost":1850,"stock":15}},
{"kind":"tools","code":"TL-RMR-001","name":"Carbide reamer Ø25H7","data":{"type":"Reamer","size":"Ø25 H7","make":"Guhring","tool_life":4000,"cost":6200,"stock":4}},
{"kind":"tools","code":"TL-EM-001","name":"End mill Ø16 4-flute","data":{"type":"End mill","size":"Ø16 · AlTiN","make":"Kennametal","tool_life":3000,"cost":4800,"stock":8}},
{"kind":"tools","code":"TL-BB-001","name":"Boring bar Ø20 min bore","data":{"type":"Boring bar","size":"Ø20 × 150","make":"Sandvik","tool_life":20000,"cost":14500,"stock":3}},
{"kind":"tools","code":"TL-HOB-001","name":"Gear hob module 2 AA","data":{"type":"Other","size":"m2 · class AA · TiN","make":"Liebherr","tool_life":12000,"cost":68000,"stock":2}},
{"kind":"tools","code":"TL-BRO-001","name":"Keyway broach 8 mm","data":{"type":"Other","size":"8 mm keyway","make":"Arkay","tool_life":15000,"cost":42000,"stock":2}},
{"kind":"tools","code":"TL-FIX-001","name":"Hydraulic fixture — Pump Housing","data":{"type":"Fixture","size":"DP-1105 OP10","make":"In-house","cost":185000,"stock":1}},
{"kind":"consumables","code":"CN-001","name":"Soluble cutting coolant","data":{"uom":"litre","min_stock":400,"rate":185,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-002","name":"Hydraulic oil ISO VG 68","data":{"uom":"litre","min_stock":200,"rate":160,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-003","name":"Slideway oil ISO VG 68","data":{"uom":"litre","min_stock":100,"rate":175,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-004","name":"Grinding wheel 400×50×127 A60","data":{"uom":"pcs","min_stock":4,"rate":9800,"supplier":"SUP-006"}},
{"kind":"consumables","code":"CN-005","name":"Cotton waste","data":{"uom":"kg","min_stock":50,"rate":90,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-006","name":"Rust preventive oil","data":{"uom":"litre","min_stock":150,"rate":140,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-007","name":"VCI poly bags 300×400","data":{"uom":"pcs","min_stock":2000,"rate":6,"supplier":"SUP-008"}},
{"kind":"consumables","code":"CN-008","name":"Nitrile gloves","data":{"uom":"pair","min_stock":500,"rate":12,"supplier":"SUP-008"}},
{"kind":"cft","code":"CFT-001","name":"R. Venkatesh","data":{"function":"Management","cft_role":"CFT leader","email":"plant.head@sample-plant.example","phone":"+91 90000 30001"}},
{"kind":"cft","code":"CFT-002","name":"S. Priya","data":{"function":"Quality","cft_role":"CFT member","email":"quality@sample-plant.example","phone":"+91 90000 30002"}},
{"kind":"cft","code":"CFT-003","name":"K. Arun","data":{"function":"Production","cft_role":"CFT member","email":"production@sample-plant.example","phone":"+91 90000 30003"}},
{"kind":"cft","code":"CFT-004","name":"M. Divya","data":{"function":"Engineering","cft_role":"CFT member","email":"engineering@sample-plant.example","phone":"+91 90000 30004"}},
{"kind":"cft","code":"CFT-005","name":"N. Suresh","data":{"function":"Maintenance","cft_role":"CFT member","email":"maintenance@sample-plant.example","phone":"+91 90000 30005"}},
{"kind":"cft","code":"CFT-006","name":"L. Meena","data":{"function":"Purchase","cft_role":"CFT member","email":"purchase@sample-plant.example","phone":"+91 90000 30006"}},
{"kind":"cft","code":"CFT-007","name":"H. Ganesh","data":{"function":"Stores","cft_role":"Key contact","email":"stores@sample-plant.example","phone":"+91 90000 30007"}},
{"kind":"cft","code":"CFT-008","name":"P. Latha","data":{"function":"Customer contact","cft_role":"Key contact","email":"sqa@sunrise-tractors.example","phone":"+91 90000 30008","organisation":"Sunrise Tractors Ltd"}},
{"kind":"cft","code":"CFT-009","name":"S. Ramesh","data":{"function":"Customer contact","cft_role":"Escalation","email":"purchase@orion-motors.example","phone":"+91 90000 30009","organisation":"Orion Motors Pvt Ltd"}},
{"kind":"cft","code":"CFT-010","name":"Key account — Deccan Steel","data":{"function":"Supplier contact","cft_role":"Key contact","email":"sales1@supplier.example","phone":"+91 90000 30010","organisation":"Deccan Steel Bars Pvt Ltd"}},
{"kind":"documents","code":"QM-01","name":"Quality manual","data":{"doc_type":"Quality manual","iatf_clause":"4.3, 4.4","revision":"05","effective_date":"@-200","owner":"Management representative","review_due":"@165"}},
{"kind":"documents","code":"QP-01","name":"Quality policy and objectives","data":{"doc_type":"Policy","iatf_clause":"5.2, 6.2","revision":"03","effective_date":"@-200","owner":"Plant head","review_due":"@165"}},
{"kind":"documents","code":"PR-01","name":"Control of documented information","data":{"doc_type":"Procedure","iatf_clause":"7.5","revision":"04","effective_date":"@-150","owner":"Quality","review_due":"@215"}},
{"kind":"documents","code":"PR-02","name":"Risk analysis and contingency planning","data":{"doc_type":"Procedure","iatf_clause":"6.1.2.1, 6.1.2.3","revision":"02","effective_date":"@-120","owner":"Plant head","review_due":"@245"}},
{"kind":"documents","code":"PR-03","name":"Calibration and measurement system analysis","data":{"doc_type":"Procedure","iatf_clause":"7.1.5.1.1, 7.1.5.2","revision":"03","effective_date":"@-100","owner":"Quality","review_due":"@265"}},
{"kind":"documents","code":"PR-04","name":"Supplier selection and monitoring","data":{"doc_type":"Procedure","iatf_clause":"8.4.1.2, 8.4.2.4","revision":"03","effective_date":"@-180","owner":"Purchase","review_due":"@185"}},
{"kind":"documents","code":"PR-05","name":"Product and process design (APQP)","data":{"doc_type":"Procedure","iatf_clause":"8.3","revision":"02","effective_date":"@-240","owner":"Engineering","review_due":"@125"}},
{"kind":"documents","code":"PR-06","name":"Control of nonconforming output","data":{"doc_type":"Procedure","iatf_clause":"8.7","revision":"04","effective_date":"@-90","owner":"Quality","review_due":"@275"}},
{"kind":"documents","code":"PR-07","name":"Problem solving — 8D and corrective action","data":{"doc_type":"Procedure","iatf_clause":"10.2.3, 10.2.4","revision":"03","effective_date":"@-60","owner":"Quality","review_due":"@305"}},
{"kind":"documents","code":"PR-08","name":"Total productive maintenance","data":{"doc_type":"Procedure","iatf_clause":"8.5.1.5","revision":"02","effective_date":"@-130","owner":"Maintenance","review_due":"@235"}},
{"kind":"documents","code":"WI-CNC-01","name":"CNC turning — set-up and first-off approval","data":{"doc_type":"Work instruction","iatf_clause":"8.5.1.3","revision":"02","effective_date":"@-70","owner":"Production","review_due":"@295"}},
{"kind":"documents","code":"FM-QA-12","name":"Layout inspection report format","data":{"doc_type":"Form / format","iatf_clause":"8.6.2","revision":"01","effective_date":"@-160","owner":"Quality","review_due":"@205"}},
{"kind":"documents","code":"CSR-001","name":"Orion Motors customer-specific requirements","data":{"doc_type":"Customer-specific requirement","iatf_clause":"4.3.2","revision":"2026","effective_date":"@-30","owner":"Quality","review_due":"@335"}},
{"kind":"documents","code":"EXT-01","name":"IATF 16949:2016 standard","data":{"doc_type":"External standard","iatf_clause":"—","revision":"2016","effective_date":"@-400","owner":"Management representative","review_due":"@-35"}}
]$sample$::jsonb
$fn$;

create or replace function console.ops_sample_dates(d jsonb) returns jsonb
language sql stable set search_path = console, public as $$
  select coalesce(jsonb_object_agg(k, case when jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^@-?[0-9]+$'
                                           then to_jsonb(to_char(current_date + substr(v #>> '{}', 2)::int, 'YYYY-MM-DD')) else v end), '{}')
    from jsonb_each(coalesce(d, '{}')) e(k, v)
$$;

create or replace function public.kmr_ops_sample_load(p_slug text) returns jsonb
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; me text := lower(coalesce(auth.jwt() ->> 'email', '')); r jsonb; added int := 0; skipped int := 0; n int;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is distinct from 'admin' then
    raise exception 'Only an Operations Master administrator can load or flush sample data.';
  end if;
  for r in select * from jsonb_array_elements(console.ops_sample()) loop
    if r ->> 'kind' = 'plant_standards'
       and exists (select 1 from console.ops_records where customer_id = cid and kind = 'plant_standards' and not sample) then
      skipped := skipped + 1; continue;
    end if;
    insert into console.ops_records (customer_id, kind, code, name, data, active, sample, updated_by)
    values (cid, r ->> 'kind', r ->> 'code', coalesce(r ->> 'name', ''), console.ops_sample_dates(r -> 'data'), true, true, me)
    on conflict (customer_id, kind, code) do nothing;
    get diagnostics n = row_count;
    if n = 1 then added := added + 1; else skipped := skipped + 1; end if;
  end loop;
  return jsonb_build_object('added', added, 'skipped', skipped);
end $$;
revoke all on function public.kmr_ops_sample_load(text) from public, anon;
grant execute on function public.kmr_ops_sample_load(text) to authenticated;

create or replace function public.kmr_ops_sample_flush(p_slug text) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; n int;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is distinct from 'admin' then
    raise exception 'Only an Operations Master administrator can load or flush sample data.';
  end if;
  delete from console.ops_records where customer_id = cid and sample;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.kmr_ops_sample_flush(text) from public, anon;
grant execute on function public.kmr_ops_sample_flush(text) to authenticated;

-- Counts now also report how many sample records are loaded ("_sample")
create or replace function public.kmr_ops_counts(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from console.ops_records where customer_id = cid and active group by kind) x), '{}')
      || jsonb_build_object('_sample', (select count(*) from console.ops_records where customer_id = cid and sample));
end $$;
grant execute on function public.kmr_ops_counts(text) to authenticated;

-- Lists now say which records are sample data
create or replace function public.kmr_ops_list(p_slug text, p_kind text) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid;
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or console.ops_role(cid) is null then raise exception 'You have no access to the Operations Master.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'data', data, 'active', active, 'sample', sample,
            'updated_at', updated_at, 'updated_by', updated_by) order by code)
          from console.ops_records where customer_id = cid and kind = p_kind), '[]');
end $$;
grant execute on function public.kmr_ops_list(text, text) to authenticated;

-- Saving (form or CSV import) makes a record the company's own: it is no longer sample data
create or replace function public.kmr_ops_save(p_slug text, p_kind text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = console, public as $$
declare cid uuid; r jsonb; n integer := 0; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  select id into cid from console.customers where slug = lower(p_slug);
  if cid is null or coalesce(console.ops_role(cid), '') not in ('admin','editor') then
    raise exception 'You can view the Operations Master but not change it. Ask your administrator for editor access.';
  end if;
  for r in select * from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else jsonb_build_array(p_rows) end) loop
    if length(trim(coalesce(r ->> 'code', ''))) = 0 then raise exception 'Every record needs a code / number.'; end if;
    if r ? 'id' and (r ->> 'id') ~ '^[0-9a-f-]{36}$' then
      update console.ops_records set code = trim(r ->> 'code'), name = coalesce(trim(r ->> 'name'), ''),
             data = coalesce(r -> 'data', '{}'), active = coalesce((r ->> 'active')::boolean, true), sample = false, updated_at = now(), updated_by = me
       where id = (r ->> 'id')::uuid and customer_id = cid and kind = p_kind;
    else
      insert into console.ops_records (customer_id, kind, code, name, data, active, updated_by)
      values (cid, p_kind, trim(r ->> 'code'), coalesce(trim(r ->> 'name'), ''), coalesce(r -> 'data', '{}'), coalesce((r ->> 'active')::boolean, true), me)
      on conflict (customer_id, kind, code) do update set name = excluded.name, data = console.ops_records.data || excluded.data,
         active = excluded.active, sample = false, updated_at = now(), updated_by = me;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.kmr_ops_save(text, text, jsonb) to authenticated;

-- The planner prefers the company's own plant standards over the sample ones
create or replace function public.kmr_capacity_masters(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = console, public as $$
declare cid uuid; hrm_ref uuid; std jsonb; hol jsonb; names jsonb;
begin
  if public.cp_my_role(p_org) is null or not console.product_ok('capacity', p_org) then raise exception 'No access to this planner.'; end if;
  select customer_id into cid from console.licences where product_code = 'capacity' and product_ref = p_org;
  if cid is null then return null; end if;
  select data into std from console.ops_records where customer_id = cid and kind = 'plant_standards' and active order by sample, updated_at desc limit 1;
  select product_ref into hrm_ref from console.licences where customer_id = cid and product_code = 'hrm' and product_ref is not null;
  if hrm_ref is not null then
    select coalesce(jsonb_agg(to_char(holiday_date, 'YYYY-MM-DD') order by holiday_date), '[]'), coalesce(jsonb_object_agg(to_char(holiday_date, 'YYYY-MM-DD'), name), '{}')
      into hol, names from hrm.holidays where tenant_id = hrm_ref;
  end if;
  return jsonb_build_object(
    'machines', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'cell', coalesce(r.data ->> 'cell', r.data ->> 'type', ''),
        'availDays', nullif(r.data ->> 'available_days', '')::numeric, 'hoursPerDay', nullif(r.data ->> 'hours_per_day', '')::numeric,
        'remarks', coalesce(r.data ->> 'remarks', ''), 'active', r.active) order by r.code)
      from console.ops_records r where r.customer_id = cid and r.kind = 'machines'), '[]'),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', row_number, 'partNo', x.part_no, 'partName', coalesce(p.name, x.part_no),
        'process', x.name, 'machine', x.machine, 'cycleTime', x.ct, 'alternates',
        coalesce((select jsonb_agg(trim(a)) from unnest(string_to_array(coalesce(x.alts, ''), ',')) a where trim(a) <> ''), '[]')) order by x.part_no, x.code)
      from (select row_number() over (order by r.data ->> 'part_no', r.code) row_number, r.code, r.name, r.data ->> 'part_no' part_no, r.data ->> 'machine' machine,
                   nullif(r.data ->> 'cycle_time_sec', '')::numeric ct, r.data ->> 'alternates' alts
              from console.ops_records r where r.customer_id = cid and r.kind = 'cycle_times' and r.active) x
      left join console.ops_records p on p.customer_id = cid and p.kind = 'parts' and p.code = x.part_no), '[]'),
    'standards', coalesce(std, '{}'), 'holidays', coalesce(hol, '[]'), 'holidayNames', coalesce(names, '{}'),
    'has_hrm', hrm_ref is not null);
end $$;
revoke all on function public.kmr_capacity_masters(uuid) from public, anon;
grant execute on function public.kmr_capacity_masters(uuid) to authenticated;
