import 'package:rotary_shared/shared.dart';

import '../core/admin_exception.dart';
import '../core/sensitive.dart';
import 'admin_repository.dart';
import 'models.dart';
import 'report_csv.dart';
import 'sample_data.dart';

/// Bellekte çalışan sahte depo (Dalga 1). Sunucu kurallarının önemli
/// kısımlarını (iade üst sınırı, kısmi ödeme, mükerrer işlem) taklit eder ki
/// arayüz hata yollarını gerçek sunucudan önce deneyebilsin.
///
/// GERÇEK DEĞİLDİR: kalıcı değildir, yetki denetimi yapmaz.
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({SampleData? data, DateTime Function()? clock})
      : _clock = clock ?? (() => SampleData.now) {
    final d = data ?? SampleData.standard();
    _campaigns = List.of(d.campaigns);
    _events = List.of(d.events);
    _projects = List.of(d.projects);
    _news = List.of(d.news);
    _members = List.of(d.members);
    _dues = List.of(d.dues);
    _payments = List.of(d.payments);
    _refunds = List.of(d.refunds);
    _audit = List.of(d.auditLogs);
    _clubMembers = List.of(d.clubMembers);
    _users = List.of(d.users);
    _registrations = List.of(d.registrations);
  }

  final DateTime Function() _clock;
  late final List<Campaign> _campaigns;
  late final List<ClubEvent> _events;
  late final List<Project> _projects;
  late final List<NewsItem> _news;
  late final List<MemberOption> _members;
  late final List<MembershipDue> _dues;
  late final List<PaymentRecord> _payments;
  late final List<RefundRecord> _refunds;
  late final List<AuditLogEntry> _audit;
  late final List<ClubMember> _clubMembers;
  late final List<AppUserRow> _users;
  late final List<EventRegistration> _registrations;
  final Set<String> _manualKeys = {};
  final Map<String, AnnouncementResult> _announcements = {};
  AppSettings _settings = const AppSettings(
    clubName: 'Örnek Rotary Kulübü',
    contact: 'iletisim@ornek.invalid',
    reservationMinutes: 15,
    donationQuickAmountsMinor: [25000, 50000, 100000, 250000],
    partialDuesEnabled: true,
    recurringDonationEnabled: false,
    paymentMode: 'simulation',
  );
  int _seq = 1000;

  String _nextId(String prefix) => '${prefix}_${_seq++}';

  @override
  bool get isSample => true;

  // --- İçerik ---------------------------------------------------------------

  @override
  Future<List<Campaign>> listCampaigns() async => List.of(_campaigns);

  @override
  Future<void> saveCampaign(Campaign campaign) async {
    _upsert(_campaigns, campaign, (c) => c.id, campaign.withId, 'cmp');
  }

  @override
  Future<List<ClubEvent>> listEvents() async => List.of(_events);

  @override
  Future<void> saveEvent(ClubEvent event) async {
    _upsert(_events, event, (e) => e.id, event.withId, 'evt');
  }

  @override
  Future<List<Project>> listProjects() async => List.of(_projects);

  @override
  Future<void> saveProject(Project project) async {
    _upsert(_projects, project, (p) => p.id, project.withId, 'prj');
  }

  @override
  Future<List<NewsItem>> listNews() async => List.of(_news);

  @override
  Future<void> saveNews(NewsItem item) async {
    _upsert(_news, item, (n) => n.id, item.withId, 'new');
  }

  void _upsert<T>(
    List<T> list,
    T item,
    String Function(T) idOf,
    T Function(String) withId,
    String prefix,
  ) {
    if (idOf(item).isEmpty) {
      list.insert(0, withId(_nextId(prefix)));
      return;
    }
    final index = list.indexWhere((e) => idOf(e) == idOf(item));
    if (index < 0) {
      throw const AdminException('failed-precondition', 'Kayıt bulunamadı.');
    }
    list[index] = item;
  }

  // --- Aidat ----------------------------------------------------------------

  @override
  Future<List<MembershipDue>> listDues() async => List.of(_dues);

  @override
  Future<List<MemberOption>> listActiveMembers() async => List.of(_members);

  @override
  Future<void> createDues(NewDuesRequest request) async {
    if (request.amountMinor <= 0) {
      throw const AdminException(
        'invalid-argument',
        'Aidat tutarı sıfırdan büyük olmalı.',
      );
    }
    final targets = request.memberId == null
        ? _members
        : _members.where((m) => m.id == request.memberId).toList();
    if (targets.isEmpty) {
      throw const AdminException('failed-precondition', 'Üye bulunamadı.');
    }
    final periodId = 'per_${request.periodLabel.replaceAll(' ', '_')}';
    final now = _clock();
    var created = 0;
    for (final m in targets) {
      final exists = _dues.any(
        (d) => d.memberId == m.id && d.periodLabel == request.periodLabel,
      );
      if (exists) continue;
      _dues.insert(
        0,
        MembershipDue(
          id: _nextId('due'),
          userId: m.userId,
          userName: m.name,
          memberId: m.id,
          periodId: periodId,
          periodLabel: request.periodLabel,
          amountMinor: request.amountMinor,
          paidMinor: 0,
          dueDate: request.dueDate,
          status: DueStatus.unpaid,
          allowPartial: request.allowPartial,
          createdAt: now,
        ),
      );
      created++;
    }
    if (created == 0) {
      throw const AdminException(
        'already-exists',
        'Bu dönem için borçlar zaten atanmış.',
      );
    }
    _log(
      'due.create',
      'due_period',
      periodId,
      after: {'periodLabel': request.periodLabel, 'count': created},
    );
  }

  // --- Ödemeler ve iadeler ----------------------------------------------------

  @override
  Future<List<PaymentRecord>> listPayments() async => List.of(_payments);

  @override
  Future<void> recordManualPayment(ManualPaymentRequest request) async {
    if (request.amountMinor <= 0) {
      throw const AdminException(
        'invalid-argument',
        'Tutar sıfırdan büyük olmalı.',
        'invalid_amount',
      );
    }
    final note = request.note.trim();
    if (note.length < 5) {
      throw const AdminException(
        'invalid-argument',
        'Açıklama en az 5 karakter olmalı.',
        'note_required',
      );
    }
    final now = _clock();
    if (request.receivedAt.isAfter(now)) {
      throw const AdminException(
        'invalid-argument',
        'Ödeme tarihi gelecekte olamaz.',
        'future_date',
      );
    }
    // Sunucuyla aynı mükerrer anahtar: tür + kayıt + tutar + (UTC) gün.
    final day = request.receivedAt.millisecondsSinceEpoch ~/ 86400000;
    final key = 'manual:${request.kind.wireName}:${request.refId}:'
        '${request.amountMinor}:$day';
    if (_manualKeys.contains(key)) {
      throw const AdminException(
        'already-exists',
        'Bu manuel ödeme zaten kaydedilmiş.',
        'duplicate_manual_payment',
      );
    }
    if (request.kind == PaymentKind.membershipDue) {
      _applyToDue(request);
    }
    final id = _nextId('pay');
    _payments.insert(
      0,
      PaymentRecord(
        id: id,
        kind: request.kind,
        refId: request.refId,
        userId: request.userId,
        amountMinor: request.amountMinor,
        status: PaymentStatus.succeeded,
        provider: 'manual',
        simulated: false,
        idempotencyKey: key,
        manual: true,
        recordedBy: 'usr_demo',
        note: note,
        createdAt: now,
        updatedAt: now,
        succeededAt: request.receivedAt,
      ),
    );
    _manualKeys.add(key);
    _log(
      'payment.manual_record',
      'payment',
      id,
      after: {
        'amountMinor': request.amountMinor,
        'kind': request.kind.wireName,
        'manual': true,
      },
    );
  }

  void _applyToDue(ManualPaymentRequest request) {
    final index = _dues.indexWhere((d) => d.id == request.refId);
    if (index < 0) {
      throw const AdminException(
        'failed-precondition',
        'Bağlı aidat borcu bulunamadı.',
      );
    }
    final due = _dues[index];
    final closed = due.status == DueStatus.paid ||
        due.status == DueStatus.cancelled ||
        due.status == DueStatus.refunded;
    if (closed) {
      throw const AdminException(
        'failed-precondition',
        'Bu borç artık ödeme kabul etmiyor.',
      );
    }
    final remaining = due.remainingMinor;
    if (request.amountMinor > remaining) {
      throw const AdminException(
        'failed-precondition',
        'Tutar kalan borcu aşıyor.',
      );
    }
    if (request.amountMinor < remaining && !due.allowPartial) {
      throw const AdminException(
        'failed-precondition',
        'Bu borç için kısmi ödeme kapalı.',
      );
    }
    final paid = due.paidMinor + request.amountMinor;
    _dues[index] = MembershipDue(
      id: due.id,
      userId: due.userId,
      userName: due.userName,
      memberId: due.memberId,
      periodId: due.periodId,
      periodLabel: due.periodLabel,
      amountMinor: due.amountMinor,
      currency: due.currency,
      paidMinor: paid,
      dueDate: due.dueDate,
      status: paid >= due.amountMinor ? DueStatus.paid : DueStatus.partiallyPaid,
      allowPartial: due.allowPartial,
      createdAt: due.createdAt,
    );
  }

  @override
  Future<List<RefundRecord>> listRefunds() async => List.of(_refunds);

  @override
  Future<void> issueRefund(RefundRequest request) async {
    final index = _payments.indexWhere((p) => p.id == request.paymentId);
    if (index < 0) {
      throw const AdminException('failed-precondition', 'Ödeme bulunamadı.');
    }
    final payment = _payments[index];
    if (request.amountMinor <= 0) {
      throw const AdminException(
        'invalid-argument',
        'İade tutarı sıfırdan büyük olmalı.',
      );
    }
    if (!payment.status.countsAsCollected) {
      throw const AdminException(
        'failed-precondition',
        'Yalnızca başarılı ödemeler iade edilebilir.',
      );
    }
    // Sunucu kuralı: bekleyen iadeler de kalan tutardan düşer.
    final reserved = _refunds
        .where(
          (r) =>
              r.paymentId == payment.id &&
              (r.status == RefundStatus.succeeded ||
                  r.status == RefundStatus.pending),
        )
        .fold<int>(0, (sum, r) => sum + r.amountMinor);
    if (request.amountMinor > payment.amountMinor - reserved) {
      throw const AdminException(
        'failed-precondition',
        'İade tutarı iade edilebilir kalan tutarı aşıyor.',
      );
    }
    final now = _clock();
    final refundedTotal = payment.refundedMinor + request.amountMinor;
    final next = refundedTotal >= payment.amountMinor
        ? PaymentStatus.refunded
        : PaymentStatus.partiallyRefunded;
    if (!payment.status.canTransitionTo(next)) {
      throw const AdminException(
        'failed-precondition',
        'Ödeme durumu iadeye uygun değil.',
      );
    }
    _payments[index] = PaymentRecord(
      id: payment.id,
      kind: payment.kind,
      refId: payment.refId,
      userId: payment.userId,
      amountMinor: payment.amountMinor,
      currency: payment.currency,
      status: next,
      provider: payment.provider,
      providerRef: payment.providerRef,
      simulated: payment.simulated,
      idempotencyKey: payment.idempotencyKey,
      manual: payment.manual,
      recordedBy: payment.recordedBy,
      note: payment.note,
      failureCode: payment.failureCode,
      refundedMinor: refundedTotal,
      createdAt: payment.createdAt,
      updatedAt: now,
      succeededAt: payment.succeededAt,
    );
    final id = _nextId('ref');
    _refunds.insert(
      0,
      RefundRecord(
        id: id,
        paymentId: payment.id,
        kind: payment.kind,
        amountMinor: request.amountMinor,
        currency: payment.currency,
        reason: request.reason,
        status: RefundStatus.succeeded,
        requestedBy: 'usr_demo',
        createdAt: now,
      ),
    );
    _log(
      'refund.issue',
      'payment',
      payment.id,
      before: {'refundedMinor': payment.refundedMinor},
      after: {'refundedMinor': refundedTotal},
    );
  }

  // --- Üyelik, roller, etkinlik kayıtları ------------------------------------

  @override
  Future<List<ClubMember>> listClubMembers() async => List.of(_clubMembers);

  int _memberIndex(String memberId) {
    final i = _clubMembers.indexWhere((m) => m.id == memberId);
    if (i < 0) {
      throw const AdminException('failed-precondition', 'Üye kaydı bulunamadı.');
    }
    return i;
  }

  ClubMember _copyMember(
    ClubMember m, {
    MemberStatus? status,
    String? memberNo,
    DateTime? joinedAt,
  }) =>
      ClubMember(
        id: m.id,
        userId: m.userId,
        userName: m.userName,
        status: status ?? m.status,
        requestedAt: m.requestedAt,
        memberNo: memberNo ?? m.memberNo,
        joinedAt: joinedAt ?? m.joinedAt,
      );

  /// Yönetici rolü (içerik/finans/sistem) üyelik değişiminde korunur
  /// (functions/src/members/members.ts ile aynı kural).
  bool _isStaff(AppRole r) =>
      r == AppRole.contentManager ||
      r == AppRole.financeManager ||
      r == AppRole.systemAdmin;

  void _setRole(String userId, AppRole role) {
    final i = _users.indexWhere((u) => u.id == userId);
    if (i < 0) return;
    final u = _users[i];
    _users[i] = AppUserRow(id: u.id, name: u.name, role: role);
  }

  @override
  Future<void> approveMembership(String memberId, String memberNo) async {
    final i = _memberIndex(memberId);
    final m = _clubMembers[i];
    if (m.status != MemberStatus.pending) {
      throw const AdminException(
        'failed-precondition',
        'Yalnızca bekleyen talepler onaylanabilir.',
      );
    }
    if (memberNo.trim().isEmpty) {
      throw const AdminException('invalid-argument', 'Üye numarası gerekli.');
    }
    final taken = _clubMembers.any(
      (x) => x.memberNo?.toLowerCase() == memberNo.trim().toLowerCase(),
    );
    if (taken) {
      throw const AdminException(
        'already-exists',
        'Bu üye numarası zaten kullanılıyor.',
      );
    }
    _clubMembers[i] = _copyMember(
      m,
      status: MemberStatus.active,
      memberNo: memberNo.trim(),
      joinedAt: _clock(),
    );
    final user = _users.where((u) => u.id == m.userId);
    if (user.isNotEmpty && !_isStaff(user.first.role)) {
      _setRole(m.userId, AppRole.clubMember);
    }
    _log(
      'club_member.approve',
      'club_member',
      memberId,
      before: {'status': 'pending'},
      after: {'status': 'active'},
    );
  }

  @override
  Future<void> endMembership(String memberId, MemberStatus to) async {
    if (to != MemberStatus.suspended && to != MemberStatus.resigned) {
      throw const AdminException('invalid-argument', 'Geçersiz üyelik durumu.');
    }
    final i = _memberIndex(memberId);
    final m = _clubMembers[i];
    if (m.status != MemberStatus.active) {
      throw const AdminException(
        'failed-precondition',
        'Yalnızca aktif üyelik sonlandırılabilir.',
      );
    }
    _clubMembers[i] = _copyMember(m, status: to);
    final user = _users.where((u) => u.id == m.userId);
    if (user.isNotEmpty && !_isStaff(user.first.role)) {
      _setRole(m.userId, AppRole.registeredUser);
    }
    _log(
      'club_member.end',
      'club_member',
      memberId,
      before: {'status': 'active'},
      after: {'status': to.wireName},
    );
  }

  @override
  Future<List<AppUserRow>> listUsers() async => List.of(_users);

  @override
  Future<void> assignRole(String userId, AppRole role) async {
    final i = _users.indexWhere((u) => u.id == userId);
    if (i < 0) {
      throw const AdminException('failed-precondition', 'Kullanıcı bulunamadı.');
    }
    final old = _users[i].role;
    if (old == role) {
      throw const AdminException(
        'failed-precondition',
        'Kullanıcı zaten bu role sahip.',
      );
    }
    // Son sistem yöneticisi düşürülemez (panel kilitlenmesini önler).
    if (old == AppRole.systemAdmin &&
        _users.where((u) => u.role == AppRole.systemAdmin).length == 1) {
      throw const AdminException(
        'failed-precondition',
        'Son sistem yöneticisinin rolü değiştirilemez.',
      );
    }
    _setRole(userId, role);
    _log(
      'role.assign',
      'user',
      userId,
      before: {'role': old.wireName},
      after: {'role': role.wireName},
    );
  }

  @override
  Future<List<EventRegistration>> listRegistrations() async =>
      List.of(_registrations);

  // --- Bildirim ---------------------------------------------------------------

  static final RegExp _clientKey = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  @override
  Future<AnnouncementResult> sendAnnouncement(AnnouncementRequest r) async {
    final title = r.title.trim();
    final body = r.body.trim();
    if (title.isEmpty || title.length > 80) {
      throw const AdminException(
        'invalid-argument',
        'Başlık 1-80 karakter olmalı.',
        'invalid_title',
      );
    }
    if (body.isEmpty || body.length > 300) {
      throw const AdminException(
        'invalid-argument',
        'Metin 1-300 karakter olmalı.',
        'invalid_body',
      );
    }
    if (!_clientKey.hasMatch(r.clientKey)) {
      throw const AdminException(
        'invalid-argument',
        'İşlem anahtarı geçersiz.',
        'invalid_clientKey',
      );
    }
    if (containsSensitive(title) || containsSensitive(body)) {
      throw const AdminException(
        'invalid-argument',
        null,
        'sensitive_content',
      );
    }
    if (r.audience == AnnouncementAudience.role &&
        (r.role == null || r.role == AppRole.visitor)) {
      throw const AdminException(
        'invalid-argument',
        'Hedef rol geçersiz.',
        'invalid_audience',
      );
    }
    // Aynı anahtar: bildirimler zaten var, çift üretilmez (yalnızca ilk sonuç döner).
    final previous = _announcements[r.clientKey];
    if (previous != null) return previous;

    final count = _users.where((u) {
      switch (r.audience) {
        case AnnouncementAudience.all:
          return true;
        case AnnouncementAudience.members:
          return u.role == AppRole.clubMember;
        case AnnouncementAudience.role:
          return u.role == r.role;
      }
    }).length;
    final result = AnnouncementResult(
      recipients: count,
      sent: count,
      skippedByPreferences: 0,
    );
    _announcements[r.clientKey] = result;
    _log(
      'announcement.send',
      'announcement',
      r.clientKey,
      after: {
        'audience': r.audience == AnnouncementAudience.role
            ? 'role:${r.role!.wireName}'
            : r.audience.wireName,
        'route': r.route.path,
        'recipients': count,
        'sent': count,
      },
    );
    return result;
  }

  // --- Ayarlar ---------------------------------------------------------------

  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    if (settings.clubName.trim().isEmpty) {
      throw const AdminException('invalid-argument', 'Kulüp adı boş olamaz.');
    }
    if (settings.reservationMinutes < 5 || settings.reservationMinutes > 120) {
      throw const AdminException(
        'invalid-argument',
        'Rezervasyon süresi 5 ile 120 dakika arasında olmalı.',
      );
    }
    final amounts = settings.donationQuickAmountsMinor;
    final valid = amounts.isNotEmpty &&
        amounts.length <= 6 &&
        amounts.every((a) => a >= 100) &&
        amounts.toSet().length == amounts.length;
    if (!valid) {
      throw const AdminException(
        'invalid-argument',
        'Hızlı bağış tutarları: 1-6 adet, her biri en az 1 ₺, tekrarsız.',
      );
    }
    final sorted = [...amounts]..sort();
    // paymentMode sunucuda belirlenir; istemci değeri yok sayılır.
    _settings = AppSettings(
      clubName: settings.clubName.trim(),
      contact: settings.contact.trim(),
      reservationMinutes: settings.reservationMinutes,
      donationQuickAmountsMinor: sorted,
      partialDuesEnabled: settings.partialDuesEnabled,
      recurringDonationEnabled: settings.recurringDonationEnabled,
      paymentMode: _settings.paymentMode,
    );
    _log('settings.update', 'app_settings', 'public');
  }

  // --- Denetim ve raporlar ------------------------------------------------------

  @override
  Future<List<AuditLogEntry>> listAuditLogs() async => List.of(_audit);

  @override
  Future<List<ReportAggregate>> listAggregates() async =>
      buildAggregates(_payments);

  @override
  Future<String> exportReport(ExportRequest request) async {
    final range = request.range;
    bool inRange(DateTime at) => range == null || range.contains(at);
    final String csv;
    final int rows;
    switch (request.kind) {
      case ExportKind.payments:
        final payList = _payments.where((p) => inRange(p.createdAt)).toList();
        csv = paymentsCsv(payList);
        rows = payList.length;
      case ExportKind.dues:
        final dueList = _dues.where((d) => inRange(d.dueDate)).toList();
        csv = duesCsv(dueList);
        rows = dueList.length;
      case ExportKind.refunds:
        final refundList =
            _refunds.where((r) => inRange(r.createdAt)).toList();
        csv = refundsCsv(refundList);
        rows = refundList.length;
    }
    _log(
      'export.financial',
      'report',
      request.kind.wireName,
      after: {'rows': rows},
    );
    return csv;
  }

  void _log(
    String action,
    String targetType,
    String targetId, {
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) {
    _audit.insert(
      0,
      AuditLogEntry(
        id: _nextId('aud'),
        actorId: 'usr_demo',
        actorRole: 'demo',
        action: action,
        targetType: targetType,
        targetId: targetId,
        before: before,
        after: after,
        createdAt: _clock(),
      ),
    );
  }
}
