/// Derleme zamanı ortam ayarları. Örnek:
/// `flutter run --dart-define=APP_ENV=dev --dart-define=PAYMENT_MODE=simulation`
///
/// Gizli anahtarlar (ödeme sağlayıcı API anahtarları vb.) ASLA buraya konmaz;
/// yalnızca sunucu tarafında (Cloud Functions + Secret Manager) tutulur.
enum PaymentMode { simulation, live }

abstract final class AppEnv {
  static const String name =
      String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static const String _paymentModeRaw =
      String.fromEnvironment('PAYMENT_MODE', defaultValue: 'simulation');

  static bool get isProduction => name == 'prod';

  /// Varsayılan her zaman simülasyondur. Canlı mod yalnızca açıkça seçilirse
  /// ve üretim ortamında etkinleşir.
  static PaymentMode get paymentMode =>
      (_paymentModeRaw == 'live' && isProduction)
          ? PaymentMode.live
          : PaymentMode.simulation;

  static bool get isSimulation => paymentMode == PaymentMode.simulation;

  /// Geliştirme/test ortamında örnek veriler gösterilebilir ve işaretlenir.
  static bool get showTestDataBadges => !isProduction;
}
