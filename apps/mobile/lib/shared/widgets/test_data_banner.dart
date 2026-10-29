import 'package:flutter/material.dart';

import '../../core/env/app_env.dart';
import '../../core/theme/app_theme.dart';

/// Geliştirme ortamında örnek veri ve simüle edilmiş ödemeyi açıkça işaretler.
/// Üretimde ([AppEnv.showTestDataBadges] false) hiçbir şey çizmez.
class TestDataBanner extends StatelessWidget {
  const TestDataBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppEnv.showTestDataBadges) return const SizedBox.shrink();

    final text = AppEnv.isSimulation
        ? 'TEST VERİSİ • ÖDEME SİMÜLASYONU (gerçek tahsilat yapılmaz)'
        : 'TEST VERİSİ';

    return Container(
      width: double.infinity,
      color: AppTheme.warning,
      padding: const EdgeInsets.symmetric(
        horizontal: Gaps.md,
        vertical: Gaps.xs,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
