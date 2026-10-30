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

/// Haberler ve duyurular. Yazma yetkisi: `manageContent`.
class NewsPage extends ConsumerWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(adminRoleProvider).can(Permission.manageContent);
    final async = ref.watch(newsProvider);
    return AdminPageFrame(
      title: 'Haberler ve Duyurular',
      actions: [
        if (canEdit)
          FilledButton.icon(
            onPressed: () => _openForm(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Yeni kayıt'),
          ),
      ],
      child: AsyncBody<List<NewsItem>>(
        value: async,
        onRetry: () => ref.invalidate(newsProvider),
        builder: (rows) => AdminTable<NewsItem>(
          rows: rows,
          emptyMessage: 'Henüz haber veya duyuru yok.',
          searchText: (n) => '${n.title} ${n.category} ${n.kind.label}',
          dateOf: (n) => n.publishedAt,
          dateLabel: 'Yayın tarihi',
          onRowTap: (n) => canEdit ? _openForm(context, n) : _view(context, n),
          filters: [
            TableFilter<NewsItem>(
              label: 'Tür',
              options: [
                for (final k in NewsKind.values)
                  FilterOption<NewsItem>(k.label, (n) => n.kind == k),
              ],
            ),
            TableFilter<NewsItem>(
              label: 'Yayın',
              options: [
                FilterOption<NewsItem>('Yayında', (n) => n.published),
                FilterOption<NewsItem>('Taslak', (n) => !n.published),
              ],
            ),
          ],
          columns: [
            AdminColumn<NewsItem>(
              label: 'Başlık',
              text: (n) => n.title,
              compare: (a, b) => a.title.compareTo(b.title),
            ),
            AdminColumn<NewsItem>(label: 'Tür', text: (n) => n.kind.label),
            AdminColumn<NewsItem>(label: 'Kategori', text: (n) => n.category),
            AdminColumn<NewsItem>(
              label: 'Yayın',
              text: (n) => n.published ? 'Yayında' : 'Taslak',
              cell: (_, n) => StatusChip(
                label: n.published ? 'Yayında' : 'Taslak',
                tone: n.published ? StatusTone.success : StatusTone.neutral,
              ),
            ),
            AdminColumn<NewsItem>(
              label: 'Yayın tarihi',
              text: (n) => formatDateTime(n.publishedAt),
            ),
            AdminColumn<NewsItem>(
              label: 'Sabit',
              text: (n) => n.kind == NewsKind.announcement && n.pinned ? 'Evet' : '—',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, NewsItem? initial) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => NewsFormDialog(initial: initial),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kayıt kaydedildi.')),
      );
    }
  }

  void _view(BuildContext context, NewsItem n) {
    showDetailDialog(
      context,
      title: n.title,
      rows: [
        ('Tür', n.kind.label),
        ('Kategori', n.category),
        ('Yayın', n.published ? 'Yayında' : 'Taslak'),
        ('Yayın tarihi', formatDateTime(n.publishedAt)),
        ('İçerik', n.body),
      ],
    );
  }
}

class NewsFormDialog extends ConsumerStatefulWidget {
  const NewsFormDialog({super.key, this.initial});

  final NewsItem? initial;

  @override
  ConsumerState<NewsFormDialog> createState() => _NewsFormDialogState();
}

class _NewsFormDialogState extends ConsumerState<NewsFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _category;
  late NewsKind _kind;
  late bool _published;
  late bool _pinned;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = widget.initial;
    _title = TextEditingController(text: n?.title ?? '');
    _body = TextEditingController(text: n?.body ?? '');
    _category = TextEditingController(text: n?.category ?? '');
    _kind = n?.kind ?? NewsKind.news;
    _published = n?.published ?? false;
    _pinned = n?.pinned ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final old = widget.initial;
    final now = ref.read(adminClockProvider)();
    // Yayın tarihi: ilk yayında şimdi; yayından kaldırılırsa temizlenir;
    // zaten yayındaysa korunur.
    final DateTime? publishedAt = _published ? (old?.publishedAt ?? now) : null;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveNews(
            NewsItem(
              id: old?.id ?? '',
              kind: _kind,
              title: _title.text.trim(),
              body: _body.text.trim(),
              category: _category.text.trim(),
              published: _published,
              publishedAt: publishedAt,
              authorId: old?.authorId ?? ref.read(adminUserIdProvider),
              pinned: _kind == NewsKind.announcement && _pinned,
            ),
          );
      ref.invalidate(newsProvider);
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
      title: widget.initial == null ? 'Yeni haber / duyuru' : 'Kaydı düzenle',
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
              EnumDropdown<NewsKind>(
                label: 'Tür',
                value: _kind,
                values: NewsKind.values,
                labelOf: (v) => v.label,
                onChanged: (v) => setState(() => _kind = v),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _title,
                decoration: fieldDecoration('Başlık'),
                validator: requiredText(min: 3, max: 160),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _category,
                decoration: fieldDecoration('Kategori'),
                validator: requiredText(min: 2, max: 60),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _body,
                decoration: fieldDecoration('İçerik'),
                maxLines: 6,
                validator: requiredText(min: 10, max: 10000),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Yayında'),
              value: _published,
              onChanged: (v) => setState(() => _published = v),
            ),
            if (_kind == NewsKind.announcement)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Başa sabitle'),
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
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
