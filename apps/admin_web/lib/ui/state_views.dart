import 'package:flutter/material.dart';
import 'package:rotary_shared/shared.dart';

/// Yükleniyor durumu.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// Boş liste / filtreye uyan kayıt yok durumu.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(BrandColors.navy)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Hata durumu; "Tekrar dene" ile yeniden yüklenir.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
              color: Color(BrandColors.error),
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rol bu sayfayı görmeye yetkili değil. (Gerçek yetki sunucuda uygulanır;
/// bu ekran yalnızca kullanıcıyı bilgilendirir.)
class NoAccessView extends StatelessWidget {
  const NoAccessView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: Color(BrandColors.navy)),
            SizedBox(height: 12),
            Text(
              'Bu sayfayı görüntüleme yetkiniz yok.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              'Yetkiler rolünüze göre tanımlanır; soldaki menüden '
              'erişebildiğiniz bölümleri kullanabilirsiniz.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
