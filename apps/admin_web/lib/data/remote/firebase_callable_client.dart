import 'package:cloud_functions/cloud_functions.dart';

import 'callable_client.dart';

/// `cloud_functions` ile [CallableClient]. DOĞRULANMAMIŞ: derlenmedi/çalıştırılmadı.
/// Bölge sunucudaki `callables.ts` ile aynıdır (europe-west1).
class FirebaseCallableClient implements CallableClient {
  FirebaseCallableClient({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      final out = result.data;
      if (out is Map) {
        return out.map((k, v) => MapEntry(k.toString(), v));
      }
      return const <String, Object?>{};
    } on FirebaseFunctionsException catch (e) {
      throw callableErrorToException(e.code, e.message, e.details);
    }
  }
}
