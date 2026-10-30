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

/// Etkinlikler: liste + oluştur/düzenle. Yazma yetkisi: `manageEvents`.
/// Kontenjan sayaçları (`reservedCount`, `confirmedCount`) salt okunurdur.
class EventsPage extends ConsumerWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(adminRoleProvider).can(Permission.manageEvents);
    final async = ref.watch(eventsProvider);
    return AdminPageFrame(
      title: 'Etkinlikler',
      subtitle: 'Kalan yer = kontenjan − onaylı − rezerve. Sayaçlar yalnızca '
          'sunucu tarafından değişir.',
      actions: [
        if (canEdit)
          FilledButton.icon(
            onPressed: () => _openForm(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Yeni etkinlik'),
          ),
      ],
      child: AsyncBody<List<ClubEvent>>(
        value: async,
        onRetry: () => ref.invalidate(eventsProvider),
        builder: (rows) => AdminTable<ClubEvent>(
          rows: rows,
          emptyMessage: 'Henüz etkinlik yok.',
          searchText: (e) => '${e.title} ${e.location} ${e.status.label}',
          dateOf: (e) => e.startsAt,
          dateLabel: 'Etkinlik tarihi',
          initialSortColumn: 1,
          initialAscending: false,
          onRowTap: (e) => canEdit ? _openForm(context, e) : _view(context, e),
          filters: [
            TableFilter<ClubEvent>(
              label: 'Durum',
              options: [
                for (final s in EventStatus.values)
                  FilterOption<ClubEvent>(s.label, (e) => e.status == s),
              ],
            ),
            TableFilter<ClubEvent>(
              label: 'Ücret',
              options: [
                FilterOption<ClubEvent>('Ücretsiz', (e) => e.isFree),
                FilterOption<ClubEvent>('Ücretli', (e) => !e.isFree),
              ],
            ),
          ],
          columns: [
            AdminColumn<ClubEvent>(
              label: 'Başlık',
              text: (e) => e.title,
              compare: (a, b) => a.title.compareTo(b.title),
            ),
            AdminColumn<ClubEvent>(
              label: 'Başlangıç',
              text: (e) => formatDateTime(e.startsAt),
              compare: (a, b) => a.startsAt.compareTo(b.startsAt),
            ),
            AdminColumn<ClubEvent>(label: 'Yer', text: (e) => e.location),
            AdminColumn<ClubEvent>(
              label: 'Ücret',
              numeric: true,
              text: (e) =>
                  e.isFree ? 'Ücretsiz' : moneyText(e.feeMinor, currency: e.currency),
              compare: (a, b) => a.feeMinor.compareTo(b.feeMinor),
            ),
            AdminColumn<ClubEvent>(
              label: 'Doluluk',
              numeric: true,
              text: (e) => '${e.confirmedCount}/${e.capacity}'
                  '${e.reservedCount > 0 ? ' (+${e.reservedCount} rezerve)' : ''}',
              compare: (a, b) => a.confirmedCount.compareTo(b.confirmedCount),
            ),
            AdminColumn<ClubEvent>(
              label: 'Durum',
              text: (e) => e.status.label,
              cell: (_, e) => StatusChip(label: e.status.label, tone: e.status.tone),
            ),
            AdminColumn<ClubEvent>(
              label: 'Son kayıt',
              text: (e) => formatDateTime(e.registrationDeadline),
              compare: (a, b) =>
                  a.registrationDeadline.compareTo(b.registrationDeadline),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, ClubEvent? initial) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EventFormDialog(initial: initial),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Etkinlik kaydedildi.')),
      );
    }
  }

  void _view(BuildContext context, ClubEvent e) {
    showDetailDialog(
      context,
      title: e.title,
      rows: [
        ('Durum', e.status.label),
        ('Başlangıç', formatDateTime(e.startsAt)),
        ('Bitiş', formatDateTime(e.endsAt)),
        ('Son kayıt', formatDateTime(e.registrationDeadline)),
        ('Yer', e.location),
        ('Ücret', e.isFree ? 'Ücretsiz' : moneyText(e.feeMinor, currency: e.currency)),
        ('Kontenjan', '${e.capacity}'),
        ('Onaylı / rezerve', '${e.confirmedCount} / ${e.reservedCount}'),
        ('Kalan yer', '${e.remaining}'),
        ('Bekleme listesi', e.waitlistEnabled ? 'Açık' : 'Kapalı'),
        ('İade politikası', e.refundPolicy),
        ('Düzenleyen', '${e.organizerName} • ${e.organizerContact}'),
      ],
    );
  }
}

class EventFormDialog extends ConsumerStatefulWidget {
  const EventFormDialog({super.key, this.initial});

  final ClubEvent? initial;

  @override
  ConsumerState<EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends ConsumerState<EventFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _program;
  late final TextEditingController _location;
  late final TextEditingController _fee;
  late final TextEditingController _capacity;
  late final TextEditingController _refundPolicy;
  late final TextEditingController _organizerName;
  late final TextEditingController _organizerContact;
  late EventStatus _status;
  late bool _waitlist;
  DateTime? _startsAt;
  DateTime? _endsAt;
  DateTime? _deadline;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _title = TextEditingController(text: e?.title ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _program = TextEditingController(text: e?.program ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _fee = TextEditingController(text: e == null ? '0' : moneyInput(e.feeMinor));
    _capacity = TextEditingController(text: e == null ? '' : '${e.capacity}');
    _refundPolicy = TextEditingController(text: e?.refundPolicy ?? '');
    _organizerName = TextEditingController(text: e?.organizerName ?? '');
    _organizerContact = TextEditingController(text: e?.organizerContact ?? '');
    _status = e?.status ?? EventStatus.draft;
    _waitlist = e?.waitlistEnabled ?? false;
    _startsAt = e?.startsAt;
    _endsAt = e?.endsAt;
    _deadline = e?.registrationDeadline;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _program,
      _location,
      _fee,
      _capacity,
      _refundPolicy,
      _organizerName,
      _organizerContact,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final startsAt = _startsAt;
    final deadline = _deadline;
    final fee = Money.tryParseTr(_fee.text);
    final capacity = int.tryParse(_capacity.text.trim());
    if (startsAt == null || deadline == null || fee == null || capacity == null) {
      return;
    }
    final endsAt = _endsAt;
    final old = widget.initial;

    // Alanlar arası kurallar.
    String? problem;
    if (deadline.isAfter(startsAt)) {
      problem = 'Son kayıt zamanı etkinlik başlangıcından sonra olamaz.';
    } else if (endsAt != null && endsAt.isBefore(startsAt)) {
      problem = 'Bitiş zamanı başlangıçtan önce olamaz.';
    } else if (old != null &&
        capacity < old.confirmedCount + old.reservedCount) {
      problem = 'Kontenjan, onaylı ve rezerve kayıt toplamının '
          '(${old.confirmedCount + old.reservedCount}) altına düşürülemez.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final now = ref.read(adminClockProvider)();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Sayaçlar (reservedCount/confirmedCount) istemciden yazılmaz; gerçek depo
      // bu alanları göndermez.
      await ref.read(adminRepositoryProvider).saveEvent(
            ClubEvent(
              id: old?.id ?? '',
              title: _title.text.trim(),
              description: _description.text.trim(),
              program: _program.text.trim().isEmpty ? null : _program.text.trim(),
              location: _location.text.trim(),
              startsAt: startsAt,
              endsAt: endsAt,
              registrationDeadline: deadline,
              feeMinor: fee.minor,
              currency: old?.currency ?? 'TRY',
              capacity: capacity,
              reservedCount: old?.reservedCount ?? 0,
              confirmedCount: old?.confirmedCount ?? 0,
              waitlistEnabled: _waitlist,
              status: _status,
              donationCampaignId: old?.donationCampaignId,
              refundPolicy: _refundPolicy.text.trim(),
              organizerName: _organizerName.text.trim(),
              organizerContact: _organizerContact.text.trim(),
              createdAt: old?.createdAt ?? now,
            ),
          );
      ref.invalidate(eventsProvider);
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
    final old = widget.initial;
    return DialogShell(
      title: old == null ? 'Yeni etkinlik' : 'Etkinliği düzenle',
      maxWidth: 640,
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
                controller: _program,
                decoration: fieldDecoration('Program (isteğe bağlı)'),
                maxLines: 3,
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _location,
                decoration: fieldDecoration('Yer'),
                validator: requiredText(min: 2, max: 200),
              ),
            ),
            fieldPad(
              DateFormField(
                label: 'Başlangıç',
                withTime: true,
                initialValue: _startsAt,
                onChanged: (v) => _startsAt = v,
              ),
            ),
            fieldPad(
              DateFormField(
                label: 'Bitiş (isteğe bağlı)',
                withTime: true,
                isRequired: false,
                initialValue: _endsAt,
                onChanged: (v) => _endsAt = v,
              ),
            ),
            fieldPad(
              DateFormField(
                label: 'Son kayıt zamanı',
                withTime: true,
                initialValue: _deadline,
                onChanged: (v) => _deadline = v,
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _fee,
                decoration: fieldDecoration('Ücret (₺)', helper: '0 = ücretsiz'),
                keyboardType: TextInputType.number,
                validator: moneyValidator(allowZero: true),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _capacity,
                decoration: old == null
                    ? fieldDecoration('Kontenjan')
                    : fieldDecoration(
                        'Kontenjan',
                        helper: 'Onaylı: ${old.confirmedCount}, '
                            'rezerve: ${old.reservedCount}',
                      ),
                keyboardType: TextInputType.number,
                validator: positiveInt,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bekleme listesi açık'),
              value: _waitlist,
              onChanged: (v) => setState(() => _waitlist = v),
            ),
            fieldPad(
              EnumDropdown<EventStatus>(
                label: 'Durum',
                value: _status,
                values: EventStatus.values,
                labelOf: (v) => v.label,
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _refundPolicy,
                decoration: fieldDecoration('İade politikası'),
                maxLines: 2,
                validator: requiredText(min: 3, max: 1000),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _organizerName,
                decoration: fieldDecoration('Düzenleyen'),
                validator: requiredText(min: 2, max: 120),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _organizerContact,
                decoration: fieldDecoration('Düzenleyen iletişim'),
                validator: requiredText(min: 3, max: 200),
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
