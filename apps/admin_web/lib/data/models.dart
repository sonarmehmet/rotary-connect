import 'package:rotary_shared/shared.dart';

import '../core/format.dart';

// Alan adları docs/DATA_MODEL.md ile birebir aynıdır. Bu modeller Dalga 2'de
// packages/shared'e taşınırsa yalnızca import değişir.
// Tutarlar kuruş cinsinden TAM SAYI (`...Minor`), zamanlar UTC anıdır.

// ---------------------------------------------------------------------------
// Bağış kampanyaları
// ---------------------------------------------------------------------------

enum CampaignCategory {
  education('education', 'Eğitim'),
  health('health', 'Sağlık'),
  scholarship('scholarship', 'Burs'),
  children('children', 'Çocuk'),
  disaster('disaster', 'Afet'),
  environment('environment', 'Çevre'),
  general('general', 'Genel');

  const CampaignCategory(this.wireName, this.label);
  final String wireName;
  final String label;
}

enum CampaignStatus {
  draft('draft', 'Taslak'),
  active('active', 'Aktif'),
  completed('completed', 'Tamamlandı'),
  archived('archived', 'Arşiv');

  const CampaignStatus(this.wireName, this.label);
  final String wireName;
  final String label;
}

class Campaign {
  const Campaign({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.goalMinor,
    required this.status,
    required this.createdAt,
    this.currency = 'TRY',
    this.verifiedTotalMinor = 0,
    this.donorCount = 0,
    this.endsAt,
    this.projectId,
    this.eventId,
  });

  /// Boş kimlik = yeni kayıt (kimliği sunucu/depo üretir).
  final String id;
  final String title;
  final String description;
  final CampaignCategory category;
  final int goalMinor;
  final String currency;

  /// Yalnızca Functions değiştirir (iade olursa düşer). İstemci yazmaz.
  final int verifiedTotalMinor;
  final int donorCount;
  final CampaignStatus status;
  final DateTime? endsAt;
  final String? projectId;
  final String? eventId;
  final DateTime createdAt;

  double get progress {
    if (goalMinor <= 0) return 0;
    final ratio = verifiedTotalMinor / goalMinor;
    if (ratio > 1) return 1;
    if (ratio < 0) return 0;
    return ratio;
  }

  Campaign withId(String newId) => Campaign(
        id: newId,
        title: title,
        description: description,
        category: category,
        goalMinor: goalMinor,
        status: status,
        createdAt: createdAt,
        currency: currency,
        verifiedTotalMinor: verifiedTotalMinor,
        donorCount: donorCount,
        endsAt: endsAt,
        projectId: projectId,
        eventId: eventId,
      );
}

// ---------------------------------------------------------------------------
// Etkinlikler
// ---------------------------------------------------------------------------

enum EventStatus {
  draft('draft', 'Taslak'),
  published('published', 'Yayında'),
  cancelled('cancelled', 'İptal'),
  completed('completed', 'Tamamlandı');

  const EventStatus(this.wireName, this.label);
  final String wireName;
  final String label;
}

class ClubEvent {
  const ClubEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.startsAt,
    required this.registrationDeadline,
    required this.capacity,
    required this.status,
    required this.refundPolicy,
    required this.organizerName,
    required this.organizerContact,
    required this.createdAt,
    this.program,
    this.endsAt,
    this.feeMinor = 0,
    this.currency = 'TRY',
    this.reservedCount = 0,
    this.confirmedCount = 0,
    this.waitlistEnabled = false,
    this.donationCampaignId,
  });

  final String id;
  final String title;
  final String description;
  final String? program;
  final String location;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime registrationDeadline;

  /// 0 = ücretsiz.
  final int feeMinor;
  final String currency;
  final int capacity;

  /// Yalnızca Functions transaction'ıyla değişir.
  final int reservedCount;
  final int confirmedCount;
  final bool waitlistEnabled;
  final EventStatus status;
  final String? donationCampaignId;
  final String refundPolicy;
  final String organizerName;
  final String organizerContact;
  final DateTime createdAt;

  bool get isFree => feeMinor == 0;

  /// Kalan yer = kontenjan − onaylı − rezerve.
  int get remaining => capacity - confirmedCount - reservedCount;

  ClubEvent withId(String newId) => ClubEvent(
        id: newId,
        title: title,
        description: description,
        location: location,
        startsAt: startsAt,
        registrationDeadline: registrationDeadline,
        capacity: capacity,
        status: status,
        refundPolicy: refundPolicy,
        organizerName: organizerName,
        organizerContact: organizerContact,
        createdAt: createdAt,
        program: program,
        endsAt: endsAt,
        feeMinor: feeMinor,
        currency: currency,
        reservedCount: reservedCount,
        confirmedCount: confirmedCount,
        waitlistEnabled: waitlistEnabled,
        donationCampaignId: donationCampaignId,
      );
}

