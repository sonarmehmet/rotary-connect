import 'package:rotary_shared/shared.dart';

/// Arayüz modelleri. Para her yerde küçük birim (kuruş) tamsayısıdır; double yok.
class Campaign {
  const Campaign({
    required this.id,
    required this.title,
    required this.description,
    required this.goal,
    required this.verifiedTotal,
    required this.active,
  });
  final String id;
  final String title;
  final String description;
  final Money goal;
  final Money verifiedTotal;
  final bool active;

  /// 0..1 arası; hedef 0 ise 0.
  double get progress => goal.minor <= 0 ? 0 : (verifiedTotal.minor / goal.minor).clamp(0, 1).toDouble();
}

enum RegistrationStatus { none, reserved, confirmed, waitlisted, cancelled }

class EventItem {
  const EventItem({
    required this.id,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.location,
    required this.fee,
    required this.capacity,
    required this.confirmedCount,
    this.myStatus = RegistrationStatus.none,
  });
  final String id;
  final String title;
  final String description;
  final DateTime startsAt;
  final String location;
  final Money fee;
  final int capacity;
  final int confirmedCount;
  final RegistrationStatus myStatus;

  bool get isFull => capacity > 0 && confirmedCount >= capacity;
  bool get isFree => fee.minor == 0;
  int get remaining => capacity <= 0 ? 0 : (capacity - confirmedCount).clamp(0, capacity);

  EventItem withStatus(RegistrationStatus s) => EventItem(
        id: id,
        title: title,
        description: description,
        startsAt: startsAt,
        location: location,
        fee: fee,
        capacity: capacity,
        confirmedCount: confirmedCount,
        myStatus: s,
      );
}

class Project {
  const Project({required this.id, required this.title, required this.summary, required this.status});
  final String id;
  final String title;
  final String summary;
  final String status;
}

class NewsItem {
  const NewsItem({required this.id, required this.title, required this.body, required this.publishedAt});
  final String id;
  final String title;
  final String body;
  final DateTime publishedAt;
}

class DueItem {
  const DueItem({required this.id, required this.period, required this.amount, required this.paid, required this.dueDate});
  final String id;
  final String period;
  final Money amount;
  final Money paid;
  final DateTime dueDate;

  Money get remaining => amount - paid;
  bool get isPaid => remaining.minor <= 0;
  bool isOverdue(DateTime now) => !isPaid && dueDate.isBefore(now);
}

class DonationRequest {
  const DonationRequest({
    required this.campaignId,
    required this.amount,
    required this.donorName,
    required this.donorEmail,
    required this.anonymous,
    required this.clientKey,
  });
  final String? campaignId;
  final Money amount;
  final String donorName;
  final String donorEmail;
  final bool anonymous;

  /// Çift tıklamada aynı ödemeyi tekrar kullanmak için (sunucuda idempotency anahtarı).
  final String clientKey;
}

class DonationResult {
  const DonationResult({required this.paymentId, required this.simulated, required this.succeeded});
  final String paymentId;
  final bool simulated;
  final bool succeeded;
}

class UserProfile {
  const UserProfile({required this.name, required this.email, required this.role});
  final String name;
  final String email;
  final AppRole role;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.route,
    required this.createdAt,
    required this.read,
  });
  final String id;
  final String title;
  final String body;
  final String route;
  final DateTime createdAt;
  final bool read;

  AppNotification asRead() => AppNotification(id: id, title: title, body: body, route: route, createdAt: createdAt, read: true);
}

/// Bildirim tercihleri (sunucudaki `notificationPrefs` ile aynı anahtarlar). İşlemsel bildirimler
/// (ödeme sonucu, kayıt/bağış/aidat onayı) tercihten bağımsız gönderilir.
class NotificationPrefs {
  const NotificationPrefs({this.events = true, this.dues = true, this.donations = true, this.announcements = true});
  final bool events;
  final bool dues;
  final bool donations;
  final bool announcements;

  NotificationPrefs copyWith({bool? events, bool? dues, bool? donations, bool? announcements}) => NotificationPrefs(
        events: events ?? this.events,
        dues: dues ?? this.dues,
        donations: donations ?? this.donations,
        announcements: announcements ?? this.announcements,
      );
}

/// Bildirim tercihleri. Ödeme sonucu ve makbuz gibi işlemsel bildirimler kapatılamaz.
class NotificationPrefs {
  const NotificationPrefs({this.events = true, this.dues = true, this.donations = true, this.announcements = true});
  final bool events;
  final bool dues;
  final bool donations;
  final bool announcements;

  NotificationPrefs copyWith({bool? events, bool? dues, bool? donations, bool? announcements}) => NotificationPrefs(
        events: events ?? this.events,
        dues: dues ?? this.dues,
        donations: donations ?? this.donations,
        announcements: announcements ?? this.announcements,
      );
}
