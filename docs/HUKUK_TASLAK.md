# Hukuk metinleri — TASLAK (yayından önce avukat onayı ŞART)

> Bu metinler uygulamanın GERÇEK veri akışına göre hazırlanmış çalışma taslaklarıdır; hukuki görüş değildir. `[KÖŞELİ]` alanları kulüp doldurur. Yayından önce KVKK ve tüketici mevzuatı yönünden bir avukat gözden geçirmelidir. Bağış kabulü için derneğin/kulübün hukuki statüsüne göre ek izin/bildirim (ör. yardım toplama mevzuatı) gerekip gerekmediği ayrıca teyit edilmelidir.

## 1. Kişisel Verilerin İşlenmesine İlişkin Aydınlatma Metni (KVKK m.10)

**Veri sorumlusu:** [KULÜP/DERNEK TAM ÜNVANI], [ADRES], [E-POSTA], [KEP/TELEFON].

**İşlenen veriler ve amaçlar**
| Veri | Amaç | Hukuki sebep (KVKK m.5) |
|---|---|---|
| Ad-soyad, e-posta, (varsa) telefon | Hesap oluşturma, giriş, iletişim | Sözleşmenin kurulması/ifası |
| Üyelik bilgileri (üye no, durum, tarihler) | Üyelik yönetimi, aidat takibi | Sözleşme, meşru menfaat |
| Bağış, aidat, etkinlik ücreti ödeme kayıtları (tutar, tarih, durum, sağlayıcı referansı) | Tahsilat, makbuz, iade, muhasebe | Hukuki yükümlülük, sözleşme |
| Etkinlik kayıtları (katılımcı adı, e-posta) | Kontenjan ve katılım yönetimi | Sözleşme |
| Bildirim tercihleri, cihaz bildirim anahtarı (FCM) | Anlık bildirim gönderimi | Açık rıza / sözleşme |
| İşlem ve denetim kayıtları (yönetici işlemleri) | Güvenlik, hesap verebilirlik | Meşru menfaat, hukuki yükümlülük |

- **Kart bilgileri uygulamamızda veya sunucularımızda SAKLANMAZ**; ödeme, lisanslı ödeme kuruluşu [iyzico] tarafından işlenir.
- **Aktarım:** Ödeme kuruluşu ([iyzico Ödeme Hizmetleri A.Ş.]), bulut altyapı sağlayıcısı (Google Firebase/Google Cloud — yurt dışı aktarım olabilir; KVKK m.9 kapsamında [açık rıza/standart sözleşme] ile), yasal talep hâlinde yetkili kurumlar.
- **Saklama:** Hesap verileri hesap silinene kadar; ödeme/mali kayıtlar ilgili mevzuattaki süre boyunca ([10 yıl — doğrulayın]) kimliksizleştirilerek saklanır.
- **Haklarınız (m.11):** Öğrenme, düzeltme, silme/yok etme, itiraz, zarar giderim talebi. Başvuru: [E-POSTA]. Uygulama içinden "Hesabımı sil" talebi oluşturabilirsiniz; yasal saklama yükümlülüğü olan mali kayıtlar kimliksizleştirilir.

## 2. Gizlilik Politikası (özet)
- Topladığımız veriler yukarıdaki tabloyla sınırlıdır; reklam amaçlı izleme ve üçüncü taraf reklam SDK'sı kullanılmaz [teyit edin].
- Misafir bağışçıdan yalnızca makbuz için gereken bilgiler istenir; "Anonim bağış" seçildiğinde adınız kulüp dışına ve diğer kullanıcılara gösterilmez.
- Bildirimleri ayarlardan kapatabilirsiniz (etkinlik, aidat, bağış, duyuru ayrı ayrı).
- Güvenlik: Aktarımda şifreleme (TLS), rol tabanlı erişim, finansal kayıtlara yalnızca sunucu üzerinden yazılır, yönetici işlemleri denetim kaydına alınır.

## 3. Bağış Koşulları
1. Bağışlar [KULÜP ADI] tarafından [AMAÇ/PROJELER] için kullanılır; kampanya hedefi aşılırsa fazla tutar [aynı amaçlı diğer çalışmalara aktarılır — kulüp kararı].
2. Kampanya sayfasındaki "toplanan" tutar yalnızca doğrulanmış (başarıyla tahsil edilmiş) bağışları gösterir.
3. Bağış makbuzu e-posta/uygulama üzerinden sunulur; [vergi indirimi uygunluğu kulübün statüsüne bağlıdır — doldurun].
4. Hatalı/mükerrer bağışlar için bkz. İade ve İptal.

## 4. İade ve İptal Koşulları
- **Aidat:** Yanlış veya mükerrer tahsilat, kulüp yönetimine yazılı başvuru üzerine [14] gün içinde iade edilir; iade ödemenin yapıldığı yönteme yapılır. Dönem aidatının iadesi üyelik ilkelerine tabidir: [doldurun].
- **Bağış:** Hatalı tutar veya mükerrer işlemde [14] gün içinde başvuru hâlinde iade edilir. Kampanya amacına fiilen kullanılmış bağışların iadesi [kulüp kararına bağlıdır — doldurun].
- **Etkinlik ücreti:** Her etkinlik sayfasındaki "iade politikası" geçerlidir. Etkinlik kulüp tarafından iptal edilirse ücret tam iade edilir. Katılımcı iptalinde [etkinlikten X gün öncesine kadar tam/kısmi iade — doldurun]. Bekleme listesinden gelen yer rezervasyonu [15 dk] içinde ödenmezse düşer.
- **Süre ve tutar:** İade tutarı ödenen tutarı aşamaz; kısmi iade yapılabilir. Bankaya yansıma süresi kart çıkaran kuruma göre [2-10 iş günü].
- **Mesafeli satış:** Etkinlik ücreti belirli tarihli hizmet olduğundan cayma hakkı istisnası kapsamında olabilir (Mesafeli Sözleşmeler Yönetmeliği m.15) — avukatla teyit edin; bağış ve aidat tüketici satışı niteliğinde değildir [teyit edin].
- **Başvuru:** [E-POSTA] veya uygulamadaki iletişim bilgisi; gerekçe ve ödeme referansı belirtilmelidir.

## 5. Uygulamada gösterilecek yerler (yapılacak)
Kayıt ekranında aydınlatma metni bağlantısı + gizlilik politikası onayı (açık rıza gerektiren bildirimler ayrı ve işaretsiz kutu), bağış ve ödeme ekranında Bağış/İade koşulları bağlantısı, profil → "Hesabımı sil", mağaza sayfalarında gizlilik politikası URL'si.
