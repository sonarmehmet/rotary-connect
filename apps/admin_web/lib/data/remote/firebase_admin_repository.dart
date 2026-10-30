import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/admin_exception.dart';
import '../admin_repository.dart';
import '../donation_record.dart';
import '../models.dart';
import 'admin_callables.dart';

/// Gerçek veri: okumalar Firestore'dan (kurallar rolü zorlar), finans/üyelik
/// yazmaları Functions callable'larıyla, içerik yazmaları ("İ") Firestore'a.
/// DOĞRULANMAMIŞ: derlenmedi, emülatörde çalıştırılmadı.
///
/// Bilinen sınırlar:
/// - Listeler en fazla [_limit] belge okur (sayfalama yok).
/// - Kullanıcı adları `users` koleksiyonundan okunur; kurallar bunu yalnızca
///   sistem yöneticisine açar, diğer roller adı yerine kimliği görür.
/// - `users.role` aynası yalnızca rol/üyelik callable'ları çalıştıktan sonra dolar.
class FirebaseAdminRepository implements AdminRepository {
  FirebaseAdminRepository({
    required AdminCallables callables,
    FirebaseFirestore? firestore,
    required this.actorId,
  })  : _calls = callables,
        _db = firestore ?? FirebaseFirestore.instance;

  static const int _limit = 500;

  final AdminCallables _calls;
  final FirebaseFirestore _db;

  /// Oturumdaki kullanıcı (haber `authorId` alanı için).
  final String actorId;

  @override
  bool get isSample => false;

  // ------------------------------------------------------------ yardımcılar

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _all(
    String collection, {
    String? orderBy,
  }) async {
    Query<Map<String, dynamic>> q = _db.collection(collection);
    if (orderBy != null) q = q.orderBy(orderBy, descending: true);
    final snap = await q.limit(_limit).get();
    return snap.docs;
  }

  Future<Map<String, String>> _userNames() async {
    try {
      final docs = await _all('users');
      return {
        for (final d in docs)
          d.id: (d.data()['displayName'] as String?) ?? d.id,
      };
    } on FirebaseException {
      return const {}; // yetki yoksa kimlik gösterilir
    }
  }

  static DateTime? _ts(Object? v) =>
      v is Timestamp ? v.toDate().toUtc() : null;

  static DateTime _tsOr(Object? v, DateTime fallback) => _ts(v) ?? fallback;

  static final DateTime _epoch = DateTime.utc(1970);

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static String _str(Object? v, [String fallback = '']) =>
      v is String ? v : fallback;

  static String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

  static T _enum<T>(
    Iterable<T> values,
    Object? wire,
    String Function(T) name,
    T fallback,
  ) {
    for (final v in values) {
      if (name(v) == wire) return v;
    }
    return fallback;
  }

  static Timestamp _toTs(DateTime d) => Timestamp.fromDate(d.toUtc());

  // ------------------------------------------------------------ kampanyalar

