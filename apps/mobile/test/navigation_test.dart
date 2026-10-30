import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_mobile/app.dart';
import 'package:rotary_mobile/core/router/app_router.dart';
import 'package:rotary_mobile/data/providers.dart';
import 'package:rotary_shared/shared.dart';

void main() {
  testWidgets('ana sayfa açılır; ziyaretçi aidat kısayolunu görmez',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RotaryConnectApp()));
    await tester.pumpAndSettle();

    expect(find.text('Rotary Connect'), findsWidgets);
    expect(find.text('Bağış Yap'), findsWidgets);
    expect(find.text('Aidat ve Ödemelerim'), findsNothing);
  });

  testWidgets('kulüp üyesi aidat kısayolunu görür', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRoleProvider.overrideWith((ref) => AppRole.clubMember),
        ],
        child: const RotaryConnectApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aidat ve Ödemelerim'), findsOneWidget);
  });

  testWidgets('alt gezinme Bağış sekmesine geçer', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RotaryConnectApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NavigationDestination, 'Bağış'));
    await tester.pumpAndSettle();

    expect(find.text('Bağış Yap'), findsWidgets);
    expect(find.text('Tutar (₺)'), findsOneWidget);
  });

  testWidgets('giriş ve çıkış rolü günceller', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const RotaryConnectApp()));
    await tester.pumpAndSettle();

    expect(await container.read(sessionProvider.notifier).signIn('uye@x.co', 'sifre1234'), isTrue);
    expect(container.read(currentRoleProvider), AppRole.clubMember);
    expect(await container.read(sessionProvider.notifier).signIn('a@x.co', 'kisa'), isFalse);
    await container.read(sessionProvider.notifier).signOut();
    expect(container.read(currentRoleProvider), AppRole.visitor);
  });

  testWidgets('bağış formu geçersiz tutarda gönderilmez', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RotaryConnectApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Bağış'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Bağış Yap'));
    await tester.pumpAndSettle();
    expect(find.text('Geçerli bir tutar girin'), findsOneWidget);
  });
}
