import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart';
import '../../../data/validators.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/test_data_banner.dart';

class DonateScreen extends ConsumerStatefulWidget {
  const DonateScreen({super.key});
  @override
  ConsumerState<DonateScreen> createState() => _DonateScreenState();
}

class _DonateScreenState extends ConsumerState<DonateScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  String? _campaignId;
  bool _anonymous = false;
  bool _busy = false;
  // Aynı form oturumunda çift dokunuşu aynı ödemeye bağlar.
  String _clientKey = 'k${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final res = await ref.read(repositoryProvider).donate(DonationRequest(
            campaignId: _campaignId,
            amount: Money.tryParseTr(_amount.text)!,
            donorName: _name.text.trim(),
            donorEmail: _email.text.trim(),
            anonymous: _anonymous,
            clientKey: _clientKey,
          ));
      if (!mounted) return;
      final url = res.checkoutUrl;
      if (res.pending && url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(res.succeeded ? 'Teşekkürler!' : 'Ödeme bekleniyor'),
          content: Text(res.succeeded
              ? (res.simulated ? 'Bu bir SİMÜLASYON bağışıdır; gerçek tahsilat yapılmadı.' : 'Bağışınız alındı.')
              : (url != null
                  ? 'Ödeme sayfası açıldı. Ödeme tamamlanınca bağışınız onaylanır ve bildirim alırsınız.'
                  : 'Bağışınız kaydedildi; ödeme sonucu bekleniyor. Simülasyon modunda sonuç yönetici tarafından verilir.')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
        ),
      );
      if (res.succeeded || res.pending) {
        _amount.clear();
        _clientKey = 'k${DateTime.now().microsecondsSinceEpoch}';
        ref.invalidate(campaignsProvider);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağış başlatılamadı. Tekrar deneyin.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = ref.watch(campaignsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bağış Yap')),
      body: Column(children: [
        const TestDataBanner(),
        Expanded(
          child: AsyncView<List<Campaign>>(
            value: campaigns,
            onRetry: () => ref.invalidate(campaignsProvider),
            isEmpty: (_) => false,
            builder: (list) => ListView(padding: const EdgeInsets.all(Gaps.md), children: [
              for (final c in list.where((c) => c.active)) _CampaignCard(c: c, selected: _campaignId == c.id, onTap: () => setState(() => _campaignId = _campaignId == c.id ? null : c.id)),
              const SizedBox(height: Gaps.md),
              Form(
                key: _form,
                child: Column(children: [
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Tutar (₺)', helperText: 'En az 10 ₺'),
                    validator: (v) => Validators.amount(v),
                  ),
                  Wrap(spacing: Gaps.sm, children: [
                    for (final t in const [100, 250, 500, 1000])
                      ActionChip(label: Text('$t ₺'), onPressed: () => _amount.text = '$t'),
                  ]),
                  TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Ad Soyad'), validator: (v) => Validators.required(v, 'Ad soyad')),
                  TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta'), validator: Validators.email),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Bağışım anonim görünsün'), value: _anonymous, onChanged: (v) => setState(() => _anonymous = v)),
                  const SizedBox(height: Gaps.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'İşleniyor…' : 'Bağış Yap')),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.c, required this.selected, required this.onTap});
  final Campaign c;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        shape: selected ? RoundedRectangleBorder(side: const BorderSide(color: AppTheme.gold, width: 2), borderRadius: BorderRadius.circular(12)) : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gaps.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Gaps.xs),
              Text(c.description),
              const SizedBox(height: Gaps.sm),
              LinearProgressIndicator(value: c.progress),
              const SizedBox(height: Gaps.xs),
              Text('${c.verifiedTotal.format()} / ${c.goal.format()}'),
            ]),
          ),
        ),
      );
}
