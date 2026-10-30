import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  // Aşama 4: Firebase.initializeApp() burada çağrılacak.
  runApp(const ProviderScope(child: RotaryConnectApp()));
}
