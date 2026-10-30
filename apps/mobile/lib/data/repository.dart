import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import 'models.dart';

/// Uygulamanın veri sınırı. Aşama 4'te Firebase uygulaması bu arayüzü gerçekler;
/// ekranlar yalnızca bu arayüzü bilir. Para işlemleri sunucu tarafında yapılır.
abstract class AppRepository {
  Future<List<Campaign>> campaigns();
  Future<List<EventItem>> events();
  Future<List<Project>> projects();
  Future<List<NewsItem>> news();
  Future<List<DueItem>> myDues();
  Future<UserProfile?> signIn(String email, String password);
  Future<UserProfile> register(String name, String email, String password);
  Future<void> signOut();
  Future<DonationResult> donate(DonationRequest r);

  /// Yer ayırır; ücretli etkinlikte ödeme ayrı adımdır. Doluysa bekleme listesine alır.
  Future<EventItem> registerForEvent(String eventId);
  Future<EventItem> cancelEventRegistration(String eventId);

  /// Ayrılmış yer için etkinlik ücretini öder (sunucu tutarı kayıttan çözer). Simülasyonda anında onaylanır.
  Future<EventItem> payEventFee(String eventId);

  Future<List<AppNotification>> notifications();
  Future<void> markNotificationRead(String id);
  Future<NotificationPrefs> notificationPrefs();
  Future<void> saveNotificationPrefs(NotificationPrefs prefs);
}

/// Örnek veriyle çalışan bellek içi uygulama (Aşama 3). Veriler TEST VERİSİDİR.
class FakeAppRepository implements AppRepository {
  FakeAppRepository({DateTime? now}) : _now = now ?? DateTime(2026, 10, 30);
  final DateTime _now;
  final Map<String, RegistrationStatus> _reg = {};
  final Map<String, DonationResult> _byKey = {};
  final Set<String> _readNotes = {};
  NotificationPrefs _prefs = const NotificationPrefs();
  NotificationPrefs _prefs = const NotificationPrefs();

  @override
  Future<List<Campaign>> campaigns() async => [
        Campaign(
          id: 'c1',
          title: 'Köy Okulu Kütüphanesi',
          description: 'Kırsal bir okul için kitap ve raf desteği.',
          goal: Money.fromMajor(100000),
          verifiedTotal: Money.fromMajor(37500),
          active: true,
        ),
        Campaign(
          id: 'c2',
          title: 'Ücretsiz Sağlık Taraması',
          description: 'Mobil tarama aracı için ekipman bağışı.',
          goal: Money.fromMajor(250000),
          verifiedTotal: Money.fromMajor(250000),
          active: false,
        ),
      ];

  @override
  Future<List<EventItem>> events() async {
    final list = [
      EventItem(
        id: 'e1',
        title: 'Yıllık Hayır Yemeği',
        description: 'Kulüp üyeleri ve misafirler için gala yemeği.',
        startsAt: _now.add(const Duration(days: 20)),
        location: 'Kulüp Salonu',
        fee: Money.fromMajor(750),
        capacity: 80,
        confirmedCount: 80,
      ),
      EventItem(
        id: 'e2',
        title: 'Fidan Dikim Günü',
        description: 'Ücretsiz katılım, fidanlar kulüp tarafından sağlanır.',
        startsAt: _now.add(const Duration(days: 9)),
        location: 'Şehir Ormanı',
        fee: const Money(0),
        capacity: 50,
        confirmedCount: 12,
      ),
    ];
    return [for (final e in list) e.withStatus(_reg[e.id] ?? RegistrationStatus.none)];
  }

  @override
  Future<List<Project>> projects() async => const [
        Project(id: 'p1', title: 'Temiz Su Projesi', summary: 'Üç köyde su arıtma kurulumu.', status: 'Devam ediyor'),
        Project(id: 'p2', title: 'Burs Programı', summary: 'Başarılı öğrencilere yıllık burs.', status: 'Tamamlandı'),
      ];

