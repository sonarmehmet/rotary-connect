# Claude Hesapları İçin Devir İstemi

Her yeni hesapta/oturumda aşağıdaki bloğu OLDUĞU GİBİ yapıştırın (depo adını kendi depoyla değiştirin).
Kota bitince başka hesapta aynı bloğu tekrar yapıştırın; "devam" yazmanız yeterlidir.

```
Rotary Connect projesinde çalışıyoruz. Depo: https://github.com/<KULLANICI>/<DEPO>
Birden fazla Claude hesabı bu depoda sırayla çalışıyor; sohbet hafızası paylaşılmıyor, kaynak doğruluk depodur.

BAŞLANGIÇ (zorunlu):
1. Depoyu klonla/çek (git pull). docs/PROGRESS.md, docs/AGENT_PROMPT.md ve docs/DECISIONS.md dosyalarını oku.
2. PROGRESS.md'deki "Sıradaki iş" bölümünden devam et. Onaylanmış kararları değiştirme.
3. Başka bir hesabın yarım bıraktığı işi önce tamamla; mevcut dosyaları izinsiz silme.

ÇALIŞMA KURALLARI:
- Kendine ait dal aç: stage<N>/<kisa-konu> (örn. stage3/mobile-home). main'e doğrudan itme; küçük, sık commit at.
- Aynı dosyayı iki hesap düzenlemesin: PROGRESS.md'deki "Kilitler" bölümüne hangi klasör/modül üzerinde çalıştığını yaz, push et, sonra başla.
- Tutarlar kuruş cinsinden tam sayı; durum makinesi Dart (packages/shared) ve TS (functions) tarafında birebir aynı kalmalı. İstemci finansal koleksiyonlara yazamaz.
- Gizli anahtar, google-services.json, .env commit etme.
- Çalıştırabildiğin her testi çalıştır; çalıştıramadığını PROGRESS.md "DOĞRULANMAMIŞ" bölümüne yaz. Doğrulamadığın şeyi çalışıyor diye raporlama.
- Kota bitmeden önce: işi commit + push et, PROGRESS.md'yi (yapılanlar, yarım kalanlar, sıradaki adım) güncelle. Kota bittiyse bile son commit mesajına durumu yaz.

BİTİRİRKEN: PROGRESS.md "Oturum kayıtları"na tarih + hesap numarası + ne yapıldığını ekle, push et, kullanıcıya 3 satırlık özet ver.
```

## Not (kullanıcıya)

- Claude'un GitHub'a push edebilmesi, o hesapta GitHub bağlantısının/izninin açık olmasına bağlıdır. Olmazsa kodu zip/.sh olarak alıp kendi makinenizden `git push` yapın.
- Aşama 8 (ödeme sağlayıcı seçimi) ve hukuki metinler için hesaplar arası karar çelişkisi olmasın diye bu kararları siz verip DECISIONS.md'ye yazın.
