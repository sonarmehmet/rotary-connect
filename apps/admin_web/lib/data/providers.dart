import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_repository.dart';
import 'fake_admin_repository.dart';
import 'donation_record.dart';
import 'models.dart';

/// Depo sağlayıcısı. Dalga 2'de gerçek (Firestore + Functions) uygulamayla
/// değiştirilir; ekranlar yalnızca [AdminRepository] arayüzünü bilir.
final adminRepositoryProvider =
    Provider<AdminRepository>((ref) => FakeAdminRepository());

// Liste sağlayıcıları. Yazma sonrası `ref.invalidate(...)` ile yenilenir.

final campaignsProvider = FutureProvider.autoDispose<List<Campaign>>(
  (ref) => ref.watch(adminRepositoryProvider).listCampaigns(),
);

final eventsProvider = FutureProvider.autoDispose<List<ClubEvent>>(
  (ref) => ref.watch(adminRepositoryProvider).listEvents(),
);

final projectsProvider = FutureProvider.autoDispose<List<Project>>(
  (ref) => ref.watch(adminRepositoryProvider).listProjects(),
);

final newsProvider = FutureProvider.autoDispose<List<NewsItem>>(
  (ref) => ref.watch(adminRepositoryProvider).listNews(),
);

final duesProvider = FutureProvider.autoDispose<List<MembershipDue>>(
  (ref) => ref.watch(adminRepositoryProvider).listDues(),
);

final membersProvider = FutureProvider.autoDispose<List<MemberOption>>(
  (ref) => ref.watch(adminRepositoryProvider).listActiveMembers(),
);

final donationsProvider = FutureProvider.autoDispose<List<DonationRecord>>(
  (ref) => ref.watch(adminRepositoryProvider).listDonations(),
);

final paymentsProvider = FutureProvider.autoDispose<List<PaymentRecord>>(
  (ref) => ref.watch(adminRepositoryProvider).listPayments(),
);

final refundsProvider = FutureProvider.autoDispose<List<RefundRecord>>(
  (ref) => ref.watch(adminRepositoryProvider).listRefunds(),
);

final clubMembersProvider = FutureProvider.autoDispose<List<ClubMember>>(
  (ref) => ref.watch(adminRepositoryProvider).listClubMembers(),
);

final usersProvider = FutureProvider.autoDispose<List<AppUserRow>>(
  (ref) => ref.watch(adminRepositoryProvider).listUsers(),
);

final registrationsProvider =
    FutureProvider.autoDispose<List<EventRegistration>>(
  (ref) => ref.watch(adminRepositoryProvider).listRegistrations(),
);

final settingsProvider = FutureProvider.autoDispose<AppSettings>(
  (ref) => ref.watch(adminRepositoryProvider).getSettings(),
);

final auditLogsProvider = FutureProvider.autoDispose<List<AuditLogEntry>>(
  (ref) => ref.watch(adminRepositoryProvider).listAuditLogs(),
);

final aggregatesProvider = FutureProvider.autoDispose<List<ReportAggregate>>(
  (ref) => ref.watch(adminRepositoryProvider).listAggregates(),
);

/// Finans yazmalarından sonra (ödeme, iade, borç) ilgili tüm listeleri yeniler.
void invalidateFinance(WidgetRef ref) {
  ref
    ..invalidate(duesProvider)
    ..invalidate(paymentsProvider)
    ..invalidate(donationsProvider)
    ..invalidate(refundsProvider)
    ..invalidate(auditLogsProvider)
    ..invalidate(aggregatesProvider);
}
