import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/admin_exception.dart';
import '../data/providers.dart';
import 'state_views.dart';
import 'test_data_banner.dart';

/// Sayfa çerçevesi: başlık, eylem düğmeleri, örnek veri uyarısı ve içerik.
class AdminPageFrame extends ConsumerWidget {
  const AdminPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSample = ref.watch(adminRepositoryProvider).isSample;
    final narrow = MediaQuery.sizeOf(context).width < 1000;
    final subtitleText = subtitle;
    return Padding(
      padding: EdgeInsets.all(narrow ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (subtitleText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(subtitleText),
                      ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isSample)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: TestDataBanner(),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// `AsyncValue` için yükleniyor / hata / veri geçişi.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const LoadingView(),
      error: (error, _) =>
          ErrorView(message: errorMessageTr(error), onRetry: onRetry),
    );
  }
}
