# Görev Dağılımı (3 Claude hesabı)

Önce `docs/DATA_MODEL.md` (ortak sözleşme) okunur. Klasör sahipliği ayrıdır; başka hesabın klasörüne dokunulmaz,
gerekirse `PROGRESS.md` > "Değişiklik istekleri" bölümüne yazılır. Her hesap kendi dalında çalışır
(`a/...`, `b/...`, `c/...`) ve tamamlanan parçayı `main`'e PR/merge ile alır; merge öncesi `git pull --rebase origin main`.

| Hesap | Sahip olduğu klasörler |
|---|---|
| **A** | `apps/mobile`, `packages/shared`, `docs/` |
| **B** | `apps/admin_web` |
| **C** | `functions`, `firebase`, `tests` |

## Dalga 1 (şimdi, paralel; örnek veri/emülatörsüz çalışılabilir)

**Hesap A — mobil ekranlar (Aşama 3)**
1. `features/home`: öne çıkan proje, kampanya kartı (ilerleme çubuğu), yaklaşan etkinlikler, haber, iletişim; role göre bloklar.
2. `features/donations`: kategori/kampanya seçimi → hızlı tutar (250/500/1.000/2.500 + özel, `Money.tryParseTr`) → bağışçı formu → ödeme sonucu ekranı (simülasyon etiketli).
3. `features/events`: kart (duruma göre buton), detay, kayıt formu, kayıt onayı.
4. `features/dues`: borç listesi, durum rozetleri, ödeme geçmişi (yalnızca club_member).
5. `features/auth`, `features/profile`: giriş/kayıt/şifre sıfırlama formları (backend bağlantısı yok, doğrulama var), profil, bildirim tercihleri.
6. Ortak: boş/yükleniyor/hata/başarı bileşenleri, repository arayüzleri + `Fake...Repository` (örnek veri `TestDataBanner` ile işaretli).
Kabul: `flutter analyze` temiz, widget testleri, 360 px genişlikte taşma yok.

**Hesap B — admin panel ekranları (Aşama 3 + 9'un arayüz kısmı)**
1. Ortak tablo bileşeni: arama, filtre, sayfalama, tarih aralığı, boş/hata durumu.
2. Genel Bakış kartları (toplamlar ayrı: bağış/aidat/etkinlik; iade düşülmüş) — örnek veriyle.
3. Liste + form ekranları: Kampanyalar, Etkinlikler, Projeler, Haberler, Aidat dönemleri/borçlar, Ödemeler, İadeler, Denetim kayıtları.
4. CSV dışa aktarma arayüzü (yetki kontrolü bayrağı ile, backend `exportReport` sonra bağlanır).
Kabul: 1400 px ve 800 px genişlikte düzgün; `flutter analyze` temiz; rol filtresi testleri.

**Hesap C — backend çekirdeği (Aşama 4–7'nin sunucu tarafı)**
1. `firebase-admin` + `firebase-functions` ekle; `DATA_MODEL.md` callable sözleşmesini uygula: `startPayment`, `paymentWebhook` (idempotent, transaction), `reconcilePending`, `recordManualPayment`, `issueRefund`.
2. Kontenjan: `reserveEventSpot`, `cancelRegistration`, `expireReservations` + bekleme listesi (Firestore transaction; eşzamanlılık testi).
3. Aidat: `createDue`/`assignDues`, kısmi ödeme kuralı, `overdue` zamanlayıcı; `report_aggregates` güncelleme.
4. `tests/rules/`: Firestore emülatör testleri (her rol için okuma/yazma matrisi, sayaçların istemciden değiştirilememesi).
5. Her kritik işlemde `audit_logs` kaydı; loglara kişisel veri yazılmaz.
Kabul: `npm test` yeşil; emülatör testleri (çalıştırılabiliyorsa) yeşil, çalıştırılamadıysa `PROGRESS.md` DOĞRULANMAMIŞ bölümüne yazılır.

## Dalga 2 (Dalga 1 merge edildikten sonra)

- **A:** Firebase istemci bağlantısı (Auth, Firestore, Messaging), repository'lerin gerçek uygulamaları, kayıt/giriş/üyelik talebi, bildirim izinleri; mobil ödeme akışı (`startPayment` + sonuç sorgulama).
- **B:** Panelin gerçek veriye bağlanması, rol atama, üyelik onayı, iade ve manuel ödeme ekranları, `exportReport`.
- **C:** FCM bildirim function'ları, `exportReport`, KVKK silme/anonimleştirme, rate limit/App Check.

## Dalga 3

- **Ödeme sağlayıcı entegrasyonu (Aşama 8):** kullanıcı sağlayıcıyı seçip `DECISIONS.md` #7'yi kapattıktan sonra, C yapar (A/B ödeme sayfası yönlendirmesini uyarlar).
- **Aşama 10–11:** test matrisi, yayın hazırlığı, KVKK/gizlilik/iade metin taslakları (hukuk onayı gerekir), kurulum kılavuzları. Boşta olan hesap alır.

## Entegrasyon sözleşmeleri

- Mobil/panel repository arayüzleri Dalga 1'de sahte, Dalga 2'de gerçek uygulamayla değişir; arayüz imzaları değişmez.
- Hata kodları (functions → istemci): `permission-denied`, `invalid-argument`, `failed-precondition` (ör. kontenjan dolu), `already-exists` (mükerrer işlem), `unavailable`. İstemci bunları Türkçe mesaja eşler.
- Tutar istemciden yalnızca bağışta gelir (min 1 ₺, max sunucu ayarı); aidat/etkinlikte tutar sunucuda belirlenir.
