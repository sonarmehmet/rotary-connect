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
import '../payments/manual_payment_dialog.dart';

/// Aidat dönemleri ve borçlar. Borç atama/manuel ödeme yetkisi: finans.
/// Tutar ve dönemler kodda sabit değildir; buradan atanır.
class DuesPage extends ConsumerWidget {
  const DuesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(adminRoleProvider);
    final canAssign = role.can(Permission.manageDuesAndCollections);
    final canRecord = role.can(Permission.recordManualPayment);
    final async = ref.watch(duesProvider);
    return AdminPageFrame(
      title: 'Aidat ve Tahsilatlar',
      subtitle: 'Borçlar sunucuda atanır; durumlar ödemelerle güncellenir.',
      actions: [
        if (canAssign)
          FilledButton.icon(
            onPressed: () => _assign(context),
            icon: const Icon(Icons.add),
            label: const Text('Aidat borcu ata'),
          ),
      ],
      child: AsyncBody<List<MembershipDue>>(
        value: async,
        onRetry: () => ref.invalidate(duesProvider),
        builder: (rows) => AdminTable<MembershipDue>(
          rows: rows,
          emptyMessage: 'Henüz aidat borcu atanmamış.',
          searchText: (d) => '${d.userName} ${d.periodLabel} ${d.status.label}',
          dateOf: (d) => d.dueDate,
          dateLabel: 'Vade tarihi',
          onRowTap: (d) => _detail(context, ref, d, canRecord, canAssign),
          filters: [
            TableFilter<MembershipDue>(
              label: 'Durum',
              options: [
                for (final s in DueStatus.values)
                  FilterOption<MembershipDue>(s.label, (d) => d.status == s),
              ],
            ),
            TableFilter<MembershipDue>(
              label: 'Dönem',
              options: [
                for (final p
                    in (rows.map((d) => d.periodLabel).toSet().toList()..sort()))
                  FilterOption<MembershipDue>(p, (d) => d.periodLabel == p),
              ],
            ),
          ],
          columns: [
            AdminColumn<MembershipDue>(
              label: 'Üye',
              text: (d) => d.userName,
              compare: (a, b) => a.userName.compareTo(b.userName),
            ),
            AdminColumn<MembershipDue>(label: 'Dönem', text: (d) => d.periodLabel),
            AdminColumn<MembershipDue>(
              label: 'Tutar',
              numeric: true,
              text: (d) => moneyText(d.amountMinor, currency: d.currency),
              compare: (a, b) => a.amountMinor.compareTo(b.amountMinor),
            ),
            AdminColumn<MembershipDue>(
              label: 'Ödenen',
              numeric: true,
              text: (d) => moneyText(d.paidMinor, currency: d.currency),
              compare: (a, b) => a.paidMinor.compareTo(b.paidMinor),
            ),
            AdminColumn<MembershipDue>(
              label: 'Kalan',
              numeric: true,
              text: (d) => moneyText(d.remainingMinor, currency: d.currency),
              compare: (a, b) => a.remainingMinor.compareTo(b.remainingMinor),
            ),
            AdminColumn<MembershipDue>(
              label: 'Vade',
              text: (d) => formatDate(d.dueDate),
              compare: (a, b) => a.dueDate.compareTo(b.dueDate),
            ),
            AdminColumn<MembershipDue>(
              label: 'Durum',
              text: (d) => d.status.label,
              cell: (_, d) => StatusChip(label: d.status.label, tone: d.status.tone),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign(BuildContext context) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const AssignDuesDialog(),
    );
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aidat borçları atandı.')),
      );
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    MembershipDue d,
  ) async {
    final reason = TextEditingController();
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Borcu iptal et'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${d.userName} — ${d.periodLabel} borcu iptal edilecek. '
                  'Ödemesi alınmış borç iptal edilemez; önce iade edin.'),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLines: 2,
                decoration: fieldDecoration('Gerekçe'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(adminRepositoryProvider)
                      .cancelDue(d.id, reason.text);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }
                } catch (e) {
                  setState(() => error = errorMessageTr(e));
                }
              },
              child: const Text('Borcu iptal et'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (done == true) {
      ref.invalidate(duesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Borç iptal edildi.')),
        );
      }
    }
  }

  void _detail(
    BuildContext context,
    WidgetRef ref,
    MembershipDue d,
    bool canRecord,
    bool canCancel,
  ) {
    final open = d.status == DueStatus.unpaid ||
        d.status == DueStatus.partiallyPaid ||
        d.status == DueStatus.overdue;
    showDetailDialog(
      context,
      title: '${d.userName} — ${d.periodLabel}',
      rows: [
        ('Durum', d.status.label),
        ('Tutar', moneyText(d.amountMinor, currency: d.currency)),
        ('Ödenen', moneyText(d.paidMinor, currency: d.currency)),
        ('Kalan', moneyText(d.remainingMinor, currency: d.currency)),
        ('Vade', formatDate(d.dueDate)),
        ('Kısmi ödeme', d.allowPartial ? 'İzinli' : 'Kapalı'),
      ],
      actionsBuilder: (dialogContext) => [
        if (canRecord && open)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              showDialog<bool>(
                context: context,
                builder: (_) => ManualPaymentDialog(
                  kind: PaymentKind.membershipDue,
                  refId: d.id,
                  userId: d.userId,
                  refLabel: '${d.userName} — ${d.periodLabel}',
                  suggestedMinor: d.remainingMinor,
                  maxMinor: d.remainingMinor,
                ),
              );
            },
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Manuel ödeme kaydet'),
          ),
        if (canCancel && open && d.paidMinor == 0)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _cancel(context, ref, d);
            },
            icon: const Icon(Icons.block),
            label: const Text('Borcu iptal et'),
          ),
      ],
    );
  }
}

