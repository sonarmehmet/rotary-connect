import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/providers.dart';
import '../../../data/validators.dart';
import '../../../shared/widgets/test_data_banner.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(sessionProvider.notifier).signIn(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      context.go(Routes.home);
    } else {
      // Hesap var/yok bilgisini sızdırmayan genel mesaj.
      setState(() => _error = 'E-posta veya şifre hatalı');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Giriş Yap')),
        body: Column(children: [
          const TestDataBanner(),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(Gaps.md), children: [
              Form(
                key: _form,
                child: Column(children: [
                  TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta'), validator: Validators.email),
                  TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre'), validator: Validators.password),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: Gaps.sm), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: Gaps.md),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: const Text('Giriş Yap'))),
                  TextButton(onPressed: () => context.go(Routes.register), child: const Text('Hesabın yok mu? Kayıt ol')),
                  TextButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Şifre sıfırlama bağlantısı e-postanıza gönderilir (Aşama 4).'))), child: const Text('Şifremi unuttum')),
                ]),
              ),
            ]),
          ),
        ]),
      );
}
