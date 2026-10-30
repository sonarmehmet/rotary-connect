import 'package:rotary_shared/shared.dart';

import '../core/format.dart';
import 'models.dart';

/// Dalga 1 örnek verisi. TÜM kayıtlar uydurmadır; gerçek kişi/ödeme içermez.
/// Tarihler sabittir (testler deterministik kalsın diye `DateTime.now()` yok).
class SampleData {
  SampleData({
    required this.campaigns,
    required this.events,
    required this.projects,
    required this.news,
    required this.members,
    required this.dues,
    required this.payments,
    required this.refunds,
    required this.auditLogs,
  });

  final List<Campaign> campaigns;
  final List<ClubEvent> events;
  final List<Project> projects;
  final List<NewsItem> news;
  final List<MemberOption> members;
  final List<MembershipDue> dues;
  final List<PaymentRecord> payments;
  final List<RefundRecord> refunds;
  final List<AuditLogEntry> auditLogs;

  /// Örnek verinin "bugünü": 29 Ekim 2026, 12:00 (İstanbul).
  static final DateTime now = istanbulToInstant(2026, 10, 29, 12);

  factory SampleData.standard() {
    final payments = _buildPayments();
    return SampleData(
      campaigns: _campaigns(),
      events: _events(),
      projects: _projects(),
      news: _news(),
      members: _members(),
      dues: _dues(),
      payments: payments,
      refunds: _refundsFor(payments),
      auditLogs: _auditLogs(),
    );
  }
}

DateTime _day(int y, int m, int d, [int h = 0, int min = 0]) =>
    istanbulToInstant(y, m, d, h, min);

List<Campaign> _campaigns() => [
      Campaign(
        id: 'cmp_1',
        title: 'Köy Okulu Kütüphane Projesi',
        description: 'Üç köy okulunun kütüphanesini kitap ve rafla donatıyoruz.',
        category: CampaignCategory.education,
        goalMinor: 15000000,
        verifiedTotalMinor: 6250000,
        donorCount: 84,
        status: CampaignStatus.active,
        endsAt: _day(2026, 12, 31, 23, 59),
        createdAt: _day(2026, 8, 3, 10),
      ),
      Campaign(
        id: 'cmp_2',
        title: 'Burs Fonu 2026-2027',
        description: 'Başarılı ve ihtiyaç sahibi öğrencilere dönemlik burs.',
        category: CampaignCategory.scholarship,
        goalMinor: 20000000,
        verifiedTotalMinor: 12480000,
        donorCount: 143,
        status: CampaignStatus.active,
        createdAt: _day(2026, 9, 1, 9),
      ),
      Campaign(
        id: 'cmp_3',
        title: 'Sağlık Taraması Kampanyası',
        description: 'Mobil sağlık taraması aracının işletme gideri.',
        category: CampaignCategory.health,
        goalMinor: 5000000,
        verifiedTotalMinor: 5000000,
        donorCount: 61,
        status: CampaignStatus.completed,
        createdAt: _day(2026, 4, 12, 9),
      ),
      Campaign(
        id: 'cmp_4',
        title: 'Orman Yeniden Yeşersin',
        description: 'Yanan alanda fidan dikimi için kaynak toplama (taslak).',
        category: CampaignCategory.environment,
        goalMinor: 3000000,
        status: CampaignStatus.draft,
        createdAt: _day(2026, 10, 20, 15),
      ),
      Campaign(
        id: 'cmp_5',
        title: 'Afet Yardım Fonu',
        description: 'Deprem bölgesi için acil yardım fonu.',
        category: CampaignCategory.disaster,
        goalMinor: 10000000,
        verifiedTotalMinor: 9120000,
        donorCount: 212,
        status: CampaignStatus.archived,
        createdAt: _day(2026, 2, 8, 8),
      ),
    ];

