import "server-only";
import fs from "node:fs/promises";
import path from "node:path";
import { PDFDocument, rgb, type PDFFont, type PDFImage, type PDFPage } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import { basisText, inr, inWords, lineAmount, type QuoteLine, type ScopeRow } from "@/lib/quote";

export type QuoteDoc = {
  number: string | null; quote_date: string; valid_until: string | null; currency: string;
  to_name: string; to_attn?: string | null; to_address?: string | null; to_gstin?: string | null; to_email?: string | null; to_phone?: string | null;
  subject: string; intro?: string | null; scope: ScopeRow[]; lines: QuoteLine[]; includes?: string | null; terms?: string | null;
  discount_pct: number; gst_rate: number; subtotal: number; discount: number; taxable: number; gst: number; total: number;
  seller: { trade_name?: string | null; legal_name?: string | null; gstin?: string | null; signatory?: string | null };
  seat_label?: (code?: string | null) => string;
};

// A4 in points; the letterhead's safe area (measured on the 1054 × 1492 artwork)
const W = 595.28, H = 841.89, X0 = 44, X1 = W - 44, TOP = H - H * (300 / 1492), BOTTOM = H * (1 - 1190 / 1492);
const NAVY = rgb(0.043, 0.122, 0.278), GOLD = rgb(0.788, 0.635, 0.294), INK = rgb(0.09, 0.14, 0.23), MUTED = rgb(0.42, 0.47, 0.55);
const ROW = rgb(0.965, 0.972, 0.985), LINE = rgb(0.86, 0.88, 0.92), GOLDBG = rgb(0.985, 0.955, 0.88);

