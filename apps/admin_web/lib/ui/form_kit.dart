import 'package:flutter/material.dart';
import 'package:rotary_shared/shared.dart';

import '../core/format.dart';

/// Form iletişim kutusu çerçevesi. `AlertDialog` yerine `Dialog` kullanılır:
/// `AlertDialog` içeriği iç boyut hesabı yaptığından `DropdownMenu` gibi
/// alanlarla çakışabilir.
class DialogShell extends StatelessWidget {
  const DialogShell({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.maxWidth = 560,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Flexible(child: SingleChildScrollView(child: child)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, runSpacing: 8, children: actions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alanlar arası dikey boşluk.
Widget fieldPad(Widget child) =>
    Padding(padding: const EdgeInsets.only(bottom: 16), child: child);

/// Standart metin alanı süslemesi.
InputDecoration fieldDecoration(String label, {String? helper}) =>
    InputDecoration(
      labelText: label,
      helperText: helper,
      border: const OutlineInputBorder(),
    );

/// Zorunlu metin doğrulayıcısı (kırpılmış uzunluk sınırları).
String? Function(String?) requiredText({int min = 1, int max = 2000}) {
  return (value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Zorunlu alan';
    if (text.length < min) return 'En az $min karakter girin';
    if (text.length > max) return 'En çok $max karakter olabilir';
    return null;
  };
}

/// Tutar doğrulayıcısı ("1.250,50" biçimi; ondalık ayraç virgüldür).
String? Function(String?) moneyValidator({bool allowZero = false}) {
  return (value) {
    final money = Money.tryParseTr(value ?? '');
    if (money == null) return 'Geçerli bir tutar girin (örn. 1.250,50)';
    if (!allowZero && money.minor <= 0) return 'Tutar sıfırdan büyük olmalı';
    return null;
  };
}

/// Pozitif tam sayı doğrulayıcısı.
String? positiveInt(String? value) {
  final n = int.tryParse((value ?? '').trim());
  if (n == null || n < 1) return 'En az 1 olan bir tam sayı girin';
  return null;
}

/// Enum seçimi (etiketli açılır menü).
class EnumDropdown<E> extends StatelessWidget {
  const EnumDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final E value;
  final List<E> values;
  final String Function(E value) labelOf;
  final ValueChanged<E> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<E>(
      initialSelection: value,
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      enableFilter: false,
      dropdownMenuEntries: [
        for (final v in values)
          DropdownMenuEntry<E>(value: v, label: labelOf(v)),
      ],
      onSelected: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}

/// Tarih (ve isteğe bağlı saat) alanı. Değer UTC anıdır; seçim İstanbul
/// takvimine göre yorumlanır. `endOfDay` tarih-only alanlarda gün sonunu
/// (23:59) saklar (örn. kampanya bitişi).
class DateFormField extends FormField<DateTime> {
  DateFormField({
    super.key,
    required String label,
    required ValueChanged<DateTime?> onChanged,
    DateTime? initialValue,
    bool withTime = false,
    bool endOfDay = false,
    bool isRequired = true,
  }) : super(
          initialValue: initialValue,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) =>
              isRequired && value == null ? 'Zorunlu alan' : null,
          builder: (state) {
            Future<void> pick() async {
              final ctx = state.context;
              final current = state.value == null
                  ? toIstanbul(DateTime.now())
                  : toIstanbul(state.value!);
              final date = await showDatePicker(
                context: ctx,
                initialDate: DateTime(current.year, current.month, current.day),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                helpText: label,
                cancelText: 'Vazgeç',
                confirmText: 'Seç',
              );
              if (date == null || !ctx.mounted) return;
              var hour = endOfDay ? 23 : 0;
              var minute = endOfDay ? 59 : 0;
              if (withTime) {
                final time = await showTimePicker(
                  context: ctx,
                  initialTime: TimeOfDay(
                    hour: state.value == null ? 9 : current.hour,
                    minute: state.value == null ? 0 : current.minute,
                  ),
                  helpText: '$label — saat',
                  cancelText: 'Vazgeç',
                  confirmText: 'Seç',
                );
                if (time == null || !ctx.mounted) return;
                hour = time.hour;
                minute = time.minute;
              }
              final picked =
                  istanbulToInstant(date.year, date.month, date.day, hour, minute);
              state.didChange(picked);
              onChanged(picked);
            }

            final value = state.value;
            return InkWell(
              onTap: pick,
              child: InputDecorator(
                isEmpty: value == null,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: state.errorText,
                ),
                child: Text(
                  value == null
                      ? ''
                      : (withTime ? formatDateTime(value) : formatDate(value)),
                ),
              ),
            );
          },
        );
}
