import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Aşama 4: Firebase.initializeApp() burada çağrılacak.
  runApp(const ProviderScope(child: RotaryConnectApp()));
}
