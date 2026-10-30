# Mimari Kararlar (ADR özeti)

| # | Karar | Gerekçe | Durum |
|---|---|---|---|
| 1 | Flutter + Riverpod + GoRouter, feature-first | İstek + tek kod tabanı | Onaylı |
| 2 | Web panel Flutter Web | Tek dil, kota/mesaj tasarrufu; tablo ağırlıklı ekranlarda React daha rahat olurdu | Onaylı (kullanıcı delegasyonu) |
| 3 | Firebase + Cloud Functions (TS) | Hızlı kurulum; finans yazmaları Admin SDK ile | Onaylı |
| 4 | Para: kuruş tamsayı + currency | Kayan nokta hatası yok | Onaylı |
| 5 | Rol: Auth custom claim `role` | Kurallar ve Functions aynı kaynağı okur | Onaylı |
| 6 | Raporlar önceden toplanmış (aggregate) belgelerden | Firestore'da ağır toplama sorguları pahalı/yavaş | Plan |
| 7 | Ödeme sağlayıcı | **iyzico (Checkout Form / HPP)** seçildi (2026-10-30, kullanıcı kararı delege etti). Webhook imzası X-IYZ-SIGNATURE-V3; tutar webhook gövdesinden değil iyzico'dan sunucu-sunucu sorgulanır. Gerekçe: Türkiye'de yerleşik, dernek/kulüp için yaygın, imzalı webhook. Sözleşme/komisyon ve iyzico hesabı (sandbox → canlı) kullanıcı tarafından açılmalı. PayTR yedek aday. | **KARAR VERİLDİ — iyzico sandbox ile denenmedi** |
| 8 | Kontenjan: transaction + süreli rezervasyon (öneri 15 dk) | Aşırı kayıt önleme | Plan (Aşama 7) |
| 9 | Üyelik doğrulama yönetici onayıyla `club_member` claim'i | Kayıt = üye değildir | Plan (Aşama 4) |
