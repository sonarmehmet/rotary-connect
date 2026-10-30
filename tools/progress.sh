#!/usr/bin/env bash
# İlerleme sayacı: depodaki dosya/test sayıları ve modül kapsamı. Kullanım: bash tools/progress.sh
set -u
cd "$(dirname "$0")/.."
echo "=== Rotary Connect ilerleme ($(date +%F)) ==="
printf "%-18s %6s %6s %6s %8s\n" Klasör Toplam Kod Test "Test(adet)"
for d in apps/mobile apps/admin_web packages/shared functions firebase docs tests tools; do
  files=$(git ls-files "$d" 2>/dev/null)
  all=$(printf "%s\n" "$files" | grep -c . || true)
  tst=$(printf "%s\n" "$files" | grep -cE '(_test\.dart|\.test\.ts)$' || true)
  code=$(printf "%s\n" "$files" | grep -E '\.(dart|ts)$' | grep -vcE '(_test\.dart|\.test\.ts)$' || true)
  n=0
  for f in $(printf "%s\n" "$files" | grep -E '(_test\.dart|\.test\.ts)$'); do
    n=$((n + $(grep -cE "^\s*(it|test|testWidgets)\(" "$f" || true)))
  done
  printf "%-18s %6s %6s %6s %8s\n" "$d" "$all" "$code" "$tst" "$n"
done
echo "TOPLAM izlenen dosya: $(git ls-files | wc -l)"
echo
mods=$(grep -c "AdminModule('" apps/admin_web/lib/core/modules.dart 2>/dev/null || echo 0)
feats=$(git ls-files apps/admin_web/lib/features 2>/dev/null | awk -F/ '{print $5}' | sort -u | grep -c . || true)
echo "Admin panel: $mods modülden ~$feats özellik klasörü var (tek tek eşleşme için docs/CHECKLIST.md)"
mfeat=$(git ls-files apps/mobile/lib/features 2>/dev/null | awk -F/ '{print $4}' | sort -u | grep -c . || true)
echo "Mobil: planlanan 6 özellikten (home, donations, events, dues, auth, profile) $mfeat klasör var"
echo
echo "Kontrol listesi özeti (docs/CHECKLIST.md): $(grep -c '^- \[x\]' docs/CHECKLIST.md) tamam, $(grep -c '^- \[ \]' docs/CHECKLIST.md) bekliyor"