const fmtDate = (d?: string | null) => d ? new Date(d + "T00:00:00Z").toLocaleDateString("en-IN", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" }) : "—";

export async function quotePdf(q: QuoteDoc, letterhead?: Uint8Array | null): Promise<Uint8Array> {
  const dir = path.join(process.cwd(), "assets");
  const pdf = await PDFDocument.create(); pdf.registerFontkit(fontkit);
  pdf.setTitle(`Quotation ${q.number ?? ""} — ${q.to_name}`); pdf.setAuthor(q.seller.trade_name || "KMR Group of Companies"); pdf.setCreator("KMR Console");
  const [reg, med, bold] = await Promise.all(["Poppins-Regular", "Poppins-Medium", "Poppins-Bold"].map(async (f) => pdf.embedFont(await fs.readFile(path.join(dir, "fonts", f + ".ttf")), { subset: true })));
  const lhBytes = letterhead ?? await fs.readFile(path.join(dir, "letterhead.jpg"));
  const isPng = lhBytes[0] === 0x89 && lhBytes[1] === 0x50;
  const lh: PDFImage = isPng ? await pdf.embedPng(lhBytes) : await pdf.embedJpg(lhBytes);

  let page!: PDFPage, y = 0;
  const newPage = () => { page = pdf.addPage([W, H]); page.drawImage(lh, { x: 0, y: 0, width: W, height: H }); y = TOP; };
  const ensure = (h: number) => { if (y - h < BOTTOM) newPage(); };
  const width = (t: string, f: PDFFont, s: number) => f.widthOfTextAtSize(t, s);
  const wrap = (t: string, f: PDFFont, s: number, w: number): string[] => {
    const out: string[] = [];
    for (const para of String(t ?? "").split("\n")) {
      let cur = "";
      for (const word of para.split(/\s+/).filter(Boolean)) {
        const test = cur ? cur + " " + word : word;
        if (width(test, f, s) <= w) cur = test;
        else { if (cur) out.push(cur); cur = word; while (width(cur, f, s) > w) { let k = cur.length; while (k > 1 && width(cur.slice(0, k), f, s) > w) k--; out.push(cur.slice(0, k)); cur = cur.slice(k); } }
      }
      out.push(cur);
    }
    return out;
  };
  const text = (t: string, x: number, yy: number, f: PDFFont, s: number, c = INK) => page.drawText(t, { x, y: yy, size: s, font: f, color: c });
  const right = (t: string, x: number, yy: number, f: PDFFont, s: number, c = INK) => text(t, x - width(t, f, s), yy, f, s, c);
  const para = (t: string, f = reg, s = 9.2, c = INK, gap = 4, indent = 0) => {
    for (const l of wrap(t, f, s, X1 - X0 - indent)) { ensure(s + 4); text(l, X0 + indent, y - s, f, s, c); y -= s + 4; }
    y -= gap;
  };
  const heading = (t: string) => {
    ensure(40); y -= 6;
    text(t, X0, y - 11, bold, 11, NAVY); page.drawRectangle({ x: X0, y: y - 16, width: 34, height: 2, color: GOLD }); y -= 26;
  };

  /** a table that splits across pages; the header row repeats on each page */
  const table = (cols: { title: string; w: number; align?: "right" | "center" }[], rows: { cells: string[]; bold?: boolean; sub?: string }[], opts: { zebra?: boolean } = {}) => {
    const total = cols.reduce((a, c) => a + c.w, 0), sc = (X1 - X0) / total, ws = cols.map((c) => c.w * sc);
    const drawHead = () => {
      page.drawRectangle({ x: X0, y: y - 20, width: X1 - X0, height: 20, color: NAVY });
      let x = X0; cols.forEach((c, i) => {
        const tx = c.align === "right" ? x + ws[i] - 6 - width(c.title, bold, 8) : c.align === "center" ? x + (ws[i] - width(c.title, bold, 8)) / 2 : x + 6;
        text(c.title, tx, y - 13.5, bold, 8, rgb(1, 1, 1)); x += ws[i];
      });
      y -= 20;
    };
    ensure(46); drawHead();
    rows.forEach((r, ri) => {
      const cellLines = r.cells.map((c, i) => wrap(c, r.bold && i === 1 ? med : reg, 8.6, ws[i] - 12));
      const subLines = r.sub ? wrap(r.sub, reg, 7.6, ws[1] - 12) : [];
      const h = Math.max(...cellLines.map((l) => l.length)) * 11.5 + subLines.length * 10 + 9;
      if (y - h < BOTTOM) { newPage(); drawHead(); }
      if (opts.zebra && ri % 2 === 0) page.drawRectangle({ x: X0, y: y - h, width: X1 - X0, height: h, color: ROW });
      let x = X0;
      cellLines.forEach((ls, i) => {
        ls.forEach((l, k) => {
          const f = r.bold && i === 1 ? med : reg, yy = y - 12 - k * 11.5;
          if (cols[i].align === "right") right(l, x + ws[i] - 6, yy, f, 8.6); else if (cols[i].align === "center") text(l, x + (ws[i] - width(l, f, 8.6)) / 2, yy, f, 8.6); else text(l, x + 6, yy, f, 8.6);
        });
        if (i === 1) subLines.forEach((l, k) => text(l, x + 6, y - 12 - ls.length * 11.5 - k * 10, reg, 7.6, MUTED));
        x += ws[i];
      });
      page.drawLine({ start: { x: X0, y: y - h }, end: { x: X1, y: y - h }, thickness: 0.5, color: LINE });
      y -= h;
    });
  };

  // ---------------- page 1 ----------------
  newPage();
  const title = "QUOTATION";
  text(title, (W - width(title, bold, 17)) / 2, y - 17, bold, 17, NAVY);
  page.drawRectangle({ x: (W - 60) / 2, y: y - 24, width: 60, height: 2.2, color: GOLD }); y -= 38;

  // reference box
  const bx = X0, bw = X1 - X0, bh = 40;
  page.drawRectangle({ x: bx, y: y - bh, width: bw, height: bh, color: ROW, borderColor: LINE, borderWidth: 0.6 });
  const refs: [string, string][] = [["Quotation No.", q.number ?? "Draft"], ["Date", fmtDate(q.quote_date)], ["Valid until", fmtDate(q.valid_until)], ["Currency", q.currency === "INR" ? "INR (₹)" : q.currency]];
  refs.forEach(([k, v], i) => { const cx = bx + 10 + i * (bw / 4); text(k.toUpperCase(), cx, y - 15, bold, 6.8, MUTED); text(v, cx, y - 30, med, 9.4, NAVY); });
  y -= bh + 16;

  // to
  text("TO", X0, y - 9, bold, 7.5, GOLD); y -= 14;
  para(`M/s. ${q.to_name}`, bold, 11, NAVY, 1);
  [q.to_attn && `Attn: ${q.to_attn}`, q.to_address, [q.to_gstin && `GSTIN: ${q.to_gstin}`, q.to_email, q.to_phone].filter(Boolean).join("   ·   ")]
    .filter(Boolean).forEach((l) => para(String(l), reg, 9, INK, 0));
  y -= 8;

  // subject bar
  const subj = wrap(`SUBJECT: ${q.subject}`, bold, 9.6, X1 - X0 - 20);
  ensure(subj.length * 13 + 14);
  page.drawRectangle({ x: X0, y: y - (subj.length * 13 + 12), width: X1 - X0, height: subj.length * 13 + 12, color: NAVY });
  page.drawRectangle({ x: X0, y: y - (subj.length * 13 + 12), width: 4, height: subj.length * 13 + 12, color: GOLD });
  subj.forEach((l, i) => text(l, X0 + 12, y - 16 - i * 13, bold, 9.6, rgb(1, 1, 1)));
  y -= subj.length * 13 + 24;

  para("Dear Sir / Madam,", reg, 9.4, INK, 2);
  if (q.intro) para(q.intro, reg, 9.2, INK, 8);

  let n = 1;
  if (q.scope.length) {
    heading(`${n++}. SCOPE OF SUPPLY`);
    table([{ title: "#", w: 5, align: "center" }, { title: "MODULE", w: 30 }, { title: "INCLUDED CAPABILITY", w: 65 }],
      q.scope.map((s, i) => ({ cells: [String(i + 1), s.module, s.capability], bold: true })), { zebra: true });
    y -= 10;
  }

  heading(`${n++}. COMMERCIAL PROPOSAL`);
  const seat = (c?: string | null) => (q.seat_label ? q.seat_label(c) : "users");
  table([{ title: "#", w: 5, align: "center" }, { title: "PARTICULARS", w: 43 }, { title: "BASIS", w: 20 }, { title: "RATE (₹)", w: 15, align: "right" }, { title: "AMOUNT (₹)", w: 17, align: "right" }],
    q.lines.map((l, i) => ({ cells: [String(i + 1), l.particulars, basisText(l, seat(l.product_code)), inr(l.rate, false), inr(lineAmount(l), false)], bold: true, sub: l.detail || undefined })), { zebra: true });

  // totals block
  const tot: [string, string, boolean?][] = [["Sub-total", inr(q.subtotal, false)]];
  if (q.discount > 0) tot.push([`Less: discount @ ${q.discount_pct}%`, `− ${inr(q.discount, false)}`]);
  if (q.discount > 0) tot.push(["Total before GST", inr(q.taxable, false)]);
  tot.push([`GST @ ${q.gst_rate}%`, inr(q.gst, false)]);
  ensure(tot.length * 18 + 52);
  const tx = X0 + (X1 - X0) * 0.48;
  tot.forEach(([k, v]) => { text(k, tx + 8, y - 13, med, 9, INK); right(v, X1 - 6, y - 13, med, 9, INK); page.drawLine({ start: { x: tx, y: y - 18 }, end: { x: X1, y: y - 18 }, thickness: 0.5, color: LINE }); y -= 18; });
  page.drawRectangle({ x: tx, y: y - 24, width: X1 - tx, height: 24, color: NAVY });
  text("GRAND TOTAL", tx + 8, y - 16, bold, 10, GOLD); right(`₹ ${inr(q.total, false)}`, X1 - 6, y - 16, bold, 10.5, rgb(1, 1, 1)); y -= 32;
  para(`Amount in words: ${inWords(q.total)}`, med, 8.6, NAVY, 10);

  const bullets = (t?: string | null) => (t ?? "").split("\n").map((s) => s.trim()).filter(Boolean);
  if (bullets(q.includes).length) {
    heading(`${n++}. THE SUBSCRIPTION INCLUDES`);
    bullets(q.includes).forEach((b) => { const ls = wrap(b, reg, 9, X1 - X0 - 16); ensure(ls.length * 13); page.drawCircle({ x: X0 + 4, y: y - 6, size: 2.2, color: GOLD }); ls.forEach((l) => { text(l, X0 + 14, y - 9, reg, 9); y -= 13; }); y -= 2; });
    y -= 6;
  }
  if (bullets(q.terms).length) {
    heading(`${n++}. COMMERCIAL TERMS & CONDITIONS`);
    bullets(q.terms).forEach((b, i) => { const ls = wrap(b, reg, 9, X1 - X0 - 20); ensure(ls.length * 13); text(`${i + 1}.`, X0, y - 9, bold, 9, NAVY); ls.forEach((l) => { text(l, X0 + 18, y - 9, reg, 9); y -= 13; }); y -= 2; });
    y -= 6;
  }

  // signatures
  ensure(96); y -= 10;
  const half = (X1 - X0 - 20) / 2;
  [[`For ${(q.seller.trade_name || "KMR GROUP OF COMPANIES").toUpperCase()}`, "Authorised signatory"], ["CUSTOMER ACCEPTANCE", "Authorised signatory · name / designation"]].forEach(([h, s], i) => {
    const x = X0 + i * (half + 20);
    page.drawRectangle({ x, y: y - 82, width: half, height: 82, borderColor: LINE, borderWidth: 0.8, color: i ? rgb(1, 1, 1) : GOLDBG });
    text(h, x + 10, y - 16, bold, 8.6, NAVY);
    page.drawLine({ start: { x: x + 10, y: y - 58 }, end: { x: x + half - 10, y: y - 58 }, thickness: 0.6, color: MUTED });
    text(s, x + 10, y - 70, reg, 7.6, MUTED);
  });
  y -= 92;

  // page numbers + reference, just above the footer artwork
  const pages = pdf.getPages();
  pages.forEach((p, i) => {
    const t = `${q.number ?? "Draft quotation"}  ·  Page ${i + 1} of ${pages.length}`;
    p.drawText(t, { x: X1 - reg.widthOfTextAtSize(t, 7), y: BOTTOM - 14, size: 7, font: reg, color: MUTED });
    p.drawText("Confidential commercial proposal", { x: X0, y: BOTTOM - 14, size: 7, font: reg, color: MUTED });
  });
  return pdf.save();
}
