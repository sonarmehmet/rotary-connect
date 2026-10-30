import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/admin_exception.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/form_kit.dart';

/// İade başlatma (`issueRefund`). Toplam iade ≤ orijinal tutar; kesin kural
/// sunucudadır, burada yalnızca erken uyarı verilir.
class RefundDialog extends ConsumerStatefulWidget {
  const RefundDialog({super.key, required this.payment});

  final PaymentRecord payment;

  @override
  ConsumerState<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends ConsumerState<RefundDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: moneyInput(widget.payment.refundableMinor),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = Money.tryParseTr(_amount.text);
    if (amount == null) return;
    final max = widget.payment.refundableMinor;
    if (amount.minor > max) {
      setState(() => _error =
          'İade tutarı iade edilebilir kalan tutarı (${moneyText(max)}) aşamaz.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).issueRefund(
            RefundRequest(
              paymentId: widget.payment.id,
              amountMinor: amount.minor,
              reason: _reason.text.trim(),
            ),
          );
      invalidateFinance(ref);
      ref.invalidate(campaignsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İade kaydedildi.')),
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
    final p = widget.payment;
    return DialogShell(
      title: 'İade başlat',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'İşleniyor…' : 'İadeyi onayla'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fieldPad(
              Text(
                '${p.kind.labelTr} ödemesi ${p.id} • '
                'Tutar: ${moneyText(p.amountMinor, currency: p.currency)} • '
                'İade edilebilir: ${moneyText(p.refundableMinor, currency: p.currency)}',
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _amount,
                decoration: fieldDecoration('İade tutarı (₺)'),
                keyboardType: TextInputType.number,
                validator: moneyValidator(),
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _reason,
                decoration: fieldDecoration('Gerekçe'),
                maxLines: 2,
                validator: requiredText(min: 3, max: 300),
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
