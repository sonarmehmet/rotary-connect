import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';

/// Yükleniyor / hata / boş / veri durumlarını tek yerde yönetir.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.emptyText = 'Henüz içerik yok.',
    this.onRetry,
    this.isEmpty,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final String emptyText;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message(
        icon: Icons.error_outline,
        text: 'Bir sorun oluştu. Lütfen tekrar deneyin.',
        action: onRetry == null ? null : TextButton(onPressed: onRetry, child: const Text('Yeniden dene')),
      ),
      data: (d) => (isEmpty?.call(d) ?? (d is Iterable && d.isEmpty))
          ? _Message(icon: Icons.inbox_outlined, text: emptyText)
          : builder(d),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Gaps.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40),
            const SizedBox(height: Gaps.sm),
            Text(text, textAlign: TextAlign.center),
            if (action != null) action!,
          ]),
        ),
      );
}
