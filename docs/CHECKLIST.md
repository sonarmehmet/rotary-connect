# Kontrol Listesi (planlanan işler ve durumu)

`[x]` = kod yazıldı. DOĞRULAMA (2026-10-31, GitHub Actions `CI`, gerçek ortam): backend derleme+vitest, Firestore kural testleri (emülatör), Flutter analyze+test (shared, mobil, admin) YEŞİL. Hâlâ denenmemiş: iyzico sandbox (ödeme/iade uç noktaları), Firebase'e gerçek bağlantı (emülatör/deploy), mobilin Firebase'e bağlanması. Güncel sayılar için: `bash tools/progress.sh`.
Her hesap işini bitirince kendi bölümünü işaretler.

## Mobil (Hesap A) — apps/mobile
- [x] İskelet: tema, yönlendirme, ortam bayrakları, ortak logo/test-verisi bandı
- [x] Ana sayfa kartları (kampanya, etkinlik, proje, haber)
- [x] Bağış akışı (kategori/kampanya, tutar, bağışçı formu, sonuç)
- [x] Etkinlikler (kart, detay, kayıt formu, onay)
- [x] Aidat ekranı (borçlar, geçmiş)
- [x] Giriş / kayıt formları (şifre sıfırlama yalnızca mesaj, Aşama 4)
- [x] Profil (KVKK silme talebi yalnızca iletişim kutusu; bildirim tercih ekranı VAR)
- [x] Yükleniyor / boş / hata / başarı bileşenleri
- [x] Sahte repository'ler (örnek veri)
- [ ] Firebase bağlantısı (Aşama 4, ağ gerekir)

## Admin panel (Hesap B) — apps/admin_web (16 modül)
- [x] Genel Bakış   - [x] Üyeler   - [x] Rol ve İzinler   - [x] Aidat   - [x] Kampanyalar
- [x] Bağış Kayıtları   - [x] Etkinlikler   - [x] Katılımcı Kayıtları   - [x] Projeler   - [x] Haberler
- [x] Ödemeler   - [x] İadeler   - [x] Bildirimler   - [x] Raporlar/CSV
- [x] Denetim   - [x] Ayarlar
- [ ] Gerçek veriye bağlama (Aşama 9, ağ gerekir)

## Backend (Hesap C) — functions
Callable sözleşmesi (DATA_MODEL.md) — "mantık" = test edilmiş iş kuralı, "sarmalayıcı" = Firebase `onCall`/HTTP bağlantısı (HİÇBİRİ yok):
- [x] requestMembership (mantık)       - [x] approveMembership (mantık)     - [x] assignRole (B: adminOps)
- [x] assignDues (mantık)              - [x] startPayment (mantık; bağış işleyicisi var, aidat/etkinlik işleyicisi yok)
- [x] paymentWebhook (mantık; sağlayıcıya özel imza yok)   - [x] reconcilePending (mantık)
- [x] recordManualPayment (mantık + işleyici)   - [x] issueRefund (B: adminOps; simülasyon ödemesi, gerçek sağlayıcı iadesi henüz yok)
- [x] reserveEventSpot (mantık + işleyici)      - [x] cancelRegistration (mantık + işleyici)
- [x] expireReservations (mantık)      - [x] getDonationReceipt (mantık + işleyici)   - [x] exportReport (B: adminOps)
- [x] requestAccountDeletion (talep işleyicisi; gerçek silme/anonimleştirme yürütücüsü YOK)    - [x] sendAnnouncement (mantık + işleyici)
- [x] Ödeme sonucu etkileri (borç, bağış, kampanya toplamı, etkinlik kaydı, bildirim)
- [x] Firestore adaptörleri (etkinlik, ödeme, ödeme etkileri; sahte Firestore ile test)
- [x] startDuePayment / startEventFeePayment işleyicileri, webhook→etkiler akışı (`pipeline.ts`), etki tarama (`sweepEffects`)
- [x] firebase-admin SDK sarmalayıcısı (`src/firebase/sdk.ts`, `stores.ts`) ve onCall/HTTP/onSchedule bağlantısı (`src/firebase/main.ts`) — YAZILDI ama DERLENMEDİ (paketler kurulamadı)
- [x] B'nin adminOps işleyicileri (+cancelDue, iade etkileri, tarama) için Firestore adaptörleri + onCall bağlantısı (emülatörde ÇALIŞTIRILMADI)
- [x] Zamanlanmış iş gövdeleri (`jobs/scheduled.ts`: rezervasyon süresi, aidat gecikme/hatırlatma, mutabakat); `onSchedule` bağlantısı YOK
- [x] Firestore kuralları emülatör testleri (`tests/rules/`) — yazıldı, ÇALIŞTIRILMADI
- [x] iyzico adaptörü (oturum, sonuç sorgusu, V3 HPP imza, webhook işleyici) — sandbox'ta DENENMEDİ
- [x] KVKK silme yürütücüsü (`privacy/executeDeletion.ts`; talep → `deletion_requests`, saatlik iş)

## Ortak
- [x] packages/shared (Money, roller, ödeme durumu, renkler)
- [x] Ödeme sağlayıcı seçimi: iyzico (bkz. DECISIONS #7); iyzico para iadesi (`IyzicoProvider.refund`, `issueRefund` içinde önce sağlayıcı sonra kayıt) YAZILDI, sandbox'ta DENENMEDİ
- [x] KVKK/gizlilik/iade metin taslakları → docs/HUKUK_TASLAK.md (avukat onayı ŞART; uygulamada gösterim bağlantıları YAPILACAK)
- [~] Android/iOS derleme ve yayın hazırlığı: klasörler, ad/izin/imza ayarı, build-apps iş akışı, docs/YAYIN.md hazır; derleme ve mağaza işlemleri DOĞRULANMADI
