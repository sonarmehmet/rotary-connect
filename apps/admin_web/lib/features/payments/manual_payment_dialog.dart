import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

import '../../core/admin_exception.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../ui/form_kit.dart';

/// Manuel ödeme kaydı (`recordManualPayment`). Form açılırken bir
/// `idempotencyKey` üretilir; çift tıklama / yeniden deneme mükerrer kayıt
/// oluşturmaz (sunucu `already-exists` döner).
class ManualPaymentDialog extends ConsumerStatefulWidget {
  const ManualPaymentDialog({
    super.key,
    required this.kind,
    required this.refId,
    required this.refLabel,
    this.suggestedMinor,
    this.maxMinor,
    this.userId,
  });

  final PaymentKind kind;
  final String refId;
  final String refLabel;
  final int? suggestedMinor;

  /// Verilirse istemci bu tutarı aşan girişi uyarır (kesin kural sunucudadır).
  final int? maxMinor;

  /// Ödemenin ait olduğu kullanıcı (aidat borcunda borçlu üye).
  final String? userId;

  @override
  ConsumerState<ManualPaymentDialog> createState() =>
      _ManualPaymentDialogState();
}

class _ManualPaymentDialogState extends ConsumerState<ManualPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _note = TextEditingController();
  DateTime? _receivedAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.suggestedMinor == null ? '' : moneyInput(widget.suggestedMinor!),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = Money.tryParseTr(_amount.text);
    final received = _receivedAt;
    if (amount == null || received == null) return;
    final max = widget.maxMinor;
    if (max != null && amount.minor > max) {
      setState(() => _error = 'Tutar kalan borcu (${moneyText(max)}) aşamaz.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).recordManualPayment(
            ManualPaymentRequest(
              kind: widget.kind,
              refId: widget.refId,
              amountMinor: amount.minor,
              note: _note.text.trim(),
              receivedAt: received,
              userId: widget.userId,
            ),
          );
      invalidateFinance(ref);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manuel ödeme kaydedildi.')),
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
      title: 'Manuel ödeme kaydet',
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
            fieldPad(Text('Kayıt: ${widget.refLabel}')),
            fieldPad(
              TextFormField(
                controller: _amount,
                decoration: fieldDecoration('Tutar (₺)'),
                keyboardType: TextInputType.number,
                validator: moneyValidator(),
              ),
            ),
            fieldPad(
              DateFormField(
                label: 'Paranın alındığı tarih',
                initialValue: _receivedAt,
                onChanged: (v) => _receivedAt = v,
              ),
            ),
            fieldPad(
              TextFormField(
                controller: _note,
                decoration: fieldDecoration(
                  'Not',
                  helper: 'En az 5 karakter. Örn. dekont no (kişisel veri yazmayın)',
                ),
                maxLines: 2,
                validator: requiredText(min: 5, max: 500),
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
