import 'package:rotary_shared/shared.dart';

import '../core/admin_exception.dart';
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
  final Set<String> _manualKeys = {};
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
      );
    }
    if (_manualKeys.contains(request.idempotencyKey)) {
      throw const AdminException(
        'already-exists',
        'Bu manuel ödeme zaten kaydedilmiş.',
      );
    }
    if (request.kind == PaymentKind.membershipDue) {
      _applyToDue(request);
    }
    final now = _clock();
    final id = _nextId('pay');
    _payments.insert(
      0,
      PaymentRecord(
        id: id,
        kind: request.kind,
        refId: request.refId,
        amountMinor: request.amountMinor,
        status: PaymentStatus.succeeded,
        provider: 'simulation',
        simulated: true,
        idempotencyKey: request.idempotencyKey,
        manual: true,
        recordedBy: 'usr_demo',
        note: request.note,
        createdAt: now,
        updatedAt: now,
        succeededAt: now,
      ),
    );
    _manualKeys.add(request.idempotencyKey);
    _log(
      'payment.manual_record',
      'payment',
      id,
      after: {
        'amountMinor': request.amountMinor,
        'kind': request.kind.wireName,
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
