import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/admin_exception.dart';
import '../../core/labels.dart';
import '../../core/role_provider.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/admin_table.dart';
import '../../ui/form_kit.dart';
import '../../ui/page_frame.dart';

/// Rol ve izinler: kullanıcıya rol atama (`assignRole`, yalnızca sistem
/// yöneticisi). "Kulüp üyesi" rolü üyelik onayıyla verilir; buradan atanmaz.
class RolesPage extends ConsumerWidget {
  const RolesPage({super.key});

  /// Elle atanabilen roller (club_member üyelik onayıyla gelir).
  static const List<AppRole> assignable = [
    AppRole.registeredUser,
    AppRole.contentManager,
    AppRole.financeManager,
    AppRole.systemAdmin,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(adminRoleProvider).can(Permission.manageRoles);
    final async = ref.watch(usersProvider);
    return AdminPageFrame(
      title: 'Rol ve İzinler',
      subtitle: 'Rol değişiklikleri denetim kaydına yazılır. Kulüp üyesi rolü '
          'üyelik onayıyla verilir.',
      child: AsyncBody<List<AppUserRow>>(
        value: async,
        onRetry: () => ref.invalidate(usersProvider),
        builder: (rows) => AdminTable<AppUserRow>(
          rows: rows,
          emptyMessage: 'Kullanıcı yok.',
          searchText: (u) => '${u.name} ${u.role.labelTr}',
          onRowTap: canManage
              ? (u) => showDialog<bool>(
                    context: context,
                    builder: (_) => AssignRoleDialog(user: u),
                  )
              : null,
          filters: [
            TableFilter<AppUserRow>(
              label: 'Rol',
              options: [
                for (final r in AppRole.values)
                  if (r != AppRole.visitor)
                    FilterOption<AppUserRow>(r.labelTr, (u) => u.role == r),
              ],
            ),
          ],
          columns: [
            AdminColumn<AppUserRow>(
              label: 'Ad',
              text: (u) => u.name,
              compare: (a, b) => a.name.compareTo(b.name),
            ),
            AdminColumn<AppUserRow>(label: 'Rol', text: (u) => u.role.labelTr),
          ],
        ),
      ),
    );
  }
}

class AssignRoleDialog extends ConsumerStatefulWidget {
  const AssignRoleDialog({super.key, required this.user});

  final AppUserRow user;

  @override
  ConsumerState<AssignRoleDialog> createState() => _AssignRoleDialogState();
}

class _AssignRoleDialogState extends ConsumerState<AssignRoleDialog> {
  late AppRole _role;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.user.role;
    _role = RolesPage.assignable.contains(current)
        ? current
        : AppRole.registeredUser;
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).assignRole(widget.user.id, _role);
      ref
        ..invalidate(usersProvider)
        ..invalidate(auditLogsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rol güncellendi.')),
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
      title: 'Rol ata',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fieldPad(Text('${widget.user.name} • Mevcut rol: ${widget.user.role.labelTr}')),
          fieldPad(
            EnumDropdown<AppRole>(
              label: 'Yeni rol',
              value: _role,
              values: RolesPage.assignable,
              labelOf: (r) => r.labelTr,
              onChanged: (r) => setState(() => _role = r),
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(color: Color(BrandColors.error)),
            ),
        ],
      ),
    );
  }
}