// ---------------------------------------------------------------------------
// Projeler
// ---------------------------------------------------------------------------

enum ProjectStatus {
  draft('draft', 'Taslak'),
  ongoing('ongoing', 'Devam ediyor'),
  completed('completed', 'Tamamlandı');

  const ProjectStatus(this.wireName, this.label);
  final String wireName;
  final String label;
}

class Project {
  const Project({
    required this.id,
    required this.title,
    required this.description,
    required this.leadName,
    required this.status,
    required this.startDate,
    required this.goals,
    this.endDate,
    this.verifiedResults,
    this.campaignId,
  });

  final String id;
  final String title;
  final String description;
  final String leadName;
  final ProjectStatus status;
  final DateTime startDate;
  final DateTime? endDate;
  final String goals;
  final String? verifiedResults;
  final String? campaignId;

  Project withId(String newId) => Project(
        id: newId,
        title: title,
        description: description,
        leadName: leadName,
        status: status,
        startDate: startDate,
        goals: goals,
        endDate: endDate,
        verifiedResults: verifiedResults,
        campaignId: campaignId,
      );
}

// ---------------------------------------------------------------------------
// Haberler ve duyurular (news/{id} ve announcements/{id} aynı şekilde)
// ---------------------------------------------------------------------------

enum NewsKind {
  news('news', 'Haber'),
  announcement('announcement', 'Duyuru');

  const NewsKind(this.wireName, this.label);
  final String wireName;
  final String label;
}

class NewsItem {
  const NewsItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.category,
    required this.published,
    required this.authorId,
    this.publishedAt,
    this.pinned = false,
  });

  final String id;
  final NewsKind kind;
  final String title;
  final String body;
  final String category;
  final bool published;
  final DateTime? publishedAt;
  final String authorId;

  /// Yalnızca duyurularda anlamlıdır.
  final bool pinned;

  NewsItem withId(String newId) => NewsItem(
        id: newId,
        kind: kind,
        title: title,
        body: body,
        category: category,
        published: published,
        authorId: authorId,
        publishedAt: publishedAt,
        pinned: pinned,
      );
}

// ---------------------------------------------------------------------------
// Aidat
// ---------------------------------------------------------------------------

enum DueStatus {
  unpaid('unpaid', 'Ödenmedi'),
  partiallyPaid('partially_paid', 'Kısmen ödendi'),
  paid('paid', 'Ödendi'),
  overdue('overdue', 'Gecikmiş'),
  cancelled('cancelled', 'İptal'),
  refunded('refunded', 'İade edildi');

  const DueStatus(this.wireName, this.label);
  final String wireName;
  final String label;
}

/// membership_dues/{id}. Yazma: yalnızca Functions.
class MembershipDue {
  const MembershipDue({
    required this.id,
    required this.userId,
    required this.userName,
    required this.memberId,
    required this.periodId,
    required this.periodLabel,
    required this.amountMinor,
    required this.paidMinor,
    required this.dueDate,
    required this.status,
    required this.allowPartial,
    required this.createdAt,
    this.currency = 'TRY',
  });

  final String id;
  final String userId;

  /// Görüntüleme için users/{userId}'den çözülmüş ad (belgede tutulmaz).
  final String userName;
  final String memberId;
  final String periodId;
  final String periodLabel;
  final int amountMinor;
  final String currency;
  final int paidMinor;
  final DateTime dueDate;
  final DueStatus status;
  final bool allowPartial;
  final DateTime createdAt;

  int get remainingMinor => amountMinor - paidMinor;
}

/// Borç atanabilecek üye (club_members + users birleşimi, yalnızca aktifler).
class MemberOption {
  const MemberOption({
    required this.id,
    required this.userId,
    required this.name,
    required this.memberNo,
  });

  final String id;
  final String userId;
  final String name;
  final String memberNo;
}

// ---------------------------------------------------------------------------
// Ödemeler ve iadeler
// ---------------------------------------------------------------------------

/// payments/{id}. Yazma: yalnızca Functions.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.kind,
    required this.refId,
    required this.amountMinor,
    required this.status,
    required this.provider,
    required this.simulated,
    required this.idempotencyKey,
    required this.manual,
    required this.createdAt,
    required this.updatedAt,
    this.currency = 'TRY',
    this.userId,
    this.providerRef,
    this.recordedBy,
    this.note,
    this.failureCode,
    this.refundedMinor = 0,
    this.succeededAt,
  });

  final String id;
  final PaymentKind kind;
  final String refId;
  final String? userId;
  final int amountMinor;
  final String currency;
  final PaymentStatus status;
  final String provider;
  final String? providerRef;
  final bool simulated;
  final String idempotencyKey;
  final bool manual;
  final String? recordedBy;
  final String? note;
  final String? failureCode;
  final int refundedMinor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? succeededAt;

  /// Bu ödemeden iade edilebilecek en çok tutar (sunucu kuralı belirleyicidir).
  int get refundableMinor => amountMinor - refundedMinor;

  bool get isRefundable => status.countsAsCollected && refundableMinor > 0;
}