/// Dönem için borç atama (`createDue` / `assignDues`).
class AssignDuesDialog extends ConsumerStatefulWidget {
  const AssignDuesDialog({super.key});

  @override
  ConsumerState<AssignDuesDialog> createState() => _AssignDuesDialogState();
}

class _AssignDuesDialogState extends ConsumerState<AssignDuesDialog> {
  final _formKey = GlobalKey<FormState>();
  final _period = TextEditingController();
  final _amount = TextEditingController();
  DateTime? _dueDate;
  bool _allowPartial = false;
  bool _allMembers = true;
  String? _memberId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _period.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = Money.tryParseTr(_amount.text);
    final due = _dueDate;
    if (amount == null || due == null) return;
    if (!_allMembers && _memberId == null) {
      setState(() => _error = 'Bir üye seçin.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).createDues(
            NewDuesRequest(
              periodLabel: _period.text.trim(),
              amountMinor: amount.minor,
              dueDate: due,
              allowPartial: _allowPartial,
              memberId: _allMembers ? null : _memberId,
            ),
          );
      invalidateFinance(ref);
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
    final members = ref.watch(membersProvider).valueOrNull ?? const [];
    return DialogShell(
      title: 'Aidat borcu ata',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Atanıyor…' : 'Ata'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fieldPad(
              TextFormField(
                controller: _period,
                decoration: fieldDecoration('Dönem', helper: 'Örn. 2027-2028'),
                validator: requiredText(min: 3, max: 40),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _amount,
                decoration: fieldDecoration('Tutar (₺)', helper: 'Örn. 1.200'),
                keyboardType: TextInputType.number,
                validator: moneyValidator(),
              ),
            ),
            fieldPad(
              DateFormField(
                label: 'Vade tarihi',
                initialValue: _dueDate,
                onChanged: (v) => _dueDate = v,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kısmi ödemeye izin ver'),
              value: _allowPartial,
              onChanged: (v) => setState(() => _allowPartial = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tüm aktif üyelere ata'),
              value: _allMembers,
              onChanged: (v) => setState(() => _allMembers = v),
            ),
            if (!_allMembers)
              fieldPad(
                DropdownMenu<String>(
                  label: const Text('Üye'),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (final m in members)
                      DropdownMenuEntry<String>(
                        value: m.id,
                        label: '${m.name} (${m.memberNo})',
                      ),
                  ],
                  onSelected: (v) => setState(() => _memberId = v),
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
