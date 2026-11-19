-- KMR 0167 — Budget: fix the "assumed" list in bud_month (array append).
do $fx$ declare def text; begin
  def := pg_get_functiondef('console.bud_month(uuid,text)'::regprocedure);
  def := replace(def, 'assumed := assumed || ''average machine load 15 kW''', 'assumed := array_append(assumed, ''average machine load 15 kW''::text)');
  def := replace(def, 'assumed := assumed || ''tariff Rs 8 per kWh''', 'assumed := array_append(assumed, ''tariff Rs 8 per kWh''::text)');
  execute def;
end $fx$;
