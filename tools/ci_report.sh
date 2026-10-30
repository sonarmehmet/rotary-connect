#!/usr/bin/env bash
# Komutu çalıştırır; başarısızsa önemli çıktıyı GitHub "annotation" olarak yazar (günlük indirilemeyen
# ortamlarda hata API'den okunabilsin diye). GitHub adım başına en fazla 10 annotation gösterir; bu yüzden
# satırlar birkaç büyük parçada (%0A ile) paketlenir. Kullanım: ci_report.sh ad komut...
name="$1"; shift
out=$(mktemp)
"$@" >"$out" 2>&1
code=$?
cat "$out"
if [ $code -ne 0 ]; then
  pick=$(mktemp)
  {
    grep -E "\(failed\)|^ *error •|^ *warning •|Some tests|Could not|Because|version solving|rror:" "$out"
    grep -A16 -E "EXCEPTION CAUGHT" "$out"
    grep -E "Warning|would not hit|Expected:|Actual:|Which:" "$out"
  } | grep -vE "^--$|^\s*$" | awk '!seen[$0]++' | cut -c1-300 | head -120 >"$pick"
  python3 - "$name" "$pick" <<'PY'
import sys
name, path = sys.argv[1], sys.argv[2]
lines = [l.rstrip("\r\n") for l in open(path, encoding="utf-8", errors="replace")]
chunks, cur, size = [], [], 0
for l in lines:
    if size + len(l) > 3000 and cur:
        chunks.append(cur); cur, size = [], 0
    cur.append(l); size += len(l) + 3
if cur: chunks.append(cur)
for c in chunks[:8]:
    msg = "%0A".join(x.replace("%", "%25").replace("\n", "") for x in c)
    print(f"::error title={name}::{msg}")
PY
fi
exit $code