enum RefundStatus {
  pending('pending', 'Beklemede'),
  succeeded('succeeded', 'Tamamlandı'),
  failed('failed', 'Başarısız');

  const RefundStatus(this.wireName, this.label);
  final String wireName;
  final String label;
}

/// refunds/{id}. Yazma: yalnızca Functions.
class RefundRecord {
  const RefundRecord({
    required this.id,
    required this.paymentId,
    required this.kind,
    required this.amountMinor,
    required this.reason,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
    this.currency = 'TRY',
    this.providerRef,
  });

  final String id;
  final String paymentId;
  final PaymentKind kind;
  final int amountMinor;
  final String currency;
  final String reason;
  final RefundStatus status;
  final String requestedBy;
  final String? providerRef;
  final DateTime createdAt;
}

// ---------------------------------------------------------------------------
// Denetim kayıtları ve raporlar
// ---------------------------------------------------------------------------

/// audit_logs/{id}. Değiştirilemez; yalnızca Functions yazar. Kişisel veri içermez.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.actorId,
    required this.actorRole,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.createdAt,
    this.before,
    this.after,
  });

  final String id;
  final String actorId;
  final String actorRole;

  /// Örn. `payment.manual_record`, `refund.issue`, `role.assign`, `export.financial`.
  final String action;
  final String targetType;
  final String targetId;
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
  final DateTime createdAt;
}

/// report_aggregates/{id}: önceden toplanmış tutarlar.
///
/// `collectedMinor` BRÜT tahsilattır (sonradan iade edilenler dahil);
/// net = collected − refunded. Bağış/aidat/etkinlik ayrı satırlardır.
class ReportAggregate {
  const ReportAggregate({
    required this.period,
    required this.kind,
    required this.collectedMinor,
    required this.refundedMinor,
    required this.count,
    this.currency = 'TRY',
  });

  /// "yyyy-MM" (İstanbul ayı).
  final String period;
  final PaymentKind kind;
  final int collectedMinor;
  final int refundedMinor;
  final int count;
  final String currency;

  int get netMinor => collectedMinor - refundedMinor;
}

// ---------------------------------------------------------------------------
// Callable istekleri (istemci → Functions)
// ---------------------------------------------------------------------------

/// `createDue` / `assignDues`.
class NewDuesRequest {
  const NewDuesRequest({
    required this.periodLabel,
    required this.amountMinor,
    required this.dueDate,
    required this.allowPartial,
    this.memberId,
  });

  final String periodLabel;
  final int amountMinor;
  final DateTime dueDate;
  final bool allowPartial;

  /// `null` = tüm aktif üyelere ata.
  final String? memberId;
}

/// `recordManualPayment`. `idempotencyKey` form açılırken üretilir; çift
/// tıklama/yeniden deneme ikinci kayıt oluşturmaz (`already-exists`).
class ManualPaymentRequest {
  const ManualPaymentRequest({
    required this.kind,
    required this.refId,
    required this.amountMinor,
    required this.note,
    required this.idempotencyKey,
  });

  final PaymentKind kind;
  final String refId;
  final int amountMinor;
  final String note;
  final String idempotencyKey;
}

/// `issueRefund`.
class RefundRequest {
  const RefundRequest({
    required this.paymentId,
    required this.amountMinor,
    required this.reason,
  });

  final String paymentId;
  final int amountMinor;
  final String reason;
}

enum ExportKind {
  payments('payments', 'Ödemeler'),
  dues('dues', 'Aidat borçları'),
  refunds('refunds', 'İadeler');

  const ExportKind(this.wireName, this.label);
  final String wireName;
  final String label;
}

/// `exportReport`.
class ExportRequest {
  const ExportRequest({required this.kind, this.range});

  final ExportKind kind;

  /// `null` = tüm tarihler.
  final DateRange? range;
}

// ---------------------------------------------------------------------------
// Üyelik, kullanıcı rolleri, etkinlik kayıtları
// ---------------------------------------------------------------------------

enum MemberStatus {
  pending('pending', 'Onay bekliyor'),
  active('active', 'Aktif'),
  suspended('suspended', 'Askıda'),
  resigned('resigned', 'İstifa etti');

  const MemberStatus(this.wireName, this.label);
  final String wireName;
  final String label;
}

/// club_members/{id} + users/{userId} görünümü. Yazma: yalnızca Functions.
class ClubMember {
  const ClubMember({
    required this.id,
    required this.userId,
    required this.userName,
    required this.status,
    required this.requestedAt,
    this.memberNo,
    this.joinedAt,
  });

