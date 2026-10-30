import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/admin_exception.dart';
import '../../core/format.dart';
import '../../core/role_provider.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/form_kit.dart';
import '../../ui/page_frame.dart';
import '../../ui/state_views.dart';

/// "250; 500; 1.000" biçimindeki noktalı virgülle ayrılmış TAM lira girdisini
/// kuruşa çevirir (virgül ondalık ayraçtır; ondalıklı tutar kabul edilmez).
/// Geçersizse `null`.
List<int>? parseQuickAmounts(String input) {
  final parts = input
      .split(';')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  final out = <int>[];
  for (final p in parts) {
    final money = Money.tryParseTr(p);
    if (money == null || money.minor % 100 != 0) return null;
    out.add(money.minor);
  }
  return out;
}

/// Uygulama ayarları (yalnızca sistem yöneticisi: `manageSettings`).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(adminRoleProvider).can(Permission.manageSettings)) {
      return const NoAccessView();
    }
    final async = ref.watch(settingsProvider);
    return AdminPageFrame(
      title: 'Uygulama Ayarları',
      subtitle: 'Değişiklikler denetim kaydına yazılır.',
      child: AsyncBody<AppSettings>(
        value: async,
        onRetry: () => ref.invalidate(settingsProvider),
        builder: (settings) => _SettingsForm(initial: settings),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial});

  final AppSettings initial;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _clubName;
  late final TextEditingController _contact;
  late final TextEditingController _reservation;
  late final TextEditingController _amounts;
  late bool _partial;
  late bool _recurring;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _clubName = TextEditingController(text: s.clubName);
    _contact = TextEditingController(text: s.contact);
    _reservation = TextEditingController(text: '${s.reservationMinutes}');
    _amounts = TextEditingController(
      text: s.donationQuickAmountsMinor
          .map((m) => moneyInput(m).replaceAll(',00', ''))
          .join('; '),
    );
    _partial = s.partialDuesEnabled;
    _recurring = s.recurringDonationEnabled;
  }

  @override
  void dispose() {
    _clubName.dispose();
    _contact.dispose();
    _reservation.dispose();
    _amounts.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amounts = parseQuickAmounts(_amounts.text);
    final minutes = int.tryParse(_reservation.text.trim());
    if (amounts == null || minutes == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveSettings(
            widget.initial.copyWith(
              clubName: _clubName.text,
              contact: _contact.text,
              reservationMinutes: minutes,
              donationQuickAmountsMinor: amounts,
              partialDuesEnabled: _partial,
              recurringDonationEnabled: _recurring,
            ),
          );
      ref
        ..invalidate(settingsProvider)
        ..invalidate(auditLogsProvider);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayarlar kaydedildi.')),
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
    final live = widget.initial.paymentMode == 'live';
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
                  TextFormField(
                    controller: _clubName,
                    decoration: fieldDecoration('Kulüp adı'),
                    validator: requiredText(min: 2, max: 120),
                  ),
                ),
                fieldPad(
                  TextFormField(
                    controller: _contact,
                    decoration: fieldDecoration('İletişim'),
                    validator: requiredText(min: 3, max: 200),
                  ),
                ),
                fieldPad(
                  TextFormField(
                    controller: _reservation,
                    decoration: fieldDecoration(
                      'Etkinlik rezervasyon süresi (dakika)',
                      helper: '5 – 120; öneri 15',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 5 || n > 120) {
                        return '5 ile 120 arasında bir sayı girin';
                      }
                      return null;
                    },
                  ),
                ),
                fieldPad(
                  TextFormField(
                    controller: _amounts,
                    decoration: fieldDecoration(
                      'Hızlı bağış tutarları (₺)',
                      helper: 'Noktalı virgülle ayırın: 250; 500; 1.000; 2.500',
                    ),
                    validator: (v) {
                      final list = parseQuickAmounts(v ?? '');
                      if (list == null) return 'Tam lira tutarları girin';
                      if (list.length > 6) return 'En çok 6 tutar';
                      if (list.any((a) => a < 100)) return 'Her tutar en az 1 ₺';
                      if (list.toSet().length != list.length) {
                        return 'Tutarlar tekrar edemez';
                      }
                      return null;
                    },
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kısmi aidat ödemesine izin ver'),
                  value: _partial,
                  onChanged: (v) => setState(() => _partial = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Düzenli bağış'),
                  subtitle: const Text('Varsayılan: kapalı'),
                  value: _recurring,
                  onChanged: (v) => setState(() => _recurring = v),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    live ? Icons.bolt_outlined : Icons.science_outlined,
                    color: Color(live ? BrandColors.success : BrandColors.warning),
                  ),
                  title: Text('Ödeme modu: ${live ? 'Canlı' : 'Simülasyon'}'),
                  subtitle: const Text(
                    'Bu ayar panelden değiştirilemez. Canlıya geçiş, ödeme '
                    'sağlayıcısı seçildikten ve entegrasyon doğrulandıktan '
                    'sonra sunucu tarafında yapılır.',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(BrandColors.error)),
                    ),
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
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
