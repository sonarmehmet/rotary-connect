import 'package:flutter/material.dart';

import 'form_kit.dart';

/// Salt okunur ayrıntı penceresi (etiket/değer satırları).
///
/// `actionsBuilder` ek eylemler üretir (örn. "İade başlat"); "Kapat" her zaman
/// sonda yer alır.
Future<void> showDetailDialog(
  BuildContext context, {
  required String title,
  required List<(String, String)> rows,
  List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return DialogShell(
        title: title,
        actions: [
          ...?actionsBuilder?.call(dialogContext),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Kapat'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text(
                        row.$1,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(child: SelectableText(row.$2)),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
