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

/// Kulüp üyeleri: üyelik talebi onayı ve üyeliği sonlandırma
/// (yalnızca sistem yöneticisi; `manageRoles`).
class MembersPage extends ConsumerWidget {
  const MembersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(adminRoleProvider).can(Permission.manageRoles);
    final async = ref.watch(clubMembersProvider);
    return AdminPageFrame(
      title: 'Kullanıcı ve Üyeler',
      subtitle: 'Kayıt olmak üye olmak değildir; üyelik yönetici onayıyla başlar.',
      child: AsyncBody<List<ClubMember>>(
        value: async,
        onRetry: () => ref.invalidate(clubMembersProvider),
        builder: (rows) => AdminTable<ClubMember>(
          rows: rows,
          emptyMessage: 'Henüz üyelik kaydı yok.',
          searchText: (m) => '${m.userName} ${m.memberNo ?? ''} ${m.status.label}',
          dateOf: (m) => m.requestedAt,
          dateLabel: 'Talep tarihi',
          onRowTap: (m) => _detail(context, m, canManage),
          filters: [
            TableFilter<ClubMember>(
              label: 'Durum',
              options: [
                for (final s in MemberStatus.values)
                  FilterOption<ClubMember>(s.label, (m) => m.status == s),
              ],
            ),
          ],
          columns: [
            AdminColumn<ClubMember>(
              label: 'Ad',
              text: (m) => m.userName,
              compare: (a, b) => a.userName.compareTo(b.userName),
            ),
            AdminColumn<ClubMember>(label: 'Üye no', text: (m) => m.memberNo ?? '—'),
            AdminColumn<ClubMember>(
              label: 'Durum',
              text: (m) => m.status.label,
              cell: (_, m) => StatusChip(label: m.status.label, tone: m.status.tone),
            ),
            AdminColumn<ClubMember>(
              label: 'Talep',
              text: (m) => formatDate(m.requestedAt),
              compare: (a, b) => a.requestedAt.compareTo(b.requestedAt),
            ),
            AdminColumn<ClubMember>(
              label: 'Üyelik başlangıcı',
              text: (m) => formatDate(m.joinedAt),
            ),
          ],
        ),
      ),
    );
  }

  void _detail(BuildContext context, ClubMember m, bool canManage) {
    showDetailDialog(
      context,
      title: m.userName,
      rows: [
        ('Durum', m.status.label),
        ('Üye no', m.memberNo ?? '—'),
        ('Talep', formatDateTime(m.requestedAt)),
        ('Üyelik başlangıcı', formatDateTime(m.joinedAt)),
      ],
      actionsBuilder: (dialogContext) => [
        if (canManage && m.status == MemberStatus.pending)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              showDialog<bool>(
                context: context,
                builder: (_) => ApproveMemberDialog(member: m),
              );
            },
            icon: const Icon(Icons.check),
            label: const Text('Onayla'),
          ),
        if (canManage && m.status == MemberStatus.active) ...[
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _confirmEnd(context, m, MemberStatus.suspended);
            },
            child: const Text('Askıya al'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _confirmEnd(context, m, MemberStatus.resigned);
            },
            child: const Text('İstifa olarak kapat'),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmEnd(
    BuildContext context,
    ClubMember m,
    MemberStatus to,
  ) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _EndMembershipDialog(member: m, to: to),
    );
  }
}

class ApproveMemberDialog extends ConsumerStatefulWidget {
  const ApproveMemberDialog({super.key, required this.member});

  final ClubMember member;

  @override
  ConsumerState<ApproveMemberDialog> createState() =>
      _ApproveMemberDialogState();
}

class _ApproveMemberDialogState extends ConsumerState<ApproveMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _memberNo = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _memberNo.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .approveMembership(widget.member.id, _memberNo.text.trim());
      ref
        ..invalidate(clubMembersProvider)
        ..invalidate(usersProvider)
        ..invalidate(auditLogsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Üyelik onaylandı.')),
        );
      }
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
      title: 'Üyeliği onayla',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Onaylanıyor…' : 'Onayla'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fieldPad(Text(widget.member.userName)),
            fieldPad(
              TextFormField(
                controller: _memberNo,
                decoration: fieldDecoration('Üye numarası', helper: 'Örn. ÜY-0007'),
                validator: requiredText(min: 2, max: 30),
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

class _EndMembershipDialog extends ConsumerStatefulWidget {
  const _EndMembershipDialog({required this.member, required this.to});

  final ClubMember member;
  final MemberStatus to;

  @override
  ConsumerState<_EndMembershipDialog> createState() =>
      _EndMembershipDialogState();
}

class _EndMembershipDialogState extends ConsumerState<_EndMembershipDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .endMembership(widget.member.id, widget.to);
      ref
        ..invalidate(clubMembersProvider)
        ..invalidate(usersProvider)
        ..invalidate(auditLogsProvider);
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
    final label =
        widget.to == MemberStatus.suspended ? 'askıya alınacak' : 'istifa olarak kapatılacak';
    return DialogShell(
      title: 'Üyeliği sonlandır',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'İşleniyor…' : 'Onayla'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.member.userName} üyeliği $label. '
              'Kulüp üyesi yetkileri kalkar; yönetici rolü korunur.'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(BrandColors.error)),
              ),
            ),
        ],
      ),
    );
  }
}
