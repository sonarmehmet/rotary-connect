import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotary_mobile/app.dart';
import 'package:rotary_mobile/core/router/app_router.dart';
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

    expect(find.textContaining('Aşama 3'), findsOneWidget);
  });
}
