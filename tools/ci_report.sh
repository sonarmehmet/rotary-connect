#!/usr/bin/env bash
# Komutu çalıştırır; başarısızsa çıktının önemli satırlarını GitHub "annotation" olarak yazar
# (günlük dosyası indirilemeyen ortamlarda hata API'den okunabilsin diye). Kullanım: ci_report.sh ad komut...
name="$1"; shift
out=$(mktemp)
"$@" >"$out" 2>&1
code=$?
cat "$out"
if [ $code -ne 0 ]; then
  grep -E "error|Error|FAIL|Failed|failed|✗|Exception|Expected|Actual|\[E\]|warning •|info •|rror •|Some tests|Could not|Because|version solving" "$out" \
    | head -45 | cut -c1-400 | while IFS= read -r line; do
      line=${line//'%'/'%25'}; line=${line//$'\r'/}
      echo "::error title=$name::$line"
    done
fi
exit $code
