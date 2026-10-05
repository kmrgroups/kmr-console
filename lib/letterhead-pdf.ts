import "server-only";
import fs from "node:fs/promises";
import path from "node:path";
import { PDFDocument, degrees, rgb, type PDFFont, type PDFImage, type PDFPage } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";

/**
 * Every commercial document (quotation, invoice) is printed on the KMR letterhead: the artwork fills each A4 page and
 * the text sits in the safe area between the header rule and the footer wave (measured on the 1054 × 1492 artwork).
 */
export const W = 595.28, H = 841.89, X0 = 44, X1 = W - 44, TOP = H - H * (300 / 1492), BOTTOM = H * (1 - 1190 / 1492);
export const NAVY = rgb(0.043, 0.122, 0.278), GOLD = rgb(0.788, 0.635, 0.294), INK = rgb(0.09, 0.14, 0.23), MUTED = rgb(0.42, 0.47, 0.55);
export const ROW = rgb(0.965, 0.972, 0.985), LINE = rgb(0.86, 0.88, 0.92), GOLDBG = rgb(0.985, 0.955, 0.88), WHITE = rgb(1, 1, 1);

export type Col = { title: string; w: number; align?: "right" | "center" };
export type Row = { cells: string[]; bold?: boolean; sub?: string };
export type SignArt = { seal?: Uint8Array | null; signature?: Uint8Array | null };

export class LetterheadDoc {
  pdf!: PDFDocument; reg!: PDFFont; med!: PDFFont; bold!: PDFFont; lh!: PDFImage;
  page!: PDFPage; y = 0;

  static async create(meta: { title: string; author: string }, letterhead?: Uint8Array | null) {
    const d = new LetterheadDoc(), dir = path.join(process.cwd(), "assets");
    d.pdf = await PDFDocument.create(); d.pdf.registerFontkit(fontkit);
    d.pdf.setTitle(meta.title); d.pdf.setAuthor(meta.author); d.pdf.setCreator("KMR Console");
    [d.reg, d.med, d.bold] = await Promise.all(["Poppins-Regular", "Poppins-Medium", "Poppins-Bold"].map(async (f) => d.pdf.embedFont(await fs.readFile(path.join(dir, "fonts", f + ".ttf")), { subset: true })));
    const bytes = letterhead ?? await fs.readFile(path.join(dir, "letterhead.jpg"));
    d.lh = await d.image(bytes) ?? await d.pdf.embedJpg(await fs.readFile(path.join(dir, "letterhead.jpg")));
    d.newPage();
    return d;
  }

  /** PNG or JPG (WebP and others are skipped — upload PNG / JPG for print) */
  async image(b?: Uint8Array | null): Promise<PDFImage | null> {
    if (!b || b.length < 8) return null;
    try {
      if (b[0] === 0x89 && b[1] === 0x50) return await this.pdf.embedPng(b);
      if (b[0] === 0xff && b[1] === 0xd8) return await this.pdf.embedJpg(b);
    } catch { /* unreadable image */ }
    return null;
  }

  newPage() { this.page = this.pdf.addPage([W, H]); this.page.drawImage(this.lh, { x: 0, y: 0, width: W, height: H }); this.y = TOP; }
  ensure(h: number) { if (this.y - h < BOTTOM) this.newPage(); }
  width(t: string, f: PDFFont, s: number) { return f.widthOfTextAtSize(t, s); }
  text(t: string, x: number, y: number, f: PDFFont, s: number, c = INK) { this.page.drawText(t, { x, y, size: s, font: f, color: c }); }
  right(t: string, x: number, y: number, f: PDFFont, s: number, c = INK) { this.text(t, x - this.width(t, f, s), y, f, s, c); }