  @override
  Future<List<Campaign>> listCampaigns() async {
    final docs = await _all('donation_campaigns', orderBy: 'createdAt');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          return Campaign(
            id: d.id,
            title: _str(m['title']),
            description: _str(m['description']),
            category: _enum(CampaignCategory.values, m['category'],
                (c) => c.wireName, CampaignCategory.general),
            goalMinor: _int(m['goalMinor']),
            currency: _str(m['currency'], 'TRY'),
            verifiedTotalMinor: _int(m['verifiedTotalMinor']),
            donorCount: _int(m['donorCount']),
            status: _enum(CampaignStatus.values, m['status'],
                (c) => c.wireName, CampaignStatus.draft),
            endsAt: _ts(m['endsAt']),
            projectId: _strOrNull(m['projectId']),
            eventId: _strOrNull(m['eventId']),
            createdAt: _tsOr(m['createdAt'], _epoch),
          );
        }(),
    ];
  }

  @override
  Future<void> saveCampaign(Campaign c) async {
    final col = _db.collection('donation_campaigns');
    // `verifiedTotalMinor` / `donorCount` istemciden ASLA güncellenmez.
    final fields = <String, Object?>{
      'title': c.title,
      'description': c.description,
      'category': c.category.wireName,
      'goalMinor': c.goalMinor,
      'currency': c.currency,
      'status': c.status.wireName,
      'endsAt': c.endsAt == null ? null : _toTs(c.endsAt!),
      'projectId': c.projectId,
      'eventId': c.eventId,
    };
    if (c.id.isEmpty) {
      await col.add({
        ...fields,
        'verifiedTotalMinor': 0,
        'donorCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await col.doc(c.id).update(fields);
    }
  }

  // ------------------------------------------------------------ etkinlikler

  @override
  Future<List<ClubEvent>> listEvents() async {
    final docs = await _all('events', orderBy: 'startsAt');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          final org = m['organizer'];
          final orgMap = org is Map ? org : const {};
          return ClubEvent(
            id: d.id,
            title: _str(m['title']),
            description: _str(m['description']),
            program: _strOrNull(m['program']),
            location: _str(m['location']),
            startsAt: _tsOr(m['startsAt'], _epoch),
            endsAt: _ts(m['endsAt']),
            registrationDeadline: _tsOr(m['registrationDeadline'], _epoch),
            feeMinor: _int(m['feeMinor']),
            currency: _str(m['currency'], 'TRY'),
            capacity: _int(m['capacity']),
            reservedCount: _int(m['reservedCount']),
            confirmedCount: _int(m['confirmedCount']),
            waitlistEnabled: m['waitlistEnabled'] == true,
            status: _enum(EventStatus.values, m['status'], (e) => e.wireName,
                EventStatus.draft),
            donationCampaignId: _strOrNull(m['donationCampaignId']),
            refundPolicy: _str(m['refundPolicy']),
            organizerName: _str(orgMap['name']),
            organizerContact: _str(orgMap['contact']),
            createdAt: _tsOr(m['createdAt'], _epoch),
          );
        }(),
    ];
  }

  @override
  Future<void> saveEvent(ClubEvent e) async {
    final col = _db.collection('events');
    // Sayaçlar (`reservedCount`, `confirmedCount`) yalnızca Functions'ındır.
    final fields = <String, Object?>{
      'title': e.title,
      'description': e.description,
      'program': e.program,
      'location': e.location,
      'startsAt': _toTs(e.startsAt),
      'endsAt': e.endsAt == null ? null : _toTs(e.endsAt!),
      'registrationDeadline': _toTs(e.registrationDeadline),
      'feeMinor': e.feeMinor,
      'currency': e.currency,
      'capacity': e.capacity,
      'waitlistEnabled': e.waitlistEnabled,
      'status': e.status.wireName,
      'donationCampaignId': e.donationCampaignId,
      'refundPolicy': e.refundPolicy,
      'organizer': {'name': e.organizerName, 'contact': e.organizerContact},
    };
    if (e.id.isEmpty) {
      await col.add({
        ...fields,
        'reservedCount': 0,
        'confirmedCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await col.doc(e.id).update(fields);
    }
  }

  // ------------------------------------------------------------ projeler

  @override
  Future<List<Project>> listProjects() async {
    final docs = await _all('projects', orderBy: 'startDate');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          return Project(
            id: d.id,
            title: _str(m['title']),
            description: _str(m['description']),
            leadName: _str(m['leadName']),
            status: _enum(ProjectStatus.values, m['status'],
                (p) => p.wireName, ProjectStatus.draft),
            startDate: _tsOr(m['startDate'], _epoch),
            endDate: _ts(m['endDate']),
            goals: _str(m['goals']),
            verifiedResults: _strOrNull(m['verifiedResults']),
            campaignId: _strOrNull(m['campaignId']),
          );
        }(),
    ];
  }

  @override
  Future<void> saveProject(Project p) async {
    final col = _db.collection('projects');
    final fields = <String, Object?>{
      'title': p.title,
      'description': p.description,
      'leadName': p.leadName,
      'status': p.status.wireName,
      'startDate': _toTs(p.startDate),
      'endDate': p.endDate == null ? null : _toTs(p.endDate!),
      'goals': p.goals,
      'verifiedResults': p.verifiedResults,
      'campaignId': p.campaignId,
    };
    if (p.id.isEmpty) {
      await col.add({...fields, 'imagePaths': <String>[]});
    } else {
      await col.doc(p.id).update(fields);
    }
  }

  // ------------------------------------------------------------ haberler

  static String _newsCollection(NewsKind k) =>
      k == NewsKind.news ? 'news' : 'announcements';

  @override
  Future<List<NewsItem>> listNews() async {
    final out = <NewsItem>[];
    for (final kind in NewsKind.values) {
      final docs = await _all(_newsCollection(kind));
      for (final d in docs) {
        final m = d.data();
        out.add(NewsItem(
          id: d.id,
          kind: kind,
          title: _str(m['title']),
          body: _str(m['body']),
          category: _str(m['category']),
          published: m['published'] == true,
          publishedAt: _ts(m['publishedAt']),
          authorId: _str(m['authorId']),
          pinned: m['pinned'] == true,
        ));
      }
    }
    out.sort((a, b) => (b.publishedAt ?? _epoch).compareTo(a.publishedAt ?? _epoch));
    return out;
  }

  @override
  Future<void> saveNews(NewsItem n) async {
    final col = _db.collection(_newsCollection(n.kind));
    final fields = <String, Object?>{
      'title': n.title,
      'body': n.body,
      'category': n.category,
      'published': n.published,
      'publishedAt': n.published
          ? (n.publishedAt == null
              ? FieldValue.serverTimestamp()
              : _toTs(n.publishedAt!))
          : null,
      'pinned': n.pinned,
    };
    if (n.id.isEmpty) {
      await col.add({...fields, 'authorId': actorId});
    } else {
      await col.doc(n.id).update(fields);
    }
  }

  // ------------------------------------------------------------ aidat

  @override
  Future<List<MembershipDue>> listDues() async {
    final names = await _userNames();
    final docs = await _all('membership_dues', orderBy: 'dueDate');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          final uid = _str(m['userId']);
          return MembershipDue(
            id: d.id,
            userId: uid,
            userName: names[uid] ?? uid,
            memberId: _str(m['memberId']),
            periodId: _str(m['periodId']),
            periodLabel: _str(m['periodLabel']),
            amountMinor: _int(m['amountMinor']),
            currency: _str(m['currency'], 'TRY'),
            paidMinor: _int(m['paidMinor']),
            dueDate: _tsOr(m['dueDate'], _epoch),
            status: _enum(DueStatus.values, m['status'], (s) => s.wireName,
                DueStatus.unpaid),
            allowPartial: m['allowPartial'] == true,
            createdAt: _tsOr(m['createdAt'], _epoch),
          );
        }(),
    ];
  }

  @override
  Future<List<MemberOption>> listActiveMembers() async {
    final names = await _userNames();
    final snap = await _db
        .collection('club_members')
        .where('status', isEqualTo: 'active')
        .limit(_limit)
        .get();
    return [
      for (final d in snap.docs)
        MemberOption(
          id: d.id,
          userId: _str(d.data()['userId']),
          name: names[_str(d.data()['userId'])] ?? _str(d.data()['userId']),
          memberNo: _str(d.data()['memberNo']),
        ),
    ];
  }

  @override
  Future<void> createDues(NewDuesRequest r) async {
    // Sunucu tek üye atamayı desteklemez: `memberId` verilirse yalnızca yetkili
    // olmayan bir işlem olurdu; sözleşme toplu atamadır.
    if (r.memberId != null) {
      throw const AdminException(
        'invalid-argument',
        'Tek üyeye borç atama sunucuda henüz yok; tüm aktif üyelere atayın.',
      );
    }
    await _calls.assignDues(r);
  }

  @override
  Future<void> cancelDue(String dueId, String reason) =>
      _calls.cancelDue(dueId, reason);

  // ------------------------------------------------------------ ödemeler

  @override
  Future<List<PaymentRecord>> listPayments() async {
    final docs = await _all('payments', orderBy: 'createdAt');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          return PaymentRecord(
            id: d.id,
            kind: _enum(PaymentKind.values, m['kind'], (k) => k.wireName,
                PaymentKind.donation),
            refId: _str(m['refId']),
            userId: _strOrNull(m['userId']),
            amountMinor: _int(m['amountMinor']),
            currency: _str(m['currency'], 'TRY'),
            status: PaymentStatus.tryParse(m['status'] as String?) ??
                PaymentStatus.pending,
            provider: _str(m['provider']),
            providerRef: _strOrNull(m['providerRef']),
            simulated: m['simulated'] == true,
            idempotencyKey: _str(m['idempotencyKey']),
            manual: m['manual'] == true,
            recordedBy: _strOrNull(m['recordedBy']),
            note: _strOrNull(m['note']),
            failureCode: _strOrNull(m['failureCode']),
            refundedMinor: _int(m['refundedMinor']),
            createdAt: _tsOr(m['createdAt'], _epoch),
            updatedAt: _tsOr(m['updatedAt'], _epoch),
            succeededAt: _ts(m['succeededAt']),
          );
        }(),
    ];
  }

  @override
  Future<List<DonationRecord>> listDonations() async {
    final payments = {for (final p in await listPayments()) p.id: p};
    final docs = await _all('donations', orderBy: 'createdAt');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          final donor = m['donor'];
          final donorMap = donor is Map ? donor : const {};
          final paymentId = _str(m['paymentId']);
          return DonationRecord(
            id: d.id,
            paymentId: paymentId,
            campaignId: _strOrNull(m['campaignId']),
            userId: _strOrNull(m['userId']),
            donorName: _str(donorMap['name']),
            donorEmail: _strOrNull(donorMap['email']),
            anonymous: donorMap['anonymous'] == true,
            amountMinor: _int(m['amountMinor']),
            currency: _str(m['currency'], 'TRY'),
            status: PaymentStatus.tryParse(m['status'] as String?) ??
                PaymentStatus.pending,
            receiptNo: _strOrNull(m['receiptNo']),
            simulated: payments[paymentId]?.simulated ?? false,
            createdAt: _tsOr(m['createdAt'], _epoch),
          );
        }(),
    ];
  }

  @override
  Future<void> recordManualPayment(ManualPaymentRequest r) async {
    await _calls.recordManualPayment(r);
  }

  @override
  Future<List<RefundRecord>> listRefunds() async {
    final docs = await _all('refunds', orderBy: 'createdAt');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          return RefundRecord(
            id: d.id,
            paymentId: _str(m['paymentId']),
            kind: _enum(PaymentKind.values, m['kind'], (k) => k.wireName,
                PaymentKind.donation),
            amountMinor: _int(m['amountMinor']),
            currency: _str(m['currency'], 'TRY'),
            reason: _str(m['reason']),
            status: _enum(RefundStatus.values, m['status'], (s) => s.wireName,
                RefundStatus.pending),
            requestedBy: _str(m['requestedBy']),
            providerRef: _strOrNull(m['providerRef']),
            createdAt: _tsOr(m['createdAt'], _epoch),
          );
        }(),
    ];
  }

  @override
  Future<void> issueRefund(RefundRequest r) async {
    await _calls.issueRefund(r);
  }

  // ------------------------------------------------------------ üyelik / roller

  @override
  Future<List<ClubMember>> listClubMembers() async {
    final names = await _userNames();
    final docs = await _all('club_members', orderBy: 'requestedAt');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          final uid = _str(m['userId']);
          return ClubMember(
            id: d.id,
            userId: uid,
            userName: names[uid] ?? uid,
            status: _enum(MemberStatus.values, m['status'], (s) => s.wireName,
                MemberStatus.pending),
            memberNo: _strOrNull(m['memberNo']),
            requestedAt: _tsOr(m['requestedAt'], _epoch),
            joinedAt: _ts(m['joinedAt']),
          );
        }(),
    ];
  }

  @override
  Future<void> approveMembership(String memberId, String memberNo) =>
      _calls.approveMembership(memberId, memberNo);

  @override
  Future<void> endMembership(String memberId, MemberStatus to) =>
      _calls.endMembership(memberId, to);

  @override
  Future<List<AppUserRow>> listUsers() async {
    final docs = await _all('users');
    return [
      for (final d in docs)
        AppUserRow(
          id: d.id,
          name: _str(d.data()['displayName'], d.id),
          // Kaynak doğruluk claim'dir; belgedeki `role` sunucunun yazdığı aynadır.
          role: d.data()['role'] is String
              ? AppRole.fromWire(d.data()['role'] as String)
              : AppRole.registeredUser,
        ),
    ];
  }

  @override
  Future<void> assignRole(String userId, AppRole role) =>
      _calls.assignRole(userId, role);

  @override
  Future<List<EventRegistration>> listRegistrations() async {
    final events = {for (final e in await listEvents()) e.id: e.title};
    final docs = await _all('event_registrations', orderBy: 'createdAt');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          final p = m['participant'];
          final pMap = p is Map ? p : const {};
          final eventId = _str(m['eventId']);
          return EventRegistration(
            id: d.id,
            eventId: eventId,
            eventTitle: events[eventId] ?? eventId,
            participantName: _str(pMap['name']),
            status: _enum(RegistrationStatus.values, m['status'],
                (s) => s.wireName, RegistrationStatus.reserved),
            paymentId: _strOrNull(m['paymentId']),
            reservedUntil: _ts(m['reservedUntil']),
            waitlistPosition:
                m['waitlistPosition'] is num ? _int(m['waitlistPosition']) : null,
            createdAt: _tsOr(m['createdAt'], _epoch),
          );
        }(),
    ];
  }

  // ------------------------------------------------------------ bildirim

  @override
  Future<AnnouncementResult> sendAnnouncement(AnnouncementRequest r) =>
      _calls.sendAnnouncement(r);

  // ------------------------------------------------------------ ayarlar

  @override
  Future<AppSettings> getSettings() async {
    final snap = await _db.collection('app_settings').doc('public').get();
    final m = snap.data() ?? const <String, dynamic>{};
    final amounts = m['donationQuickAmountsMinor'];
    return AppSettings(
      clubName: _str(m['clubName']),
      contact: m['contact'] is String ? m['contact'] as String : '',
      reservationMinutes: m['reservationMinutes'] is num
          ? _int(m['reservationMinutes'])
          : 15,
      donationQuickAmountsMinor: amounts is List
          ? [for (final a in amounts) if (a is num) a.toInt()]
          : const [25000, 50000, 100000, 250000],
      partialDuesEnabled: m['partialDuesEnabled'] == true,
      recurringDonationEnabled: m['recurringDonationEnabled'] == true,
      paymentMode: _str(m['paymentMode'], 'simulation'),
    );
  }

  @override
  Future<void> saveSettings(AppSettings s) async {
    // `paymentMode` istemciden yazılmaz (sunucu belirler).
    await _db.collection('app_settings').doc('public').set({
      'clubName': s.clubName.trim(),
      'contact': s.contact.trim(),
      'reservationMinutes': s.reservationMinutes,
      'donationQuickAmountsMinor': ([...s.donationQuickAmountsMinor]..sort()),
      'partialDuesEnabled': s.partialDuesEnabled,
      'recurringDonationEnabled': s.recurringDonationEnabled,
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------ denetim / rapor

  @override
  Future<List<AuditLogEntry>> listAuditLogs() async {
    final docs = await _all('audit_logs', orderBy: 'createdAt');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          Map<String, Object?>? mapOf(Object? v) =>
              v is Map ? v.map((k, x) => MapEntry(k.toString(), x as Object?)) : null;
          return AuditLogEntry(
            id: d.id,
            actorId: _str(m['actorId']),
            actorRole: _str(m['actorRole']),
            action: _str(m['action']),
            targetType: _str(m['targetType']),
            targetId: _str(m['targetId']),
            before: mapOf(m['before']),
            after: mapOf(m['after']),
            createdAt: _tsOr(m['createdAt'], _epoch),
          );
        }(),
    ];
  }

  @override
  Future<List<ReportAggregate>> listAggregates() async {
    final docs = await _all('report_aggregates');
    return [
      for (final d in docs)
        () {
          final m = d.data();
          return ReportAggregate(
            period: _str(m['period']),
            kind: _enum(PaymentKind.values, m['kind'], (k) => k.wireName,
                PaymentKind.donation),
            collectedMinor: _int(m['collectedMinor']),
            refundedMinor: _int(m['refundedMinor']),
            count: _int(m['count']),
            currency: _str(m['currency'], 'TRY'),
          );
        }(),
    ];
  }

  @override
  Future<String> exportReport(ExportRequest r) => _calls.exportReport(r);
}
