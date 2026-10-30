import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/admin_exception.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/role_provider.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/admin_table.dart';
import '../../ui/detail_dialog.dart';
import '../../ui/form_kit.dart';
import '../../ui/page_frame.dart';
import '../../ui/status_chip.dart';

/// Projeler: liste + oluştur/düzenle. Yazma yetkisi: `manageContent`.
class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(adminRoleProvider).can(Permission.manageContent);
    final async = ref.watch(projectsProvider);
    return AdminPageFrame(
      title: 'Projeler',
      actions: [
        if (canEdit)
          FilledButton.icon(
            onPressed: () => _openForm(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Yeni proje'),
          ),
      ],
      child: AsyncBody<List<Project>>(
        value: async,
        onRetry: () => ref.invalidate(projectsProvider),
        builder: (rows) => AdminTable<Project>(
          rows: rows,
          emptyMessage: 'Henüz proje yok.',
          searchText: (p) => '${p.title} ${p.leadName} ${p.status.label}',
          dateOf: (p) => p.startDate,
          dateLabel: 'Başlangıç tarihi',
          onRowTap: (p) => canEdit ? _openForm(context, p) : _view(context, p),
          filters: [
            TableFilter<Project>(
              label: 'Durum',
              options: [
                for (final s in ProjectStatus.values)
                  FilterOption<Project>(s.label, (p) => p.status == s),
              ],
            ),
          ],
          columns: [
            AdminColumn<Project>(
              label: 'Başlık',
              text: (p) => p.title,
              compare: (a, b) => a.title.compareTo(b.title),
            ),
            AdminColumn<Project>(label: 'Sorumlu', text: (p) => p.leadName),
            AdminColumn<Project>(
              label: 'Durum',
              text: (p) => p.status.label,
              cell: (_, p) => StatusChip(label: p.status.label, tone: p.status.tone),
            ),
            AdminColumn<Project>(
              label: 'Başlangıç',
              text: (p) => formatDate(p.startDate),
              compare: (a, b) => a.startDate.compareTo(b.startDate),
            ),
            AdminColumn<Project>(label: 'Bitiş', text: (p) => formatDate(p.endDate)),
            AdminColumn<Project>(label: 'Hedefler', text: (p) => p.goals),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, Project? initial) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProjectFormDialog(initial: initial),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proje kaydedildi.')),
      );
    }
  }

  void _view(BuildContext context, Project p) {
    showDetailDialog(
      context,
      title: p.title,
      rows: [
        ('Durum', p.status.label),
        ('Sorumlu', p.leadName),
        ('Başlangıç', formatDate(p.startDate)),
        ('Bitiş', formatDate(p.endDate)),
        ('Hedefler', p.goals),
        ('Doğrulanmış sonuçlar', p.verifiedResults ?? '—'),
        ('Açıklama', p.description),
      ],
    );
  }
}

class ProjectFormDialog extends ConsumerStatefulWidget {
  const ProjectFormDialog({super.key, this.initial});

  final Project? initial;

  @override
  ConsumerState<ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends ConsumerState<ProjectFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _lead;
  late final TextEditingController _goals;
  late final TextEditingController _results;
  late ProjectStatus _status;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _title = TextEditingController(text: p?.title ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _lead = TextEditingController(text: p?.leadName ?? '');
    _goals = TextEditingController(text: p?.goals ?? '');
    _results = TextEditingController(text: p?.verifiedResults ?? '');
    _status = p?.status ?? ProjectStatus.draft;
    _start = p?.startDate;
    _end = p?.endDate;
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _lead, _goals, _results]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final start = _start;
    if (start == null) return;
    final end = _end;
    if (end != null && end.isBefore(start)) {
      setState(() => _error = 'Bitiş tarihi başlangıçtan önce olamaz.');
      return;
    }
    final old = widget.initial;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveProject(
            Project(
              id: old?.id ?? '',
              title: _title.text.trim(),
              description: _description.text.trim(),
              leadName: _lead.text.trim(),
              status: _status,
              startDate: start,
              endDate: end,
              goals: _goals.text.trim(),
              verifiedResults:
                  _results.text.trim().isEmpty ? null : _results.text.trim(),
              campaignId: old?.campaignId,
            ),
          );
      ref.invalidate(projectsProvider);
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
      title: widget.initial == null ? 'Yeni proje' : 'Projeyi düzenle',
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
                maxLines: 3,
                validator: requiredText(min: 10, max: 2000),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _lead,
                decoration: fieldDecoration('Proje sorumlusu'),
                validator: requiredText(min: 2, max: 120),
              ),
            ),
            fieldPad(
              EnumDropdown<ProjectStatus>(
                label: 'Durum',
                value: _status,
                values: ProjectStatus.values,
                labelOf: (v) => v.label,
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            fieldPad(
              DateFormField(
                label: 'Başlangıç tarihi',
                initialValue: _start,
                onChanged: (v) => _start = v,
              ),
            ),
            fieldPad(
              DateFormField(
                label: 'Bitiş tarihi (isteğe bağlı)',
                isRequired: false,
                initialValue: _end,
                onChanged: (v) => _end = v,
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _goals,
                decoration: fieldDecoration('Hedefler'),
                maxLines: 2,
                validator: requiredText(min: 3, max: 1000),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _results,
                decoration: fieldDecoration(
                  'Doğrulanmış sonuçlar (isteğe bağlı)',
                  helper: 'Yalnızca doğrulanmış sonuçları yazın.',
                ),
                maxLines: 2,
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
