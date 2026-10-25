import 'package:get_storage/get_storage.dart';

class PaymentTokenStore {
  static const _key = 'phonePaymentToken';

  final GetStorage _storage = GetStorage();

  String get token => _storage.read<String>(_key)?.trim() ?? '';

  Future<void> save(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError('Token boş olamaz');
    await _storage.write(_key, trimmed);
  }
}
