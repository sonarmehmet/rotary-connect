import 'package:flutter/material.dart';
import 'package:rotary_shared/shared.dart';

/// Örnek veriyle çalışan her ekranın üstünde görünür.
class TestDataBanner extends StatelessWidget {
  const TestDataBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF3E0),
        border: Border.fromBorderSide(
          BorderSide(color: Color(BrandColors.warning)),
        ),
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, size: 18, color: Color(BrandColors.warning)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ÖRNEK VERİ — Bu sayfadaki kayıtlar gerçek değildir; '
              'ödemeler simülasyondur.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
