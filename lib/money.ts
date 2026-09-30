/** Money formatting for invoices: ₹1,23,456.00 for INR (Indian grouping), $1,234.50 for USD, etc. */
const SYMBOL: Record<string, string> = { INR: "₹", USD: "$", EUR: "€", GBP: "£", AED: "AED ", SGD: "S$" };

export function fmtMoney(amount: number | string | null | undefined, currency: string): string {
  const n = Number(amount ?? 0);
  const s = n.toLocaleString(currency === "INR" ? "en-IN" : "en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return `${SYMBOL[currency] ?? currency + " "}${s}`;
}

const ONES = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen",
  "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
const TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];

function below1000(n: number): string {
  const h = Math.floor(n / 100), r = n % 100;
  const rest = r < 20 ? ONES[r] : `${TENS[Math.floor(r / 10)]}${r % 10 ? " " + ONES[r % 10] : ""}`;
  return [h ? `${ONES[h]} Hundred` : "", rest].filter(Boolean).join(" ");
}

/** Whole number in words: Indian system (lakh, crore) for INR, international (thousand, million) otherwise. */
function words(n: number, indian: boolean): string {
  if (n === 0) return "Zero";
  const parts: string[] = [];
  const steps: [number, string][] = indian
    ? [[1e7, "Crore"], [1e5, "Lakh"], [1e3, "Thousand"]]
    : [[1e9, "Billion"], [1e6, "Million"], [1e3, "Thousand"]];
  for (const [v, name] of steps) {
    if (n >= v) { const q = Math.floor(n / v); parts.push(`${q < 1000 ? below1000(q) : words(q, indian)} ${name}`); n %= v; }
  }
  if (n) parts.push(below1000(n));
  return parts.join(" ");
}

const UNITS: Record<string, [string, string]> = { INR: ["Rupees", "Paise"], USD: ["US Dollars", "Cents"], EUR: ["Euros", "Cents"], GBP: ["Pounds", "Pence"], AED: ["Dirhams", "Fils"], SGD: ["Singapore Dollars", "Cents"] };

/** "Rupees Six Thousand Three Hundred Sixty Eight and Paise Forty Six Only" */
export function amountInWords(amount: number | string, currency: string): string {
  const total = Math.round(Number(amount) * 100);
  const whole = Math.floor(total / 100), fraction = total % 100;
  const [main, sub] = UNITS[currency] ?? [currency, "Cents"];
  const indian = currency === "INR";
  return `${main} ${words(whole, indian)}${fraction ? ` and ${sub} ${words(fraction, indian)}` : ""} Only`;
}
