/**
 * CSV üretimi (Türkçe Excel): ayraç `;`, UTF-8 BOM, CRLF. Panelin `core/csv.dart` ile AYNI kurallar.
 * Formül enjeksiyonu önlemi: `=`, `+`, `@`, TAB, CR ve sayı olmayan `-` ile başlayan hücrenin
 * başına `'` konur.
 */
export const CSV_DELIMITER = ";";

const FORMULA_START = /^([=+@\t\r]|-(?!\d))/;

export function csvCell(value: string): string {
  let v = value;
  if (FORMULA_START.test(v)) v = `'${v}`;
  if (v.includes(CSV_DELIMITER) || v.includes('"') || v.includes("\n") || v.includes("\r")) {
    v = `"${v.replace(/"/g, '""')}"`;
  }
  return v;
}

export function buildCsv(header: readonly string[], rows: readonly (readonly string[])[]): string {
  const lines = [header, ...rows].map((r) => r.map(csvCell).join(CSV_DELIMITER));
  return "﻿" + lines.join("\r\n") + "\r\n";
}

/** Kuruşu Türkçe biçime çevirir: 125050 → "1.250,50 ₺". Yalnızca TRY için sembol kullanır. */
export function formatMoney(minor: number, currency = "TRY"): string {
  const abs = Math.abs(minor);
  const whole = Math.floor(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  const frac = String(abs % 100).padStart(2, "0");
  return `${minor < 0 ? "-" : ""}${whole},${frac} ${currency === "TRY" ? "₺" : currency}`;
}
