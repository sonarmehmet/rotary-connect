/// Türkçe Excel'in beklediği ayraç.
const String csvDelimiter = ';';

final RegExp _formulaStart = RegExp(r'^([=+@\t\r]|-(?!\d))');

/// Tek hücreyi CSV'ye hazırlar.
///
/// - Excel'de formül olarak çalışabilecek başlangıçlar (`=`, `+`, `@`, ve
///   sayı olmayan `-`) başına `'` konur (CSV/formül enjeksiyonu önlemi).
/// - Ayraç, çift tırnak veya satır sonu içeren hücreler tırnaklanır.
String csvCell(String value) {
  var v = value;
  if (_formulaStart.hasMatch(v)) v = "'$v";
  final needsQuotes = v.contains(csvDelimiter) ||
      v.contains('"') ||
      v.contains('\n') ||
      v.contains('\r');
  if (needsQuotes) v = '"${v.replaceAll('"', '""')}"';
  return v;
}

/// Başlık + satırlardan CSV üretir. Excel'in UTF-8'i tanıması için BOM ile
/// başlar, satır sonu CRLF'dir.
String buildCsv(List<String> header, List<List<String>> rows) {
  final buffer = StringBuffer('﻿');
  buffer.write(header.map(csvCell).join(csvDelimiter));
  buffer.write('\r\n');
  for (final row in rows) {
    buffer.write(row.map(csvCell).join(csvDelimiter));
    buffer.write('\r\n');
  }
  return buffer.toString();
}
