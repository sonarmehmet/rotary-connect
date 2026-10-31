import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rotary_shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'repository.dart';

/// Gerçek (Firebase) veri katmanı. İlkeler:
/// - Okumalar Firestore'dan, kurallara uyan sorgularla (ör. `status == published`) yapılır.
/// - Para ve kontenjan işlemleri YALNIZCA Cloud Functions callable'larıyla yapılır; istemci
///   finansal koleksiyonlara yazmaz (kurallar zaten engeller).
/// DOĞRULANMAMIŞ: emülatörde/gerçek projede çalıştırılmadı.
class FirebaseAppRepository implements AppRepository {
  FirebaseAppRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _fn = functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Oturum açık değil');
    return u.uid;
  }

  Future<Map<String, Object?>> _call(String name, Map<String, Object?> data) async {
    final res = await _fn.httpsCallable(name).call<Object?>(data);
    final d = res.data;
    return d is Map ? Map<String, Object?>.from(d) : <String, Object?>{};
  }

  static String _key(String kind) => '${kind}_${DateTime.now().microsecondsSinceEpoch}';
  static DateTime _date(Object? v, [DateTime? fallback]) =>
      v is Timestamp ? v.toDate() : (fallback ?? DateTime.now());

  // ------------------------------------------------------------------ içerik

  @override
  Future<List<Campaign>> campaigns() async {
    final s = await _db.collection('donation_campaigns').where('status', whereIn: ['active', 'completed']).get();
    return [
      for (final d in s.docs)
        Campaign(
          id: d.id,
          title: (d['title'] as String?) ?? '',
          description: (d['description'] as String?) ?? '',
          goal: Money((d['goalMinor'] as num?)?.toInt() ?? 0),
          verifiedTotal: Money((d.data()['verifiedTotalMinor'] as num?)?.toInt() ?? 0),
          active: d['status'] == 'active',
        ),
    ];
  }

  @override
  Future<List<EventItem>> events() async {
    final s = await _db.collection('events').where('status', isEqualTo: 'published').get();
    final mine = _auth.currentUser == null ? <String, RegistrationStatus>{} : await _myRegistrationStatuses();
    final list = [
      for (final d in s.docs)
        EventItem(
          id: d.id,
          title: (d['title'] as String?) ?? '',
          description: (d['description'] as String?) ?? '',
          startsAt: _date(d.data()['startsAt']),
          location: (d['location'] as String?) ?? '',
          fee: Money((d.data()['feeMinor'] as num?)?.toInt() ?? 0),
          capacity: (d['capacity'] as num?)?.toInt() ?? 0,
          // Dolu sayılan yer = onaylı + ayrılmış (bekleyen ödeme yer tutar).
          confirmedCount: ((d.data()['confirmedCount'] as num?)?.toInt() ?? 0) +
              ((d.data()['reservedCount'] as num?)?.toInt() ?? 0),
          myStatus: mine[d.id] ?? RegistrationStatus.none,
        ),
    ];
    list.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return list;
  }

  @override
  Future<List<Project>> projects() async {
    final s = await _db.collection('projects').where('status', whereIn: ['ongoing', 'completed']).get();
    return [
      for (final d in s.docs)
        Project(
          id: d.id,
          title: (d['title'] as String?) ?? '',
          summary: (d['description'] as String?) ?? '',
          status: d['status'] == 'completed' ? 'Tamamlandı' : 'Devam ediyor',
        ),
    ];
  }

  @override
  Future<List<NewsItem>> news() async {
    final s = await _db.collection('news').where('published', isEqualTo: true).get();
    final list = [
      for (final d in s.docs)
        NewsItem(
          id: d.id,
          title: (d['title'] as String?) ?? '',
          body: (d['body'] as String?) ?? '',
          publishedAt: _date(d.data()['publishedAt']),
        ),
    ];
    list.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return list;
  }

  @override
  Future<List<DueItem>> myDues() async {
    final s = await _db.collection('membership_dues').where('userId', isEqualTo: _uid).get();
    final list = [
      for (final d in s.docs)
        DueItem(
          id: d.id,
          period: (d.data()['periodLabel'] as String?) ?? 'Aidat',
          amount: Money((d['amountMinor'] as num?)?.toInt() ?? 0),
          paid: Money((d.data()['paidMinor'] as num?)?.toInt() ?? 0),
          dueDate: _date(d.data()['dueDate']),
        ),
    ];
    list.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return list;
  }

  // ------------------------------------------------------------------ oturum

  Future<UserProfile> _profileOf(User u) async {
    final token = await u.getIdTokenResult(true);
    final claim = token.claims?['role'];
    // Claim yoksa oturum açmış kullanıcı `registered_user` sayılır (sunucu ve kurallarla aynı varsayılan).
    final role = claim is String ? AppRole.fromWire(claim) : AppRole.registeredUser;
    return UserProfile(name: u.displayName ?? (u.email ?? ''), email: u.email ?? '', role: role);
  }

  @override
  Future<UserProfile?> currentUser() async {
    final u = _auth.currentUser;
    return u == null ? null : _profileOf(u);
  }

  @override
  Future<UserProfile?> signIn(String email, String password) async {
    try {
      final c = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return await _profileOf(c.user!);
    } on FirebaseAuthException {
      return null; // hesap var/yok bilgisi sızdırılmaz
    }
  }

  @override
  Future<UserProfile> register(String name, String email, String password) async {
    final c = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final u = c.user!;
    await u.updateDisplayName(name);
    await _db.collection('users').doc(u.uid).set({
      'displayName': name,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'notificationPrefs': {'events': true, 'dues': true, 'donations': true, 'announcements': true},
    });
    await u.reload();
    return _profileOf(_auth.currentUser!);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  // ------------------------------------------------------------------ bağış ve ödeme

  @override
  Future<DonationResult> donate(DonationRequest r) async {
    final out = await _call('startDonation', {
      if (r.campaignId != null) 'campaignId': r.campaignId,
      'amountMinor': r.amount.minor,
      'donor': {'name': r.donorName, 'email': r.donorEmail, 'anonymous': r.anonymous},
      'clientKey': r.clientKey,
    });
    return DonationResult(
      paymentId: (out['paymentId'] as String?) ?? '',
      simulated: out['simulated'] == true,
      succeeded: out['status'] == 'succeeded',
      checkoutUrl: out['checkoutUrl'] as String?,
    );
  }

  @override
  Future<String?> payDue(String dueId) async {
    final out = await _call('startDuePayment', {'dueId': dueId, 'clientKey': _key('due')});
    return out['checkoutUrl'] as String?;
  }

  // ------------------------------------------------------------------ etkinlik kaydı

  /// Kullanıcının etkinlik başına EN GÜNCEL etkin kaydı (reserved/confirmed/waitlisted).
  Future<Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>> _myActiveRegistrations() async {
    final s = await _db.collection('event_registrations').where('userId', isEqualTo: _uid).get();
    final out = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in s.docs) {
      if (const {'reserved', 'confirmed', 'waitlisted'}.contains(d.data()['status'])) {
        out[d.data()['eventId'] as String] = d;
      }
    }
    return out;
  }

  Future<Map<String, RegistrationStatus>> _myRegistrationStatuses() async {
    final regs = await _myActiveRegistrations();
    return {
      for (final e in regs.entries)
        e.key: switch (e.value.data()['status']) {
          'reserved' => RegistrationStatus.reserved,
          'confirmed' => RegistrationStatus.confirmed,
          'waitlisted' => RegistrationStatus.waitlisted,
          _ => RegistrationStatus.none,
        },
    };
  }

  Future<EventItem> _eventById(String id) async => (await events()).firstWhere((e) => e.id == id);

  @override
  Future<EventItem> registerForEvent(String eventId) async {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Oturum açık değil');
    await _call('reserveEventSpot', {
      'eventId': eventId,
      'participant': {'name': u.displayName ?? (u.email ?? ''), 'email': u.email ?? ''},
    });
    return _eventById(eventId);
  }

  @override
  Future<EventItem> cancelEventRegistration(String eventId) async {
    final reg = (await _myActiveRegistrations())[eventId];
    if (reg == null) throw StateError('Etkin kayıt yok');
    await _call('cancelRegistration', {'registrationId': reg.id});
    return _eventById(eventId);
  }

  @override
  Future<EventItem> payEventFee(String eventId) async {
    final reg = (await _myActiveRegistrations())[eventId];
    if (reg == null || reg.data()['status'] != 'reserved') {
      throw StateError('Ödenecek bir rezervasyon yok');
    }
    final out = await _call('startEventFeePayment', {'registrationId': reg.id, 'clientKey': _key('fee')});
    final url = out['checkoutUrl'] as String?;
    if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return _eventById(eventId);
  }

  // ------------------------------------------------------------------ bildirim ve KVKK

  @override
  Future<List<AppNotification>> notifications() async {
    final s = await _db.collection('notifications').where('userId', isEqualTo: _uid).limit(50).get();
    final list = [
      for (final d in s.docs)
        AppNotification(
          id: d.id,
          title: (d['title'] as String?) ?? '',
          body: (d['body'] as String?) ?? '',
          route: ((d.data()['data'] as Map?)?['route'] as String?) ?? '/',
          createdAt: _date(d.data()['createdAt']),
          read: d.data()['read'] == true,
        ),
    ];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> markNotificationRead(String id) =>
      _db.collection('notifications').doc(id).update({'read': true}); // kurallar yalnızca `read` alanına izin verir

  @override
  Future<NotificationPrefs> notificationPrefs() async {
    final p = (await _db.collection('users').doc(_uid).get()).data()?['notificationPrefs'];
    bool b(String k) => p is Map ? p[k] != false : true;
    return NotificationPrefs(events: b('events'), dues: b('dues'), donations: b('donations'), announcements: b('announcements'));
  }

  @override
  Future<void> saveNotificationPrefs(NotificationPrefs p) => _db.collection('users').doc(_uid).update({
        'notificationPrefs': {'events': p.events, 'dues': p.dues, 'donations': p.donations, 'announcements': p.announcements},
      });

  @override
  Future<List<String>> requestAccountDeletion() async {
    final out = await _call('requestAccountDeletion', {});
    final b = out['blockers'];
    return b is List ? [for (final x in b) x.toString()] : const [];
  }
}