List<ClubEvent> _events() => [
      ClubEvent(
        id: 'evt_1',
        title: 'Yıllık Dayanışma Yemeği',
        description: 'Kulüp üyeleri ve davetlilerle geleneksel dayanışma yemeği.',
        program: '19:00 Karşılama\n20:00 Yemek\n21:30 Kampanya sunumu',
        location: 'Örnek Otel Balo Salonu',
        startsAt: _day(2026, 11, 14, 19),
        endsAt: _day(2026, 11, 14, 23),
        registrationDeadline: _day(2026, 11, 10, 23, 59),
        feeMinor: 75000,
        capacity: 120,
        confirmedCount: 87,
        reservedCount: 6,
        waitlistEnabled: true,
        status: EventStatus.published,
        donationCampaignId: 'cmp_2',
        refundPolicy: 'Etkinliğe 7 gün kalana dek ücretsiz iptal ve iade.',
        organizerName: 'Organizasyon Komitesi',
        organizerContact: 'komite@ornek.invalid',
        createdAt: _day(2026, 9, 20, 11),
      ),
      ClubEvent(
        id: 'evt_2',
        title: 'Fidan Dikim Günü',
        description: 'Aileler için açık hava fidan dikimi.',
        location: 'Örnek Mesire Alanı',
        startsAt: _day(2026, 11, 22, 10),
        registrationDeadline: _day(2026, 11, 20, 23, 59),
        capacity: 200,
        confirmedCount: 45,
        status: EventStatus.published,
        refundPolicy: 'Ücretsiz etkinlik.',
        organizerName: 'Çevre Komitesi',
        organizerContact: 'cevre@ornek.invalid',
        createdAt: _day(2026, 10, 2, 10),
      ),
      ClubEvent(
        id: 'evt_3',
        title: 'Meslek Tanıtım Semineri',
        description: 'Lise öğrencilerine meslek tanıtımı (taslak).',
        location: 'Örnek Lise Konferans Salonu',
        startsAt: _day(2026, 12, 5, 14),
        registrationDeadline: _day(2026, 12, 3, 23, 59),
        capacity: 60,
        status: EventStatus.draft,
        refundPolicy: 'Ücretsiz etkinlik.',
        organizerName: 'Meslek Hizmetleri',
        organizerContact: 'meslek@ornek.invalid',
        createdAt: _day(2026, 10, 25, 16),
      ),
      ClubEvent(
        id: 'evt_4',
        title: 'Sonbahar Kermesi',
        description: 'Burs fonu yararına kermes.',
        location: 'Örnek Okul Bahçesi',
        startsAt: _day(2026, 10, 10, 11),
        registrationDeadline: _day(2026, 10, 8, 23, 59),
        feeMinor: 25000,
        capacity: 300,
        confirmedCount: 280,
        status: EventStatus.completed,
        refundPolicy: 'Etkinlik sonrası iade yapılmaz.',
        organizerName: 'Organizasyon Komitesi',
        organizerContact: 'komite@ornek.invalid',
        createdAt: _day(2026, 8, 30, 9),
      ),
      ClubEvent(
        id: 'evt_5',
        title: 'Tarihi Yerler Gezisi',
        description: 'Hava koşulları nedeniyle iptal edildi.',
        location: 'Örnek Antik Kent',
        startsAt: _day(2026, 10, 18, 8),
        registrationDeadline: _day(2026, 10, 15, 23, 59),
        feeMinor: 45000,
        capacity: 40,
        status: EventStatus.cancelled,
        refundPolicy: 'İptalde tam iade.',
        organizerName: 'Gezi Komitesi',
        organizerContact: 'gezi@ornek.invalid',
        createdAt: _day(2026, 9, 5, 9),
      ),
    ];

