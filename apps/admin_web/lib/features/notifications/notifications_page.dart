import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/admin_exception.dart';
import '../../core/labels.dart';
import '../../core/role_provider.dart';
import '../../core/sensitive.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/form_kit.dart';
import '../../ui/page_frame.dart';
import '../../ui/state_views.dart';

/// Hedef rol seçenekleri (sunucuda `visitor` hariç tüm roller geçerlidir).
const List<AppRole> announceRoles = [
  AppRole.registeredUser,
  AppRole.clubMember,
  AppRole.contentManager,
  AppRole.financeManager,
  AppRole.systemAdmin,
];

/// Duyuru işlem anahtarı (8-64, [A-Za-z0-9_-]).
String newClientKey() {
  final rnd = Random.secure();
  final suffix = rnd.nextInt(1 << 32).toRadixString(36);
  return 'ann_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$suffix';
}

/// Bildirimler: panelden duyuru/bildirim gönderimi (`sendAnnouncement`).
/// Yetki: içerik yöneticisi veya sistem yöneticisi (`manageContent`).
/// Metinde tutar, e-posta, telefon gibi kişisel/finansal bilgi bulunamaz.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(adminRoleProvider).can(Permission.manageContent)) {
      return const NoAccessView();
    }
    return const AdminPageFrame(
      title: 'Bildirimler',
      subtitle: 'Duyuru, kullanıcıların bildirim tercihlerine göre iletilir. '
          'Metne tutar, e-posta veya telefon yazmayın.',
      child: _AnnouncementForm(),
    );
  }
}

class _AnnouncementForm extends ConsumerStatefulWidget {
  const _AnnouncementForm();

  @override
  ConsumerState<_AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends ConsumerState<_AnnouncementForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  AnnouncementAudience _audience = AnnouncementAudience.all;
  AppRole _role = AppRole.clubMember;
  AnnouncementRoute _route = AnnouncementRoute.news;
  String _clientKey = newClientKey();
  bool _sending = false;
  String? _error;
  AnnouncementResult? _result;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  String get _audienceLabel => _audience == AnnouncementAudience.role
      ? 'Rol: ${_role.labelTr}'
      : _audience.label;

  Future<void> _submit() async {
    if (_sending) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => DialogShell(
        title: 'Duyuruyu gönder',
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Gönder'),
          ),
        ],
        child: Text(
          'Hedef: $_audienceLabel\n\n"${_title.text.trim()}"\n\n'
          'Gönderim geri alınamaz.',
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref.read(adminRepositoryProvider).sendAnnouncement(
            AnnouncementRequest(
              audience: _audience,
              role: _audience == AnnouncementAudience.role ? _role : null,
              title: _title.text.trim(),
              body: _body.text.trim(),
              route: _route,
              clientKey: _clientKey,
            ),
          );
      ref.invalidate(auditLogsProvider);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _result = result;
        // Başarılı gönderimden sonra yeni anahtar: yeni içerik yeni bildirimdir.
        // Hata/zaman aşımında anahtar KORUNUR: yeniden deneme çift gönderim yapmaz.
        _clientKey = newClientKey();
        _title.clear();
        _body.clear();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = errorMessageTr(e);
        });
      }
    }
  }

  String? _sensitiveCheck(String? v) {
    final base = requiredText(min: 3, max: 10000)(v);
    if (base != null) return base;
    if (containsSensitive(v!)) {
      return 'Tutar, e-posta veya telefon gibi bilgi içeremez';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fieldPad(
                  EnumDropdown<AnnouncementAudience>(
                    label: 'Hedef kitle',
                    value: _audience,
                    values: AnnouncementAudience.values,
                    labelOf: (v) => v.label,
                    onChanged: (v) => setState(() => _audience = v),
                  ),
                ),
                if (_audience == AnnouncementAudience.role)
                  fieldPad(
                    EnumDropdown<AppRole>(
                      label: 'Rol',
                      value: _role,
                      values: announceRoles,
                      labelOf: (r) => r.labelTr,
                      onChanged: (r) => setState(() => _role = r),
                    ),
                  ),
                fieldPad(
                  TextFormField(
                    controller: _title,
                    maxLength: 80,
                    decoration: fieldDecoration('Başlık'),
                    validator: (v) {
                      final e = _sensitiveCheck(v);
                      if (e != null) return e;
                      return v!.trim().length > 80 ? 'En çok 80 karakter' : null;
                    },
                  ),
                ),
                fieldPad(
                  TextFormField(
                    controller: _body,
                    maxLength: 300,
                    maxLines: 4,
                    decoration: fieldDecoration('Metin'),
                    validator: (v) {
                      final e = _sensitiveCheck(v);
                      if (e != null) return e;
                      return v!.trim().length > 300 ? 'En çok 300 karakter' : null;
                    },
                  ),
                ),
                fieldPad(
                  EnumDropdown<AnnouncementRoute>(
                    label: 'Dokununca açılacak sayfa',
                    value: _route,
                    values: AnnouncementRoute.values,
                    labelOf: (r) => r.label,
                    onChanged: (r) => setState(() => _route = r),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(BrandColors.error)),
                    ),
                  ),
                if (result != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Gönderildi: ${result.sent} / ${result.recipients} alıcı'
                          '${result.skippedByPreferences > 0 ? ' (${result.skippedByPreferences} kişi bildirimi kapatmış)' : ''}.',
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _submit,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(_sending ? 'Gönderiliyor…' : 'Gönder'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
