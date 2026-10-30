import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/admin_table.dart';
import '../../ui/detail_dialog.dart';
import '../../ui/page_frame.dart';

String _json(Map<String, Object?>? map) {
  if (map == null || map.isEmpty) return '—';
  return map.entries.map((e) => '${e.key}: ${e.value}').join('\n');
}

/// Denetim kayıtları (değiştirilemez; yalnızca system_admin okur).
class AuditPage extends ConsumerWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auditLogsProvider);
    return AdminPageFrame(
      title: 'Denetim Kayıtları',
      subtitle: 'Kayıtlar değiştirilemez ve silinemez; kişisel veri içermez.',
      child: AsyncBody<List<AuditLogEntry>>(
        value: async,
        onRetry: () => ref.invalidate(auditLogsProvider),
        builder: (rows) {
          final actions = (rows.map((r) => r.action).toSet().toList()..sort());
          return AdminTable<AuditLogEntry>(
            rows: rows,
            emptyMessage: 'Henüz denetim kaydı yok.',
            searchText: (a) =>
                '${a.action} ${a.actorId} ${a.actorRole} ${a.targetType} ${a.targetId}',
            dateOf: (a) => a.createdAt,
            dateLabel: 'Kayıt tarihi',
            initialSortColumn: 0,
            initialAscending: false,
            onRowTap: (a) => showDetailDialog(
              context,
              title: a.action,
              rows: [
                ('Zaman', formatDateTime(a.createdAt)),
                ('İşlemi yapan', '${a.actorId} (${a.actorRole})'),
                ('Hedef', '${a.targetType} / ${a.targetId}'),
                ('Önce', _json(a.before)),
                ('Sonra', _json(a.after)),
              ],
            ),
            filters: [
              TableFilter<AuditLogEntry>(
                label: 'İşlem',
                options: [
                  for (final a in actions)
                    FilterOption<AuditLogEntry>(a, (e) => e.action == a),
                ],
              ),
            ],
            columns: [
              AdminColumn<AuditLogEntry>(
                label: 'Zaman',
                text: (a) => formatDateTime(a.createdAt),
                compare: (a, b) => a.createdAt.compareTo(b.createdAt),
              ),
              AdminColumn<AuditLogEntry>(label: 'İşlem', text: (a) => a.action),
              AdminColumn<AuditLogEntry>(
                label: 'İşlemi yapan',
                text: (a) => '${a.actorId} (${a.actorRole})',
              ),
              AdminColumn<AuditLogEntry>(
                label: 'Hedef',
                text: (a) => '${a.targetType} / ${a.targetId}',
              ),
            ],
          );
        },
      ),
    );
  }
}
