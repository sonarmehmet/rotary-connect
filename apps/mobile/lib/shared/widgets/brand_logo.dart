import 'package:flutter/material.dart';

/// Değiştirilebilir logo alanı. Resmî Rotary logosu verilmediği için GEÇİCİ
/// bir yer tutucu çizilir; resmî dosya geldiğinde yalnızca [assetPath]
/// verilmesi yeterlidir (dosyayı `assets/` altına koyup pubspec'e ekleyin).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 48, this.assetPath});

  final double size;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final path = assetPath;
    if (path != null) {
      return Image.asset(path, width: size, height: size, semanticLabel: 'Kulüp logosu');
    }
    return Semantics(
      label: 'Geçici logo alanı',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: const Color(0xFFC9A24B), width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          'LOGO',
          style: TextStyle(
            fontSize: size * 0.22,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0B2A5B),
          ),
        ),
      ),
    );
  }
}