  final String id;
  final String userId;
  final String userName;
  final MemberStatus status;
  final String? memberNo;
  final DateTime requestedAt;
  final DateTime? joinedAt;
}

/// Rol atama ekranı için kullanıcı satırı (rol: Auth claim).
class AppUserRow {
  const AppUserRow({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;
  final AppRole role;
}

enum RegistrationStatus {
  reserved('reserved', 'Rezerve'),
  confirmed('confirmed', 'Onaylı'),
  waitlisted('waitlisted', 'Bekleme listesinde'),
  cancelled('cancelled', 'İptal'),
  expired('expired', 'Süresi doldu'),
  refunded('refunded', 'İade edildi');

  const RegistrationStatus(this.wireName, this.label);
  final String wireName;
  final String label;
}

/// event_registrations/{id}. Yazma: yalnızca Functions.
class EventRegistration {
  const EventRegistration({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.participantName,
    required this.status,
    required this.createdAt,
    this.paymentId,
    this.reservedUntil,
    this.waitlistPosition,
  });

  final String id;
  final String eventId;

  /// Görüntüleme için çözülmüş etkinlik adı (belgede tutulmaz).
  final String eventTitle;
  final String participantName;
  final RegistrationStatus status;
  final String? paymentId;
  final DateTime? reservedUntil;
  final int? waitlistPosition;
  final DateTime createdAt;
}

// ---------------------------------------------------------------------------
// Uygulama ayarları (app_settings/public)
// ---------------------------------------------------------------------------

/// app_settings/public. Yazma: yalnızca sistem yöneticisi.
/// `paymentMode` panelden DEĞİŞTİRİLMEZ (canlı geçiş sağlayıcı kararına bağlı).
class AppSettings {
  const AppSettings({
    required this.clubName,
    required this.contact,
    required this.reservationMinutes,
    required this.donationQuickAmountsMinor,
    required this.partialDuesEnabled,
    required this.recurringDonationEnabled,
    required this.paymentMode,
  });

  final String clubName;
  final String contact;
  final int reservationMinutes;
  final List<int> donationQuickAmountsMinor;
  final bool partialDuesEnabled;
  final bool recurringDonationEnabled;

  /// `simulation` | `live`.
  final String paymentMode;

  AppSettings copyWith({
    String? clubName,
    String? contact,
    int? reservationMinutes,
    List<int>? donationQuickAmountsMinor,
    bool? partialDuesEnabled,
    bool? recurringDonationEnabled,
  }) =>
      AppSettings(
        clubName: clubName ?? this.clubName,
        contact: contact ?? this.contact,
        reservationMinutes: reservationMinutes ?? this.reservationMinutes,
        donationQuickAmountsMinor:
            donationQuickAmountsMinor ?? this.donationQuickAmountsMinor,
        partialDuesEnabled: partialDuesEnabled ?? this.partialDuesEnabled,
        recurringDonationEnabled:
            recurringDonationEnabled ?? this.recurringDonationEnabled,
        paymentMode: paymentMode,
      );
}

// ---------------------------------------------------------------------------
// Duyuru / bildirim gönderimi (`sendAnnouncement`)
// ---------------------------------------------------------------------------

enum AnnouncementAudience {
  all('all', 'Tüm kullanıcılar'),
  members('members', 'Kulüp üyeleri'),
  role('role', 'Belirli bir rol');

  const AnnouncementAudience(this.wireName, this.label);
  final String wireName;
  final String label;
}

/// Duyurunun açacağı uygulama sayfası (sunucudaki `ANNOUNCE_ROUTES`).
/// Finansal sayfa (`/dues`) bilerek yoktur.
enum AnnouncementRoute {
  news('/news', 'Haberler'),
  events('/events', 'Etkinlikler'),
  projects('/projects', 'Projeler'),
  donate('/donate', 'Bağış'),
  profile('/profile', 'Profil');

  const AnnouncementRoute(this.path, this.label);
  final String path;
  final String label;
}

/// `sendAnnouncement`. `clientKey` idempotency anahtarıdır (8-64, [A-Za-z0-9_-]).
class AnnouncementRequest {
  const AnnouncementRequest({
    required this.audience,
    required this.title,
    required this.body,
    required this.route,
    required this.clientKey,
    this.role,
  });

  final AnnouncementAudience audience;

  /// Yalnızca `audience == role` iken.
  final AppRole? role;
  final String title;
  final String body;
  final AnnouncementRoute route;
  final String clientKey;
}

class AnnouncementResult {
  const AnnouncementResult({
    required this.recipients,
    required this.sent,
    required this.skippedByPreferences,
  });

  final int recipients;
  final int sent;
  final int skippedByPreferences;
}
