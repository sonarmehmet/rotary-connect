import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/providers.dart';
import '../../../data/validators.dart';
import '../../../shared/widgets/test_data_banner.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _kvkk = false;
  bool _busy = false;
  bool _showKvkkError = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    setState(() => _showKvkkError = !_kvkk);
    if (_busy || !valid || !_kvkk) return;
    setState(() => _busy = true);
    await ref.read(sessionProvider.notifier).register(_name.text.trim(), _email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kayıt Ol')),
        body: Column(children: [
          const TestDataBanner(),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(Gaps.md), children: [
              Form(
                key: _form,
                child: Column(children: [
                  TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Ad Soyad'), validator: (v) => Validators.required(v, 'Ad soyad')),
                  TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta'), validator: Validators.email),
                  TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre (en az 8 karakter)'), validator: Validators.password),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _kvkk,
                    onChanged: (v) => setState(() => _kvkk = v ?? false),
                    title: const Text('KVKK aydınlatma metnini okudum ve kişisel verilerimin işlenmesini kabul ediyorum.'),
                    subtitle: _showKvkkError && !_kvkk ? Text('Devam etmek için onay gerekli', style: TextStyle(color: Theme.of(context).colorScheme.error)) : null,
                  ),
                  const SizedBox(height: Gaps.md),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: const Text('Kayıt Ol'))),
                  TextButton(onPressed: () => context.go(Routes.login), child: const Text('Zaten hesabım var')),
                ]),
              ),
            ]),
          ),
        ]),
      );
}
