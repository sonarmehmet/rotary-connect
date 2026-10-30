import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_admin_web/main.dart';
import 'package:rotary_shared/shared.dart';

void main() {
  testWidgets('sistem yöneticisi geniş ekranda gezinme çubuğunu görür',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();

    expect(find.text('Denetim Kayıtları'), findsOneWidget);
    expect(find.text('Rol ve İzinler'), findsOneWidget);
  });

  testWidgets('içerik yöneticisi finans ve rol modüllerini görmez',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRoleProvider.overrideWith((ref) => AppRole.contentManager),
        ],
        child: const AdminApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Haberler ve Duyurular'), findsOneWidget);
    expect(find.text('İadeler'), findsNothing);
    expect(find.text('Rol ve İzinler'), findsNothing);
  });

  testWidgets('Genel Bakış izni olmayan rol ilk erişebildiği modüle yönlenir',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();

    // Sistem yöneticisi: '/' yerine 'Kullanıcı ve Üyeler' açılır.
    expect(find.text('Bu sayfayı görüntüleme yetkiniz yok.'), findsNothing);
    expect(find.text('Kayıt olmak üye olmak değildir; üyelik yönetici '
        'onayıyla başlar.'), findsOneWidget);
  });
}
