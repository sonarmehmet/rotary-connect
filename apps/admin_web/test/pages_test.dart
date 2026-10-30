import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_admin_web/core/role_provider.dart';
import 'package:rotary_admin_web/features/campaigns/campaigns_page.dart';
import 'package:rotary_admin_web/features/overview/overview_page.dart';
import 'package:rotary_admin_web/features/payments/payments_page.dart';
import 'package:rotary_admin_web/features/reports/reports_page.dart';
import 'package:rotary_admin_web/ui/admin_table.dart';
import 'package:rotary_shared/shared.dart';

void _size(WidgetTester tester, double width, [double height = 900]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  AppRole role = AppRole.systemAdmin,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminRoleProvider.overrideWith((ref) => role)],
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AdminTable', () {
    Future<void> pumpTable(WidgetTester tester, {int count = 30}) async {
      _size(tester, 1400);
      final rows = [for (var i = 1; i <= count; i++) 'Kayıt $i'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminTable<String>(
              rows: rows,
              searchText: (r) => r,
              columns: [
                AdminColumn<String>(label: 'Ad', text: (r) => r),
              ],
              filters: [
                TableFilter<String>(
                  label: 'Tür',
                  options: [
                    FilterOption<String>('Tek', (r) => r.hashCode.isOdd),
                    FilterOption<String>('Hepsi', (r) => true),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sayfalama: 10 kayıt gösterir ve sonraki sayfaya geçer',
        (tester) async {
      await pumpTable(tester);
      expect(find.text('1–10 / 30 kayıt'), findsOneWidget);
      expect(find.text('Kayıt 1'), findsOneWidget);
      expect(find.text('Kayıt 11'), findsNothing);

      await tester.tap(find.byTooltip('Sonraki sayfa'));
      await tester.pumpAndSettle();
      expect(find.text('11–20 / 30 kayıt'), findsOneWidget);
      expect(find.text('Kayıt 11'), findsOneWidget);
    });

    testWidgets('arama sayfa 1\'e döner ve sonucu daraltır', (tester) async {
      await pumpTable(tester);
      await tester.tap(find.byTooltip('Sonraki sayfa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'kayıt 25');
      await tester.pumpAndSettle();
      expect(find.text('1–1 / 1 kayıt'), findsOneWidget);
      expect(find.text('Kayıt 25'), findsOneWidget);
    });

    testWidgets('eşleşme yoksa filtre-sonucu-yok mesajı ve temizle düğmesi',
        (tester) async {
      await pumpTable(tester);
      await tester.enterText(find.byType(TextField), 'bulunmaz');
      await tester.pumpAndSettle();
      expect(find.text('Filtrelere uyan kayıt bulunamadı.'), findsOneWidget);

      await tester.tap(find.text('Filtreleri temizle'));
      await tester.pumpAndSettle();
      expect(find.text('1–10 / 30 kayıt'), findsOneWidget);
    });

    testWidgets('boş liste için boş durum mesajı', (tester) async {
      await pumpTable(tester, count: 0);
      expect(find.text('Henüz kayıt yok.'), findsOneWidget);
      expect(find.text('0–0 / 0 kayıt'), findsOneWidget);
    });

    testWidgets('800 px genişlikte taşma hatası vermez', (tester) async {
      _size(tester, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminTable<String>(
              rows: const ['a', 'b'],
              searchText: (r) => r,
              columns: [
                for (var i = 0; i < 8; i++)
                  AdminColumn<String>(label: 'Sütun $i', text: (r) => '$r$i'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('sayfalar', () {
    testWidgets('Genel Bakış: üç tür ayrı kart, örnek veri uyarısı',
        (tester) async {
      _size(tester, 1400);
      await _pump(tester, const OverviewPage());
      expect(find.text('Bağış'), findsOneWidget);
      expect(find.text('Aidat'), findsOneWidget);
      expect(find.text('Etkinlik ücreti'), findsOneWidget);
      expect(find.text('Net (iade düşülmüş)'), findsNWidgets(3));
      expect(find.textContaining('ÖRNEK VERİ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Genel Bakış 800 px genişlikte taşmaz', (tester) async {
      _size(tester, 800);
      await _pump(tester, const OverviewPage());
      expect(tester.takeException(), isNull);
    });

    testWidgets('içerik yöneticisi Genel Bakış\'ı görmez', (tester) async {
      _size(tester, 1400);
      await _pump(tester, const OverviewPage(), role: AppRole.contentManager);
      expect(find.text('Bu sayfayı görüntüleme yetkiniz yok.'), findsOneWidget);
      expect(find.text('Net (iade düşülmüş)'), findsNothing);
    });

    testWidgets('kampanya listesi: içerik yöneticisi "Yeni kampanya" görür',
        (tester) async {
      _size(tester, 1400);
      await _pump(tester, const CampaignsPage(), role: AppRole.contentManager);
      expect(find.text('Yeni kampanya'), findsOneWidget);
      expect(find.text('Köy Okulu Kütüphane Projesi'), findsOneWidget);
    });

    testWidgets('finans yöneticisi kampanya oluşturamaz', (tester) async {
      _size(tester, 1400);
      await _pump(tester, const CampaignsPage(), role: AppRole.financeManager);
      expect(find.text('Yeni kampanya'), findsNothing);
    });

    testWidgets('kampanya formu boş gönderilince doğrulama hatası gösterir',
        (tester) async {
      _size(tester, 1400, 1000);
      await _pump(tester, const CampaignsPage());
      await tester.tap(find.text('Yeni kampanya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Zorunlu alan'), findsWidgets);
    });

    testWidgets('ödemeler: durum filtresi "Beklemede" satırlarını daraltır',
        (tester) async {
      _size(tester, 1400);
      await _pump(tester, const PaymentsPage(), role: AppRole.financeManager);
      expect(find.text('1–10 / 24 kayıt'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Beklemede'));
      await tester.pumpAndSettle();
      expect(find.text('1–3 / 3 kayıt'), findsOneWidget);
    });

    testWidgets('CSV dışa aktar: yalnızca dışa aktarma izni olan rolde görünür',
        (tester) async {
      _size(tester, 1400);
      await _pump(tester, const ReportsPage(), role: AppRole.financeManager);
      expect(find.text('CSV dışa aktar'), findsOneWidget);
    });

    testWidgets('CSV dışa aktar: sistem yöneticisinde (izin yok) görünmez',
        (tester) async {
      _size(tester, 1400);
      await _pump(tester, const ReportsPage());
      expect(find.text('CSV dışa aktar'), findsNothing);
    });

    testWidgets('CSV dışa aktarma önizleme üretir', (tester) async {
      _size(tester, 1400, 1000);
      await _pump(tester, const ReportsPage(), role: AppRole.financeManager);
      await tester.tap(find.text('CSV dışa aktar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dışa aktar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('satır hazırlandı'), findsOneWidget);
      expect(find.textContaining('odeme_id;'), findsOneWidget);
    });
  });
}
