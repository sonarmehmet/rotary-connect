import 'package:rotary_shared/shared.dart';

import 'models.dart';

/// Panelin veri erişim sözleşmesi.
///
/// Dalga 1'de [FakeAdminRepository] (bellekte örnek veri), Dalga 2'de Firestore
/// + Functions uygulaması bu arayüzü doldurur; imzalar değişmez.
///
/// Yazma kuralları (docs/DATA_MODEL.md):
/// - İçerik (kampanya, etkinlik, proje, haber): istemci yazabilir ("İ"), ancak
///   sayaç/toplam alanları (`verifiedTotalMinor`, `donorCount`, `reservedCount`,
///   `confirmedCount`) gerçek uygulamada ASLA istemciden yazılmaz.
/// - Finans (aidat, ödeme, iade, rapor, denetim): yalnızca Functions çağrıları.
///
/// Hatalar `AdminException` ile (Functions hata kodlarıyla) bildirilir.
abstract class AdminRepository {
  /// `true` ise ekranlarda "ÖRNEK VERİ" uyarısı gösterilir.
  bool get isSample;

  // --- İçerik (yazma: "İ") ---
  Future<List<Campaign>> listCampaigns();

  /// Boş `id` = oluştur, dolu `id` = güncelle.
  Future<void> saveCampaign(Campaign campaign);

  Future<List<ClubEvent>> listEvents();
  Future<void> saveEvent(ClubEvent event);

  Future<List<Project>> listProjects();
  Future<void> saveProject(Project project);

  Future<List<NewsItem>> listNews();
  Future<void> saveNews(NewsItem item);

  // --- Aidat (yazma: "F") ---
  Future<List<MembershipDue>> listDues();
  Future<List<MemberOption>> listActiveMembers();

  /// `createDue` / `assignDues` callable'ı.
  Future<void> createDues(NewDuesRequest request);

  // --- Ödemeler ve iadeler (yazma: "F") ---
  Future<List<PaymentRecord>> listPayments();

  /// `recordManualPayment` callable'ı.
  Future<void> recordManualPayment(ManualPaymentRequest request);

  Future<List<RefundRecord>> listRefunds();

  /// `issueRefund` callable'ı.
  Future<void> issueRefund(RefundRequest request);

  // --- Üyelik, roller, etkinlik kayıtları ---
  Future<List<ClubMember>> listClubMembers();

  /// `approveMembership` (yalnızca sistem yöneticisi). Üye no zorunludur.
  Future<void> approveMembership(String memberId, String memberNo);

  /// `endMembership`: aktif üyeyi askıya al / istifa olarak kapat.
  Future<void> endMembership(String memberId, MemberStatus to);

  Future<List<AppUserRow>> listUsers();

  /// `assignRole` (yalnızca sistem yöneticisi; audit yazılır).
  Future<void> assignRole(String userId, AppRole role);

  Future<List<EventRegistration>> listRegistrations();

  // --- Denetim ve raporlar ---
  Future<List<AuditLogEntry>> listAuditLogs();
  Future<List<ReportAggregate>> listAggregates();

  /// `exportReport` callable'ı; CSV metni döner.
  Future<String> exportReport(ExportRequest request);
}
