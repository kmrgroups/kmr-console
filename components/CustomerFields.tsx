type C = Partial<Record<"name" | "legal_name" | "country" | "currency" | "tax_id" | "address" | "city" | "state" | "postal_code" | "time_zone" | "contact_name" | "contact_email" | "contact_phone" | "status" | "source" | "notes", string | null>>;

export function CustomerFields({ c }: { c?: C }) {
  const v = (k: keyof C, d = "") => c?.[k] ?? d;
  return (
    <>
      <label className="field">Company name<input name="name" defaultValue={v("name")} required /></label>
      <label className="field">Legal name<input name="legal_name" defaultValue={v("legal_name")} placeholder="As on invoices" /></label>
      <label className="field">Country (2 letters)<input name="country" defaultValue={v("country", "IN")} maxLength={2} required /></label>
      <label className="field">Currency<input name="currency" defaultValue={v("currency", "INR")} maxLength={3} required /></label>
      <label className="field">Tax ID<input name="tax_id" defaultValue={v("tax_id")} placeholder="GSTIN / VAT / EIN" /></label>
      <label className="field">Time zone<input name="time_zone" defaultValue={v("time_zone", "Asia/Kolkata")} required /></label>
      <label className="field full">Address<input name="address" defaultValue={v("address")} /></label>
      <label className="field">City<input name="city" defaultValue={v("city")} /></label>
      <label className="field">State / region<input name="state" defaultValue={v("state")} /></label>
      <label className="field">Postal code<input name="postal_code" defaultValue={v("postal_code")} /></label>
      <label className="field">Status
        <select name="status" defaultValue={v("status", "lead")}>{["lead", "pilot", "active", "inactive"].map((s) => <option key={s}>{s}</option>)}</select>
      </label>
      <label className="field">Contact person<input name="contact_name" defaultValue={v("contact_name")} /></label>
      <label className="field">Contact email<input name="contact_email" type="email" defaultValue={v("contact_email")} /></label>
      <label className="field">Contact phone<input name="contact_phone" defaultValue={v("contact_phone")} /></label>
      <label className="field">Source<input name="source" defaultValue={v("source")} placeholder="Website, referral, exhibition…" /></label>
      <label className="field full">Notes<textarea name="notes" defaultValue={v("notes")} rows={3} /></label>
    </>
  );
}