List<Project> _projects() => [
      Project(
        id: 'prj_1',
        title: 'Köy Okulu Kütüphane Projesi',
        description: 'Üç köy okuluna kütüphane kurulumu.',
        leadName: 'Örnek Proje Sorumlusu 1',
        status: ProjectStatus.ongoing,
        startDate: _day(2026, 8, 1),
        goals: '3 kütüphane, 1.500 kitap',
        campaignId: 'cmp_1',
      ),
      Project(
        id: 'prj_2',
        title: 'Mobil Sağlık Taraması',
        description: 'Kırsalda ücretsiz sağlık taraması.',
        leadName: 'Örnek Proje Sorumlusu 2',
        status: ProjectStatus.completed,
        startDate: _day(2026, 4, 1),
        endDate: _day(2026, 9, 30),
        goals: '600 kişiye tarama',
        verifiedResults: '642 kişiye tarama yapıldı.',
        campaignId: 'cmp_3',
      ),
      Project(
        id: 'prj_3',
        title: 'Genç Girişimci Atölyeleri',
        description: 'Lise öğrencileri için girişimcilik atölyeleri (taslak).',
        leadName: 'Örnek Proje Sorumlusu 3',
        status: ProjectStatus.draft,
        startDate: _day(2027, 1, 15),
        goals: '4 atölye, 100 katılımcı',
      ),
    ];

List<NewsItem> _news() => [
      NewsItem(
        id: 'new_1',
        kind: NewsKind.news,
        title: 'Sağlık taraması projemiz tamamlandı',
        body: '642 kişiye ulaşan tarama programı başarıyla tamamlandı.',
        category: 'Proje',
        published: true,
        publishedAt: _day(2026, 10, 1, 9),
        authorId: 'usr_demo',
      ),
      NewsItem(
        id: 'new_2',
        kind: NewsKind.news,
        title: 'Burs fonu başvuruları başladı',
        body: 'Başvurular 30 Kasım\'a kadar açıktır.',
        category: 'Burs',
        published: false,
        authorId: 'usr_demo',
      ),
      NewsItem(
        id: 'ann_1',
        kind: NewsKind.announcement,
        title: 'Dayanışma yemeği kayıtları açıldı',
        body: 'Kayıtlar 10 Kasım\'a kadar sürecektir.',
        category: 'Etkinlik',
        published: true,
        publishedAt: _day(2026, 10, 22, 12),
        authorId: 'usr_demo',
        pinned: true,
      ),
      NewsItem(
        id: 'ann_2',
        kind: NewsKind.announcement,
        title: 'Aidat dönemi hatırlatması',
        body: '2026-2027 dönemi aidat vadesi 15 Ekim idi.',
        category: 'Aidat',
        published: true,
        publishedAt: _day(2026, 10, 16, 9),
        authorId: 'usr_demo',
      ),
    ];

List<MemberOption> _members() => [
      for (var i = 1; i <= 6; i++)
        MemberOption(
          id: 'mem_$i',
          userId: 'usr_$i',
          name: 'Örnek Üye $i',
          memberNo: 'ÜY-${i.toString().padLeft(4, '0')}',
        ),
    ];

List<MembershipDue> _dues() {
  final members = _members();
  final dues = <MembershipDue>[];
  // 2025-2026: eski dönem; 4 ödendi, 2 gecikmiş.
  for (var i = 0; i < members.length; i++) {
    final m = members[i];
    final paid = i < 4;
    dues.add(
      MembershipDue(
        id: 'due_a$i',
        userId: m.userId,
        userName: m.name,
        memberId: m.id,
        periodId: 'per_2025',
        periodLabel: '2025-2026',
        amountMinor: 100000,
        paidMinor: paid ? 100000 : 0,
        dueDate: _day(2025, 10, 15),
        status: paid ? DueStatus.paid : DueStatus.overdue,
        allowPartial: false,
        createdAt: _day(2025, 9, 1, 9),
      ),
    );
  }
  // 2026-2027: güncel dönem.
  const statuses = [
    DueStatus.paid,
    DueStatus.paid,
    DueStatus.partiallyPaid,
    DueStatus.unpaid,
    DueStatus.unpaid,
    DueStatus.overdue,
  ];
  for (var i = 0; i < members.length; i++) {
    final m = members[i];
    final status = statuses[i];
    final due = i == 5 ? _day(2026, 10, 15) : _day(2026, 11, 30);
    final paidMinor = switch (status) {
      DueStatus.paid => 120000,
      DueStatus.partiallyPaid => 60000,
      _ => 0,
    };
    dues.add(
      MembershipDue(
        id: 'due_b$i',
        userId: m.userId,
        userName: m.name,
        memberId: m.id,
        periodId: 'per_2026',
        periodLabel: '2026-2027',
        amountMinor: 120000,
        paidMinor: paidMinor,
        dueDate: due,
        status: status,
        allowPartial: i == 2 || i == 3,
        createdAt: _day(2026, 9, 1, 9),
      ),
    );
  }
  return dues;
}