  wrap(t: string, f: PDFFont, s: number, w: number): string[] {
    const out: string[] = [];
    for (const para of String(t ?? "").split("\n")) {
      let cur = "";
      for (const word of para.split(/\s+/).filter(Boolean)) {
        const test = cur ? cur + " " + word : word;
        if (this.width(test, f, s) <= w) cur = test;
        else {
          if (cur) out.push(cur); cur = word;
          while (this.width(cur, f, s) > w) { let k = cur.length; while (k > 1 && this.width(cur.slice(0, k), f, s) > w) k--; out.push(cur.slice(0, k)); cur = cur.slice(k); }
        }
      }
      out.push(cur);
    }
    return out;
  }

  para(t: string, f = this.reg, s = 9.2, c = INK, gap = 4, indent = 0) {
    for (const l of this.wrap(t, f, s, X1 - X0 - indent)) { this.ensure(s + 4); this.text(l, X0 + indent, this.y - s, f, s, c); this.y -= s + 4; }
    this.y -= gap;
  }

  title(t: string) {
    this.text(t, (W - this.width(t, this.bold, 17)) / 2, this.y - 17, this.bold, 17, NAVY);
    this.page.drawRectangle({ x: (W - 60) / 2, y: this.y - 24, width: 60, height: 2.2, color: GOLD }); this.y -= 38;
  }

  heading(t: string) {
    this.ensure(40); this.y -= 6;
    this.text(t, X0, this.y - 11, this.bold, 11, NAVY); this.page.drawRectangle({ x: X0, y: this.y - 16, width: 34, height: 2, color: GOLD }); this.y -= 26;
  }

  label(t: string) { this.ensure(16); this.text(t.toUpperCase(), X0, this.y - 8, this.bold, 7.2, GOLD); this.y -= 13; }

  /** grey reference box with up to 4 label / value pairs */
  refBox(pairs: [string, string][]) {
    const bh = 40, n = pairs.length;
    this.page.drawRectangle({ x: X0, y: this.y - bh, width: X1 - X0, height: bh, color: ROW, borderColor: LINE, borderWidth: 0.6 });
    pairs.forEach(([k, v], i) => { const cx = X0 + 10 + i * ((X1 - X0) / n); this.text(k.toUpperCase(), cx, this.y - 15, this.bold, 6.8, MUTED); this.text(v, cx, this.y - 30, this.med, 9.4, NAVY); });
    this.y -= bh + 16;
  }

  /** a table that splits across pages; the header row repeats on each page */
  table(cols: Col[], rows: Row[], opts: { zebra?: boolean } = {}) {
    const total = cols.reduce((a, c) => a + c.w, 0), sc = (X1 - X0) / total, ws = cols.map((c) => c.w * sc);
    const head = () => {
      this.page.drawRectangle({ x: X0, y: this.y - 20, width: X1 - X0, height: 20, color: NAVY });
      let x = X0; cols.forEach((c, i) => {
        const tx = c.align === "right" ? x + ws[i] - 6 - this.width(c.title, this.bold, 8) : c.align === "center" ? x + (ws[i] - this.width(c.title, this.bold, 8)) / 2 : x + 6;
        this.text(c.title, tx, this.y - 13.5, this.bold, 8, WHITE); x += ws[i];
      });
      this.y -= 20;
    };
    this.ensure(46); head();
    rows.forEach((r, ri) => {
      const cl = r.cells.map((c, i) => this.wrap(c, r.bold && i === 1 ? this.med : this.reg, 8.6, ws[i] - 12));
      const sub = r.sub ? this.wrap(r.sub, this.reg, 7.6, ws[1] - 12) : [];
      const h = Math.max(...cl.map((l) => l.length)) * 11.5 + sub.length * 10 + 9;
      if (this.y - h < BOTTOM) { this.newPage(); head(); }
      if (opts.zebra && ri % 2 === 0) this.page.drawRectangle({ x: X0, y: this.y - h, width: X1 - X0, height: h, color: ROW });
      let x = X0;
      cl.forEach((ls, i) => {
        ls.forEach((l, k) => {
          const f = r.bold && i === 1 ? this.med : this.reg, yy = this.y - 12 - k * 11.5;
          if (cols[i].align === "right") this.right(l, x + ws[i] - 6, yy, f, 8.6);
          else if (cols[i].align === "center") this.text(l, x + (ws[i] - this.width(l, f, 8.6)) / 2, yy, f, 8.6);
          else this.text(l, x + 6, yy, f, 8.6);
        });
        if (i === 1) sub.forEach((l, k) => this.text(l, x + 6, this.y - 12 - ls.length * 11.5 - k * 10, this.reg, 7.6, MUTED));
        x += ws[i];
      });
      this.page.drawLine({ start: { x: X0, y: this.y - h }, end: { x: X1, y: this.y - h }, thickness: 0.5, color: LINE });
      this.y -= h;
    });
  }

