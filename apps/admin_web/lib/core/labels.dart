import 'package:rotary_shared/shared.dart';

import '../data/models.dart';

/// Durum rozetinin rengi (anlam: başarı, hata, uyarı, nötr, bilgi).
enum StatusTone { success, danger, warning, neutral, info }

extension PaymentStatusLabels on PaymentStatus {
  String get labelTr => switch (this) {
        PaymentStatus.created => 'Oluşturuldu',
        PaymentStatus.pending => 'Beklemede',
        PaymentStatus.succeeded => 'Başarılı',
        PaymentStatus.failed => 'Başarısız',
        PaymentStatus.cancelled => 'İptal',
        PaymentStatus.refunded => 'İade edildi',
        PaymentStatus.partiallyRefunded => 'Kısmen iade',
      };

  StatusTone get tone => switch (this) {
        PaymentStatus.created => StatusTone.neutral,
        PaymentStatus.pending => StatusTone.warning,
        PaymentStatus.succeeded => StatusTone.success,
        PaymentStatus.failed => StatusTone.danger,
        PaymentStatus.cancelled => StatusTone.neutral,
        PaymentStatus.refunded => StatusTone.info,
        PaymentStatus.partiallyRefunded => StatusTone.info,
      };
}

extension PaymentKindLabels on PaymentKind {
  String get labelTr => switch (this) {
        PaymentKind.membershipDue => 'Aidat',
        PaymentKind.donation => 'Bağış',
        PaymentKind.eventFee => 'Etkinlik ücreti',
      };
}

extension CampaignStatusTone on CampaignStatus {
  StatusTone get tone => switch (this) {
        CampaignStatus.draft => StatusTone.neutral,
        CampaignStatus.active => StatusTone.success,
        CampaignStatus.completed => StatusTone.info,
        CampaignStatus.archived => StatusTone.neutral,
      };
}

extension EventStatusTone on EventStatus {
  StatusTone get tone => switch (this) {
        EventStatus.draft => StatusTone.neutral,
        EventStatus.published => StatusTone.success,
        EventStatus.cancelled => StatusTone.danger,
        EventStatus.completed => StatusTone.info,
      };
}

extension ProjectStatusTone on ProjectStatus {
  StatusTone get tone => switch (this) {
        ProjectStatus.draft => StatusTone.neutral,
        ProjectStatus.ongoing => StatusTone.success,
        ProjectStatus.completed => StatusTone.info,
      };
}

extension DueStatusTone on DueStatus {
  StatusTone get tone => switch (this) {
        DueStatus.unpaid => StatusTone.warning,
        DueStatus.partiallyPaid => StatusTone.info,
        DueStatus.paid => StatusTone.success,
        DueStatus.overdue => StatusTone.danger,
        DueStatus.cancelled => StatusTone.neutral,
        DueStatus.refunded => StatusTone.info,
      };
}

extension RefundStatusTone on RefundStatus {
  StatusTone get tone => switch (this) {
        RefundStatus.pending => StatusTone.warning,
        RefundStatus.succeeded => StatusTone.success,
        RefundStatus.failed => StatusTone.danger,
      };
}

extension AppRoleLabels on AppRole {
  String get labelTr => switch (this) {
        AppRole.visitor => 'Ziyaretçi',
        AppRole.registeredUser => 'Kayıtlı kullanıcı',
        AppRole.clubMember => 'Kulüp üyesi',
        AppRole.contentManager => 'İçerik yöneticisi',
        AppRole.financeManager => 'Finans yöneticisi',
        AppRole.systemAdmin => 'Sistem yöneticisi',
      };
}

extension MemberStatusTone on MemberStatus {
  StatusTone get tone => switch (this) {
        MemberStatus.pending => StatusTone.warning,
        MemberStatus.active => StatusTone.success,
        MemberStatus.suspended => StatusTone.danger,
        MemberStatus.resigned => StatusTone.neutral,
      };
}

extension RegistrationStatusTone on RegistrationStatus {
  StatusTone get tone => switch (this) {
        RegistrationStatus.reserved => StatusTone.warning,
        RegistrationStatus.confirmed => StatusTone.success,
        RegistrationStatus.waitlisted => StatusTone.info,
        RegistrationStatus.cancelled => StatusTone.neutral,
        RegistrationStatus.expired => StatusTone.neutral,
        RegistrationStatus.refunded => StatusTone.info,
      };
}