/// 24 ödeme: tür, durum ve tutar çeşitliliği sayfalama/filtre denemesi içindir.
List<PaymentRecord> _buildPayments() {
  const kinds = [
    PaymentKind.donation,
    PaymentKind.membershipDue,
    PaymentKind.eventFee,
    PaymentKind.donation,
  ];
  const amounts = [50000, 120000, 75000, 25000];
  final payments = <PaymentRecord>[];
  for (var i = 0; i < 24; i++) {
    final kind = kinds[i % 4];
    final amount = amounts[i % 4];
    final slot = i % 8;
    final PaymentStatus status;
    var refunded = 0;
    if (slot <= 4) {
      status = PaymentStatus.succeeded;
    } else if (slot == 5) {
      status = PaymentStatus.pending;
    } else if (slot == 6) {
      status = PaymentStatus.failed;
    } else if ((i ~/ 8).isEven) {
      status = PaymentStatus.refunded;
      refunded = amount;
    } else {
      status = PaymentStatus.partiallyRefunded;
      refunded = amount ~/ 2;
    }
    final created = SampleData.now.subtract(Duration(days: i, hours: i % 5));
    final collected = status == PaymentStatus.succeeded ||
        status == PaymentStatus.refunded ||
        status == PaymentStatus.partiallyRefunded;
    final manual = i % 11 == 3;
    payments.add(
      PaymentRecord(
        id: 'pay_${(i + 1).toString().padLeft(3, '0')}',
        kind: kind,
        refId: switch (kind) {
          PaymentKind.donation => 'don_$i',
          PaymentKind.membershipDue => 'due_b${i % 6}',
          PaymentKind.eventFee => 'reg_$i',
        },
        amountMinor: amount,
        status: status,
        provider: 'simulation',
        simulated: true,
        idempotencyKey: 'idem_$i',
        manual: manual,
        recordedBy: manual ? 'usr_fin_1' : null,
        note: manual ? 'Havale ile alındı (örnek)' : null,
        failureCode: status == PaymentStatus.failed ? 'card_declined' : null,
        refundedMinor: refunded,
        createdAt: created,
        updatedAt: created,
        succeededAt: collected ? created : null,
      ),
    );
  }
  return payments;
}

List<RefundRecord> _refundsFor(List<PaymentRecord> payments) {
  final refunds = <RefundRecord>[];
  var n = 1;
  for (final p in payments) {
    if (p.refundedMinor > 0) {
      refunds.add(
        RefundRecord(
          id: 'ref_${n.toString().padLeft(3, '0')}',
          paymentId: p.id,
          kind: p.kind,
          amountMinor: p.refundedMinor,
          reason: 'Örnek iade talebi',
          status: RefundStatus.succeeded,
          requestedBy: 'usr_fin_1',
          createdAt: p.updatedAt.add(const Duration(hours: 5)),
        ),
      );
      n++;
    }
  }
  // Bekleyen ve başarısız iade örnekleri (ilk başarılı ödemeler üzerinde).
  final succeeded =
      payments.where((p) => p.status == PaymentStatus.succeeded).toList();
  if (succeeded.length >= 2) {
    refunds
      ..add(
        RefundRecord(
          id: 'ref_${n.toString().padLeft(3, '0')}',
          paymentId: succeeded[0].id,
          kind: succeeded[0].kind,
          amountMinor: 10000,
          reason: 'Mükerrer ödeme (bekliyor)',
          status: RefundStatus.pending,
          requestedBy: 'usr_fin_1',
          createdAt: SampleData.now.subtract(const Duration(hours: 2)),
        ),
      )
      ..add(
        RefundRecord(
          id: 'ref_${(n + 1).toString().padLeft(3, '0')}',
          paymentId: succeeded[1].id,
          kind: succeeded[1].kind,
          amountMinor: succeeded[1].amountMinor,
          reason: 'Sağlayıcı hatası (örnek)',
          status: RefundStatus.failed,
          requestedBy: 'usr_fin_1',
          createdAt: SampleData.now.subtract(const Duration(days: 1)),
        ),
      );
  }
  refunds.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return refunds;
}