  /** right-hand totals: label / value rows, then a navy grand-total bar */
  totals(rows: [string, string][], grand: [string, string]) {
    this.ensure(rows.length * 18 + 52);
    const tx = X0 + (X1 - X0) * 0.48;
    rows.forEach(([k, v]) => { this.text(k, tx + 8, this.y - 13, this.med, 9); this.right(v, X1 - 6, this.y - 13, this.med, 9); this.page.drawLine({ start: { x: tx, y: this.y - 18 }, end: { x: X1, y: this.y - 18 }, thickness: 0.5, color: LINE }); this.y -= 18; });
    this.page.drawRectangle({ x: tx, y: this.y - 24, width: X1 - tx, height: 24, color: NAVY });
    this.text(grand[0], tx + 8, this.y - 16, this.bold, 10, GOLD); this.right(grand[1], X1 - 6, this.y - 16, this.bold, 10.5, WHITE); this.y -= 32;
  }

  bullets(items: string[], numbered = false) {
    items.forEach((b, i) => {
      const ls = this.wrap(b, this.reg, 9, X1 - X0 - 20); this.ensure(ls.length * 13);
      if (numbered) this.text(`${i + 1}.`, X0, this.y - 9, this.bold, 9, NAVY); else this.page.drawCircle({ x: X0 + 4, y: this.y - 6, size: 2.2, color: GOLD });
      ls.forEach((l) => { this.text(l, X0 + (numbered ? 18 : 14), this.y - 9, this.reg, 9); this.y -= 13; }); this.y -= 2;
    });
  }

  /** two-column key / value list (bank details) */
  kv(rows: [string, string][], x = X0, w = (X1 - X0) / 2 - 10) {
    rows.forEach(([k, v]) => { const ls = this.wrap(v, this.reg, 8.6, w - 92); this.ensure(ls.length * 12); this.text(k, x, this.y - 9, this.reg, 8.4, MUTED); ls.forEach((l, i) => this.text(l, x + 92, this.y - 9 - i * 12, this.reg, 8.6)); this.y -= ls.length * 12 + 1; });
  }

