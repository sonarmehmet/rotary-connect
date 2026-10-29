import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'test_data_banner.dart';

/// Aşama 3'te gerçek ekranla değiştirilecek geçici ekran.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.stage = 3,
  });

  final String title;
  final int stage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          const TestDataBanner(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Gaps.lg),
                child: Text(
                  '$title ekranı Aşama $stage\'te uygulanacak.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