  @override
  Future<List<NewsItem>> news() async => [
        NewsItem(id: 'n1', title: 'Yeni dönem başkanı belirlendi', body: 'Genel kurul sonuçları duyuruldu.', publishedAt: _now.subtract(const Duration(days: 2))),
        NewsItem(id: 'n2', title: 'Hayır yemeği kayıtları açıldı', body: 'Kontenjan sınırlıdır.', publishedAt: _now.subtract(const Duration(days: 6))),
      ];

  @override
  Future<List<DueItem>> myDues() async => [
        DueItem(id: 'd1', period: '2026 – 1. Dönem', amount: Money.fromMajor(1500), paid: Money.fromMajor(1500), dueDate: _now.subtract(const Duration(days: 60))),
        DueItem(id: 'd2', period: '2026 – 2. Dönem', amount: Money.fromMajor(1500), paid: const Money(0), dueDate: _now.subtract(const Duration(days: 5))),
      ];

  @override
  Future<UserProfile?> signIn(String email, String password) async {
    if (password.length < 8) return null;
    final role = email.startsWith('uye') ? AppRole.clubMember : AppRole.registeredUser;
    return UserProfile(name: 'Test Kullanıcı', email: email, role: role);
  }

  @override
  Future<UserProfile> register(String name, String email, String password) async =>
      UserProfile(name: name, email: email, role: AppRole.registeredUser);

  @override
  Future<void> signOut() async {}

  @override
  Future<DonationResult> donate(DonationRequest r) async {
    final prev = _byKey[r.clientKey];
    if (prev != null) return prev; // idempotent: aynı anahtar aynı ödemeyi döndürür
    final res = DonationResult(paymentId: 'sim_${_byKey.length + 1}', simulated: true, succeeded: true);
    _byKey[r.clientKey] = res;
    return res;
  }

  @override
  Future<EventItem> registerForEvent(String eventId) async {
    final e = (await events()).firstWhere((x) => x.id == eventId);
    final s = e.isFull
        ? RegistrationStatus.waitlisted
        : (e.isFree ? RegistrationStatus.confirmed : RegistrationStatus.reserved);
    _reg[eventId] = s;
    return e.withStatus(s);
  }

  @override
  Future<EventItem> cancelEventRegistration(String eventId) async {
    _reg.remove(eventId);
    return (await events()).firstWhere((x) => x.id == eventId);
  }

  @override
  Future<EventItem> payEventFee(String eventId) async {
    if (_reg[eventId] != RegistrationStatus.reserved) {
      throw StateError('Ödenecek bir rezervasyon yok');
    }
    _reg[eventId] = RegistrationStatus.confirmed;
    return (await events()).firstWhere((x) => x.id == eventId);
  }

  @override
  Future<List<AppNotification>> notifications() async => [
        AppNotification(id: 'nt1', title: 'Aidat hatırlatması', body: 'Aidat son ödeme tarihiniz yaklaşıyor.', route: '/dues', createdAt: _now.subtract(const Duration(days: 1)), read: _readNotes.contains('nt1')),
        AppNotification(id: 'nt2', title: 'Etkinlik kaydı', body: 'Kaydınız onaylandı.', route: '/events', createdAt: _now.subtract(const Duration(days: 3)), read: _readNotes.contains('nt2')),
      ];

  @override
  Future<void> markNotificationRead(String id) async => _readNotes.add(id);

  @override
  Future<NotificationPrefs> notificationPrefs() async => _prefs;

  @override
  Future<void> saveNotificationPrefs(NotificationPrefs prefs) async => _prefs = prefs;

  @override
  Future<NotificationPrefs> notificationPrefs() async => _prefs;

  @override
  Future<void> saveNotificationPrefs(NotificationPrefs prefs) async => _prefs = prefs;
}

final repositoryProvider = Provider<AppRepository>((ref) => FakeAppRepository());
