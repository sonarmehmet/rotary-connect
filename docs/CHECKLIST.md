# Kontrol Listesi (planlanan işler ve durumu)

`[x]` = kod yazıldı. Ancak Flutter kodu henüz HİÇ derlenmedi/çalıştırılmadı, backend testleri yerel test
çatısıyla geçti (gerçek vitest ve Firebase henüz denenmedi). Güncel sayılar için: `bash tools/progress.sh`.
Her hesap işini bitirince kendi bölümünü işaretler.

## Mobil (Hesap A) — apps/mobile
- [x] İskelet: tema, yönlendirme, ortam bayrakları, ortak logo/test-verisi bandı
- [x] Ana sayfa kartları (kampanya, etkinlik, proje, haber)
- [x] Bağış akışı (kategori/kampanya, tutar, bağışçı formu, sonuç)
- [x] Etkinlikler (kart, detay, kayıt formu, onay)
- [x] Aidat ekranı (borçlar, geçmiş)
- [x] Giriş / kayıt formları (şifre sıfırlama yalnızca mesaj, Aşama 4)
- [x] Profil (KVKK silme talebi yalnızca iletişim kutusu; bildirim tercihleri ve bildirim listesi YOK)
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
- [x] requestMembership (mantık)       - [x] approveMembership (mantık)     - [ ] assignRole
- [x] assignDues (mantık)              - [x] startPayment (mantık; bağış işleyicisi var, aidat/etkinlik işleyicisi yok)
- [x] paymentWebhook (mantık; sağlayıcıya özel imza yok)   - [x] reconcilePending (mantık)
- [x] recordManualPayment (mantık + işleyici)   - [x] issueRefund (B: adminOps; simülasyon ödemesi, gerçek sağlayıcı iadesi henüz yok)
- [x] reserveEventSpot (mantık + işleyici)      - [x] cancelRegistration (mantık + işleyici)
- [x] expireReservations (mantık)      - [ ] getDonationReceipt   - [ ] exportReport
- [x] requestAccountDeletion (yalnızca plan)    - [x] sendAnnouncement (mantık + işleyici)
- [x] Ödeme sonucu etkileri (borç, bağış, kampanya toplamı, etkinlik kaydı, bildirim)
- [x] Firestore adaptörleri (etkinlik, ödeme, ödeme etkileri; sahte Firestore ile test)
- [x] startDuePayment / startEventFeePayment işleyicileri, webhook→etkiler akışı (`pipeline.ts`), etki tarama (`sweepEffects`)
- [ ] firebase-admin SDK sarmalayıcısı (`adapters/sdk.ts`)       - [ ] onCall/HTTP sarmalayıcıları (`src/handlers` → Firebase)
- [ ] Zamanlanmış işler (mutabakat, rezervasyon süresi, aidat gecikmesi/hatırlatma)
- [ ] Firestore kuralları emülatör testleri (`tests/rules/`)

## Ortak
- [x] packages/shared (Money, roller, ödeme durumu, renkler)
- [ ] Ödeme sağlayıcı seçimi ve entegrasyonu (KULLANICI KARARI bekliyor)
- [ ] KVKK/gizlilik/iade metin taslakları (hukuk onayı gerekir)
- [ ] Android/iOS derleme ve yayın hazırlığı