List<AuditLogEntry> _auditLogs() => [
      AuditLogEntry(
        id: 'aud_1',
        actorId: 'usr_admin_1',
        actorRole: 'system_admin',
        action: 'role.assign',
        targetType: 'user',
        targetId: 'usr_3',
        before: const {'role': 'registered_user'},
        after: const {'role': 'club_member'},
        createdAt: _day(2026, 10, 28, 10, 12),
      ),
      AuditLogEntry(
        id: 'aud_2',
        actorId: 'usr_fin_1',
        actorRole: 'finance_manager',
        action: 'payment.manual_record',
        targetType: 'payment',
        targetId: 'pay_004',
        after: const {'amountMinor': 25000, 'kind': 'donation'},
        createdAt: _day(2026, 10, 26, 14, 40),
      ),
      AuditLogEntry(
        id: 'aud_3',
        actorId: 'usr_fin_1',
        actorRole: 'finance_manager',
        action: 'refund.issue',
        targetType: 'payment',
        targetId: 'pay_008',
        before: const {'refundedMinor': 0},
        after: const {'refundedMinor': 25000},
        createdAt: _day(2026, 10, 25, 11, 5),
      ),
      AuditLogEntry(
        id: 'aud_4',
        actorId: 'usr_fin_1',
        actorRole: 'finance_manager',
        action: 'export.financial',
        targetType: 'report',
        targetId: 'payments',
        after: const {'rows': 24},
        createdAt: _day(2026, 10, 24, 9, 30),
      ),
      AuditLogEntry(
        id: 'aud_5',
        actorId: 'usr_admin_1',
        actorRole: 'system_admin',
        action: 'club_member.approve',
        targetType: 'club_member',
        targetId: 'mem_6',
        before: const {'status': 'pending'},
        after: const {'status': 'active'},
        createdAt: _day(2026, 10, 20, 16, 2),
      ),
      AuditLogEntry(
        id: 'aud_6',
        actorId: 'usr_fin_1',
        actorRole: 'finance_manager',
        action: 'due.create',
        targetType: 'due_period',
        targetId: 'per_2026',
        after: const {'periodLabel': '2026-2027', 'count': 6},
        createdAt: _day(2026, 9, 1, 9, 15),
      ),
    ];

/// Ödemelerden aylık/tür bazlı özet üretir (report_aggregates'in örnek karşılığı).
///
/// Yalnızca tahsil edilmiş ödemeler (başarılı, kısmen/tam iade edilmiş) girer.
/// `collectedMinor` brüt, `refundedMinor` iade edilen toplamdır.
List<ReportAggregate> buildAggregates(List<PaymentRecord> payments) {
  final byKey = <String, ReportAggregate>{};
  for (final p in payments) {
    final collected = p.status == PaymentStatus.succeeded ||
        p.status == PaymentStatus.partiallyRefunded ||
        p.status == PaymentStatus.refunded;
    if (!collected) continue;
    final period = periodOf(p.succeededAt ?? p.createdAt);
    final key = '$period|${p.kind.wireName}|${p.currency}';
    final old = byKey[key];
    byKey[key] = ReportAggregate(
      period: period,
      kind: p.kind,
      currency: p.currency,
      collectedMinor: (old?.collectedMinor ?? 0) + p.amountMinor,
      refundedMinor: (old?.refundedMinor ?? 0) + p.refundedMinor,
      count: (old?.count ?? 0) + 1,
    );
  }
  final list = byKey.values.toList()
    ..sort((a, b) {
      final byPeriod = b.period.compareTo(a.period);
      return byPeriod != 0
          ? byPeriod
          : a.kind.wireName.compareTo(b.kind.wireName);
    });
  return list;
}