  /**
   * The signature block. The SIGNATURE sits inside the signatory area, on the line above the signatory's name;
   * the SEAL stands beside the area (to its left), never on top of the signature.
   * acceptance = quotation layout: our signatory area (with the seal beside it) on the left, the customer's on the right.
   */
  async signBlock(o: { company: string; name?: string | null; title?: string | null; art?: SignArt; left?: string; acceptance?: boolean }) {
    const seal = await this.image(o.art?.seal), sig = await this.image(o.art?.signature);
    const half = (X1 - X0 - 20) / 2, h = 104, sealH = o.acceptance ? 64 : 74, sealGap = 10;
    const sealW = seal ? (sealH / seal.height) * seal.width : 0;
    this.ensure(h + 14); this.y -= 8;
    const top = this.y;
    // our signatory area: the right half for invoices, the left half (after the seal) for quotations
    const oursX = o.acceptance ? X0 + (seal ? sealW + sealGap : 0) : X0 + half + 20, oursW = o.acceptance ? half - (seal ? sealW + sealGap : 0) : half;
    if (seal) this.page.drawImage(seal, { x: oursX - sealGap - sealW, y: top - (h - sealH) / 2 - sealH, width: sealW, height: sealH, opacity: 0.92 });
    if (!o.acceptance && o.left) this.wrap(o.left, this.reg, 8, half - (seal ? sealW + 2 * sealGap : 0)).forEach((l, i) => this.text(l, X0, top - 60 - i * 11, this.reg, 8, MUTED));
    const box = (x: number, w: number, title: string, ours: boolean) => {
      // white boxes: a signature scanned on white paper blends in (no white rectangle on a coloured fill)
      this.page.drawRectangle({ x, y: top - h, width: w, height: h, borderColor: ours ? GOLD : LINE, borderWidth: ours ? 1 : 0.8, color: WHITE });
      if (ours) this.page.drawRectangle({ x, y: top - 3, width: w, height: 3, color: GOLD });
      // the heading always fits its box: shrink it, and wrap to two lines if it still does not fit
      const room = w - 20; let fs = 8.6;
      while (fs > 7 && this.width(title, this.bold, fs) > room) fs -= 0.2;
      const tl = this.width(title, this.bold, fs) > room ? this.wrap(title, this.bold, fs, room) : [title];
      tl.slice(0, 2).forEach((l, i) => this.text(l, x + 10, top - 16 - i * (fs + 2), this.bold, fs, NAVY));
      const lineY = top - h + 30, sigTop = top - 22 - (tl.length > 1 ? fs + 2 : 0);
      if (ours && sig) {                                   // the signature rests on the signatory line
        const maxW = w - 20, maxH = Math.min(44, sigTop - lineY - 2), sc = Math.min(maxW / sig.width, maxH / sig.height);
        this.page.drawImage(sig, { x: x + 10, y: lineY + 2, width: sig.width * sc, height: sig.height * sc });
      }
      this.page.drawLine({ start: { x: x + 10, y: lineY }, end: { x: x + w - 10, y: lineY }, thickness: 0.6, color: MUTED });
      if (ours && o.name) this.text(`${o.name}${o.title ? `, ${o.title}` : ""}`, x + 10, top - h + 18, this.med, 8.4, INK);
      this.text(ours ? "Authorised signatory" : "Authorised signatory · name / designation", x + 10, top - h + 7, this.reg, 7.4, MUTED);
    };
    box(oursX, oursW, `For ${o.company}`, true);
    if (o.acceptance) box(X0 + half + 20, half, "Customer acceptance", false);
    this.y -= h + 10;
  }

  /** DRAFT / CANCELLED / PAID across every page, footer reference and page numbers */
  async finish(o: { ref: string; note: string; watermark?: string | null; watermarkColor?: "muted" | "red" | "green" }) {
    const pages = this.pdf.getPages();
    const wc = o.watermarkColor === "red" ? rgb(0.86, 0.15, 0.15) : o.watermarkColor === "green" ? rgb(0.09, 0.64, 0.29) : rgb(0.55, 0.6, 0.68);
    pages.forEach((p, i) => {
      if (o.watermark) {
        const s = 92, tw = this.bold.widthOfTextAtSize(o.watermark, s);
        p.drawText(o.watermark, { x: W / 2 - (tw * Math.cos(Math.PI / 6)) / 2, y: H / 2 - (tw * Math.sin(Math.PI / 6)) / 2 - 20, size: s, font: this.bold, color: wc, opacity: 0.12, rotate: degrees(30) });
      }
      const t = `${o.ref}  ·  Page ${i + 1} of ${pages.length}`;
      p.drawText(t, { x: X1 - this.reg.widthOfTextAtSize(t, 7), y: BOTTOM - 14, size: 7, font: this.reg, color: MUTED });
      p.drawText(o.note, { x: X0, y: BOTTOM - 14, size: 7, font: this.reg, color: MUTED });
    });
    return this.pdf.save();
  }
}

export const fmtDateLong = (d?: string | null) => d ? new Date(d.slice(0, 10) + "T00:00:00Z").toLocaleDateString("en-IN", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" }) : "—";
