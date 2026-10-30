import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/admin_exception.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/role_provider.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/admin_table.dart';
import '../../ui/form_kit.dart';
import '../../ui/page_frame.dart';

/// Raporlar: aylık özet tablosu (report_aggregates) + CSV dışa aktarma.
/// Dışa aktarma yalnızca `exportFinancialData` izniyle görünür; asıl yetki
/// `exportReport` function'ında denetlenir ve audit_logs'a yazılır.
class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canExport =
        ref.watch(adminRoleProvider).can(Permission.exportFinancialData);
    final async = ref.watch(aggregatesProvider);
    return AdminPageFrame(
      title: 'Raporlar',
      subtitle: 'Bağış, aidat ve etkinlik satırları ayrıdır; net = brüt − iade.',
      actions: [
        if (canExport)
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ExportDialog(),
            ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV dışa aktar'),
          ),
      ],
      child: AsyncBody<List<ReportAggregate>>(
        value: async,
        onRetry: () => ref.invalidate(aggregatesProvider),
        builder: (rows) => AdminTable<ReportAggregate>(
          rows: rows,
          emptyMessage: 'Henüz rapor verisi yok.',
          searchText: (a) => '${a.period} ${periodLabelTr(a.period)} ${a.kind.labelTr}',
          initialSortColumn: 0,
          initialAscending: false,
          filters: [
            TableFilter<ReportAggregate>(
              label: 'Tür',
              options: [
                for (final k in PaymentKind.values)
                  FilterOption<ReportAggregate>(k.labelTr, (a) => a.kind == k),
              ],
            ),
          ],
          columns: [
            AdminColumn<ReportAggregate>(
              label: 'Dönem',
              text: (a) => periodLabelTr(a.period),
              compare: (a, b) => a.period.compareTo(b.period),
            ),
            AdminColumn<ReportAggregate>(label: 'Tür', text: (a) => a.kind.labelTr),
            AdminColumn<ReportAggregate>(
              label: 'Brüt',
              numeric: true,
              text: (a) => moneyText(a.collectedMinor, currency: a.currency),
              compare: (a, b) => a.collectedMinor.compareTo(b.collectedMinor),
            ),
            AdminColumn<ReportAggregate>(
              label: 'İade',
              numeric: true,
              text: (a) => moneyText(a.refundedMinor, currency: a.currency),
              compare: (a, b) => a.refundedMinor.compareTo(b.refundedMinor),
            ),
            AdminColumn<ReportAggregate>(
              label: 'Net',
              numeric: true,
              text: (a) => moneyText(a.netMinor, currency: a.currency),
              compare: (a, b) => a.netMinor.compareTo(b.netMinor),
            ),
            AdminColumn<ReportAggregate>(
              label: 'İşlem',
              numeric: true,
              text: (a) => '${a.count}',
              compare: (a, b) => a.count.compareTo(b.count),
            ),
          ],
        ),
      ),
    );
  }
}

/// CSV dışa aktarma penceresi. Dalga 1'de sonuç pano'ya kopyalanır;
/// dosya indirme (`exportReport` + tarayıcı indirmesi) Dalga 2'de bağlanır.
class ExportDialog extends ConsumerStatefulWidget {
  const ExportDialog({super.key});

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  ExportKind _kind = ExportKind.payments;
  DateRange? _range;
  bool _busy = false;
  String? _error;
  String? _csv;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Tarih aralığı seçin',
      saveText: 'Uygula',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = DateRange(picked.start, picked.end);
      _csv = null;
    });
  }

  Future<void> _run() async {
    if (_busy) return;
    // Arayüz kontrolü yalnızca kolaylıktır; sunucu yine denetler.
    if (!ref.read(adminRoleProvider).can(Permission.exportFinancialData)) {
      setState(() => _error = errorMessageTr(
            const AdminException('permission-denied'),
          ));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _csv = null;
    });
    try {
      final csv = await ref
          .read(adminRepositoryProvider)
          .exportReport(ExportRequest(kind: _kind, range: _range));
      ref.invalidate(auditLogsProvider);
      if (mounted) setState(() => _csv = csv);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessageTr(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final csv = _csv;
    if (csv == null) return;
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV panoya kopyalandı.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final csv = _csv;
    final lineCount =
        csv == null ? 0 : '\n'.allMatches(csv).length - 1; // başlık hariç
    return DialogShell(
      title: 'CSV dışa aktar',
      maxWidth: 640,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
        if (csv != null)
          OutlinedButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Panoya kopyala'),
          ),
        FilledButton(
          onPressed: _busy ? null : _run,
          child: Text(_busy ? 'Hazırlanıyor…' : 'Dışa aktar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fieldPad(
            EnumDropdown<ExportKind>(
              label: 'Rapor',
              value: _kind,
              values: ExportKind.values,
              labelOf: (v) => v.label,
              onChanged: (v) => setState(() {
                _kind = v;
                _csv = null;
              }),
            ),
          ),
          fieldPad(
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_range?.label ?? 'Tüm tarihler'),
              ),
            ),
          ),
          const Text(
            'Dışa aktarma denetim kaydına yazılır. Dosyada kişisel veri '
            '(ad, e-posta) bulunmaz; tutarlar kuruş ve biçimli olarak yer alır. '
            'Ayraç noktalı virgüldür (Türkçe Excel).',
            style: TextStyle(fontSize: 12),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(BrandColors.error)),
              ),
            ),
          if (csv != null) ...[
            const SizedBox(height: 12),
            Text('$lineCount satır hazırlandı. Önizleme:'),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(BrandColors.lightGray),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  csv.replaceFirst('﻿', ''),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
