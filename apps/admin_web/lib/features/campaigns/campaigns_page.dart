import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/admin_exception.dart';
import '../../core/role_provider.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/admin_table.dart';
import '../../ui/detail_dialog.dart';
import '../../ui/form_kit.dart';
import '../../ui/page_frame.dart';
import '../../ui/status_chip.dart';

/// Bağış kampanyaları: liste + oluştur/düzenle. Yazma yetkisi: içerik yöneticisi.
class CampaignsPage extends ConsumerWidget {
  const CampaignsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(adminRoleProvider).can(Permission.manageContent);
    final async = ref.watch(campaignsProvider);
    return AdminPageFrame(
      title: 'Bağış Kampanyaları',
      subtitle: 'Toplanan tutar yalnızca doğrulanmış ödemelerden gelir '
          '(iade düşülmüş).',
      actions: [
        if (canEdit)
          FilledButton.icon(
            onPressed: () => _openForm(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Yeni kampanya'),
          ),
      ],
      child: AsyncBody<List<Campaign>>(
        value: async,
        onRetry: () => ref.invalidate(campaignsProvider),
        builder: (rows) => AdminTable<Campaign>(
          rows: rows,
          emptyMessage: 'Henüz kampanya yok.',
          searchText: (c) => '${c.title} ${c.category.label} ${c.status.label}',
          dateOf: (c) => c.createdAt,
          dateLabel: 'Oluşturma tarihi',
          onRowTap: (c) => canEdit ? _openForm(context, c) : _view(context, c),
          filters: [
            TableFilter<Campaign>(
              label: 'Durum',
              options: [
                for (final s in CampaignStatus.values)
                  FilterOption<Campaign>(s.label, (c) => c.status == s),
              ],
            ),
            TableFilter<Campaign>(
              label: 'Kategori',
              options: [
                for (final k in CampaignCategory.values)
                  FilterOption<Campaign>(k.label, (c) => c.category == k),
              ],
            ),
          ],
          columns: [
            AdminColumn<Campaign>(
              label: 'Başlık',
              text: (c) => c.title,
              compare: (a, b) => a.title.compareTo(b.title),
            ),
            AdminColumn<Campaign>(label: 'Kategori', text: (c) => c.category.label),
            AdminColumn<Campaign>(
              label: 'Durum',
              text: (c) => c.status.label,
              cell: (_, c) => StatusChip(label: c.status.label, tone: c.status.tone),
            ),
            AdminColumn<Campaign>(
              label: 'Hedef',
              numeric: true,
              text: (c) => moneyText(c.goalMinor, currency: c.currency),
              compare: (a, b) => a.goalMinor.compareTo(b.goalMinor),
            ),
            AdminColumn<Campaign>(
              label: 'Toplanan (doğrulanmış)',
              numeric: true,
              text: (c) => moneyText(c.verifiedTotalMinor, currency: c.currency),
              compare: (a, b) =>
                  a.verifiedTotalMinor.compareTo(b.verifiedTotalMinor),
            ),
            AdminColumn<Campaign>(
              label: 'İlerleme',
              text: (c) => '%${(c.progress * 100).round()}',
              cell: (_, c) => SizedBox(
                width: 110,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: c.progress),
                    const SizedBox(height: 4),
                    Text(
                      '%${(c.progress * 100).round()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            AdminColumn<Campaign>(
              label: 'Bitiş',
              text: (c) => formatDate(c.endsAt),
              compare: (a, b) => (a.endsAt ?? DateTime(9999))
                  .compareTo(b.endsAt ?? DateTime(9999)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, Campaign? initial) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CampaignFormDialog(initial: initial),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kampanya kaydedildi.')),
      );
    }
  }

  void _view(BuildContext context, Campaign c) {
    showDetailDialog(
      context,
      title: c.title,
      rows: [
        ('Kategori', c.category.label),
        ('Durum', c.status.label),
        ('Hedef', moneyText(c.goalMinor, currency: c.currency)),
        (
          'Toplanan (doğrulanmış)',
          moneyText(c.verifiedTotalMinor, currency: c.currency),
        ),
        ('Bağışçı sayısı', '${c.donorCount}'),
        ('Bitiş', formatDate(c.endsAt)),
        ('Açıklama', c.description),
      ],
    );
  }
}

class CampaignFormDialog extends ConsumerStatefulWidget {
  const CampaignFormDialog({super.key, this.initial});

  final Campaign? initial;

  @override
  ConsumerState<CampaignFormDialog> createState() => _CampaignFormDialogState();
}

class _CampaignFormDialogState extends ConsumerState<CampaignFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _goal;
  late CampaignCategory _category;
  late CampaignStatus _status;
  DateTime? _endsAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _title = TextEditingController(text: c?.title ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _goal = TextEditingController(text: c == null ? '' : moneyInput(c.goalMinor));
    _category = c?.category ?? CampaignCategory.general;
    _status = c?.status ?? CampaignStatus.draft;
    _endsAt = c?.endsAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final goal = Money.tryParseTr(_goal.text);
    if (goal == null) return;
    final old = widget.initial;
    final now = ref.read(adminClockProvider)();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // `verifiedTotalMinor` ve `donorCount` istemciden yazılmaz: gerçek depo
      // bu alanları gönderilen belgeden çıkarır, yalnızca Functions değiştirir.
      await ref.read(adminRepositoryProvider).saveCampaign(
            Campaign(
              id: old?.id ?? '',
              title: _title.text.trim(),
              description: _description.text.trim(),
              category: _category,
              goalMinor: goal.minor,
              status: _status,
              endsAt: _endsAt,
              createdAt: old?.createdAt ?? now,
              currency: old?.currency ?? 'TRY',
              verifiedTotalMinor: old?.verifiedTotalMinor ?? 0,
              donorCount: old?.donorCount ?? 0,
              projectId: old?.projectId,
              eventId: old?.eventId,
            ),
          );
      ref.invalidate(campaignsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessageTr(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      title: widget.initial == null ? 'Yeni kampanya' : 'Kampanyayı düzenle',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fieldPad(
              TextFormField(
                controller: _title,
                decoration: fieldDecoration('Başlık'),
                validator: requiredText(min: 3, max: 120),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _description,
                decoration: fieldDecoration('Açıklama'),
                maxLines: 4,
                validator: requiredText(min: 10, max: 2000),
              ),
            ),
            fieldPad(
              EnumDropdown<CampaignCategory>(
                label: 'Kategori',
                value: _category,
                values: CampaignCategory.values,
                labelOf: (v) => v.label,
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
            fieldPad(
              EnumDropdown<CampaignStatus>(
                label: 'Durum',
                value: _status,
                values: CampaignStatus.values,
                labelOf: (v) => v.label,
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _goal,
                decoration: fieldDecoration('Hedef tutar (₺)', helper: 'Örn. 150.000'),
                keyboardType: TextInputType.number,
                validator: moneyValidator(),
              ),
            ),
            fieldPad(
              DateFormField(
                label: 'Bitiş tarihi (isteğe bağlı)',
                initialValue: _endsAt,
                isRequired: false,
                endOfDay: true,
                onChanged: (v) => _endsAt = v,
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Color(BrandColors.error)),
              ),
          ],
        ),
      ),
    );
  }
}
