/// Functions → istemci hata sözleşmesi: `code` + isteğe bağlı `reason`
/// (functions/src/handlers/callableError.ts). Kodlar: `unauthenticated`,
/// `permission-denied`, `invalid-argument`, `failed-precondition`,
/// `already-exists`, `not-found`, `unavailable`, `internal`.
class AdminException implements Exception {
  const AdminException(this.code, [this.message, this.reason]);

  final String code;

  /// Türkçe, kullanıcıya gösterilebilir ayrıntı (isteğe bağlı).
  final String? message;

  /// Makine tarafından okunabilir ince ayrım (örn. `sold_out`).
  final String? reason;

  @override
  String toString() => 'AdminException($code${reason == null ? '' : '/$reason'})';
}

/// Sunucunun `reason` değerlerinin Türkçe karşılıkları. Bilinmeyen reason için
/// `code` ve (varsa) sunucu mesajına düşülür.
const Map<String, String> reasonMessagesTr = {
  'key_amount_mismatch': 'Bu işlem anahtarı farklı bir tutarla kullanılmış.',
  'duplicate_manual_payment': 'Bu manuel ödeme zaten kaydedilmiş.',
  'already_requested': 'Üyelik talebi zaten var.',
  'campaign_not_active': 'Bu kampanya şu an bağış kabul etmiyor.',
  'not_refundable': 'Bu ödeme iade edilemez.',
  'simulated_in_live': 'Canlı modda simülasyon sağlayıcısı kullanılamaz.',
  'not_active': 'Yalnızca aktif üyelik sonlandırılabilir.',
  'not_pending': 'Yalnızca bekleyen talepler onaylanabilir.',
  'sold_out': 'Etkinlik kontenjanı dolu.',
  'deadline_passed': 'Kayıt süresi geçti.',
  'event_not_open': 'Etkinlik kayda açık değil.',
  'already_registered': 'Bu etkinliğe zaten kayıtlısınız.',
  'free_event': 'Ücretsiz etkinlik için ödeme gerekmez.',
  'invalid_amount': 'Tutar geçersiz.',
  'note_required': 'Açıklama en az 5 karakter olmalı.',
  'above_maximum': 'Tutar izin verilen üst sınırı aşıyor.',
  'below_minimum': 'Tutar çok düşük.',
  'due_date_in_past': 'Son ödeme tarihi gelecekte olmalı.',
  'future_date': 'Ödeme tarihi gelecekte olamaz.',
  'member_no_required': 'Üye numarası gerekli.',
  'exceeds_remaining': 'İade tutarı kalan tutarı aşıyor.',
  'bad_client_key': 'İşlem anahtarı geçersiz.',
  'invalid_clientKey': 'İşlem anahtarı geçersiz.',
  'event_not_found': 'Etkinlik bulunamadı.',
  'campaign_not_found': 'Kampanya bulunamadı.',
  'registration_not_found': 'Kayıt bulunamadı.',
  'login_required': 'Bu işlem için giriş yapmalısınız.',
  'user_not_found': 'Kullanıcı bulunamadı.',
  'member_not_found': 'Üyelik kaydı bulunamadı.',
  'payment_not_found': 'Ödeme bulunamadı.',
  'same_role': 'Kullanıcı zaten bu role sahip.',
  'use_membership_flow':
      'Üyeliği sonlandırmak için Kullanıcı ve Üyeler ekranını kullanın.',
  'last_admin': 'Son sistem yöneticisinin rolü değiştirilemez.',
  'member_no_taken': 'Bu üye numarası zaten kullanılıyor.',
  'member_not_active': 'Yalnızca aktif üyelere aidat atanır.',
  'already_assigned': 'Bu dönem için borçlar zaten atanmış.',
  'provider_refund_unavailable': 'Sağlayıcı iadesi henüz desteklenmiyor.',
  'too_many_rows': 'Çok fazla satır: tarih aralığını daraltın.',
  'invalid_range': 'Başlangıç tarihi bitişten sonra olamaz.',
  'due_not_found': 'Borç bulunamadı.',
  'already_cancelled': 'Bu borç zaten iptal edilmiş.',
  'due_has_payments':
      'Ödemesi alınmış borç iptal edilemez; önce ödemeyi iade edin.',
  'invalid_reason': 'Gerekçe en az 5 karakter olmalı.',
  'sensitive_content':
      'Metin tutar, e-posta veya telefon gibi kişisel/finansal bilgi içeremez.',
};

/// Hata kodunu Türkçe kullanıcı mesajına eşler. Sunucu iç ayrıntıları gösterilmez.
/// Öncelik: bilinen `reason` → sunucunun Türkçe mesajı → `code` genel metni.
String errorMessageTr(Object error) {
  if (error is AdminException) {
    final byReason = reasonMessagesTr[error.reason];
    if (byReason != null) return byReason;
    switch (error.code) {
      case 'unauthenticated':
        return 'Bu işlem için giriş yapmalısınız.';
      case 'permission-denied':
        return 'Bu işlem için yetkiniz yok.';
      case 'invalid-argument':
        return error.message ?? 'Girilen bilgiler geçersiz.';
      case 'failed-precondition':
        return error.message ?? 'İşlem şu anki durumda yapılamıyor.';
      case 'already-exists':
        return error.message ?? 'Bu işlem zaten kaydedilmiş.';
      case 'not-found':
        return error.message ?? 'Kayıt bulunamadı.';
      case 'unavailable':
        return 'Sunucuya şu an ulaşılamıyor. Lütfen tekrar deneyin.';
    }
  }
  return 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
}
