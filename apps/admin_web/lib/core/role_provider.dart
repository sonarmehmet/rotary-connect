import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotary_shared/shared.dart';

/// Geçici rol durumu (Aşama 4'te Firebase Auth claim'inden okunacak).
/// Geliştirme kolaylığı için varsayılan sistem yöneticisidir; üretimde
/// oturum açılmadan panel içeriği gösterilmeyecektir.
final adminRoleProvider = StateProvider<AppRole>((ref) => AppRole.systemAdmin);

/// Geçici kullanıcı kimliği (Aşama 4'te Auth uid olacak).
final adminUserIdProvider = Provider<String>((ref) => 'usr_demo');

/// Saat kaynağı; testlerde sabitlenebilir.
final adminClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
