import 'package:flutter/material.dart';

import '../core/labels.dart';

/// Durum rozeti. Renk tek başına anlam taşımaz; metin her zaman yazılıdır.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

(Color, Color) _colors(StatusTone tone) => switch (tone) {
      StatusTone.success => (const Color(0xFFE6F4EA), const Color(0xFF146C2E)),
      StatusTone.danger => (const Color(0xFFFDE8E8), const Color(0xFF9B1C1C)),
      StatusTone.warning => (const Color(0xFFFFF3E0), const Color(0xFF8A5300)),
      StatusTone.info => (const Color(0xFFE8EEF8), const Color(0xFF0B2A5B)),
      StatusTone.neutral => (const Color(0xFFF3F4F6), const Color(0xFF374151)),
    };
