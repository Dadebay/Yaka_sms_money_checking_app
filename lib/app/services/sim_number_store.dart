import 'package:get_storage/get_storage.dart';

/// Persists a manual mapping of SIM subscription id -> phone number.
///
/// Carrier-provisioned numbers (`SimInfo.number`) are frequently empty on the
/// SIMs this app targets, so the user can enter each SIM's number once via the
/// SIM settings screen. Stored in [GetStorage] under [_key] as
/// `{ "<subId>": "+993..." }`.
class SimNumberStore {
  static const String _key = 'simNumberMap';
  final GetStorage _storage = GetStorage();

  /// The full subId -> number map.
  Map<String, String> read() {
    final raw = _storage.read(_key);
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
    }
    return {};
  }

  /// Manually configured number for [subId], or null if none set.
  String? numberFor(int subId) {
    final value = read()[subId.toString()];
    if (value != null && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// Sets (or clears, when [number] is empty) the number for [subId].
  void setNumber(int subId, String number) {
    final map = read();
    final trimmed = number.trim();
    if (trimmed.isEmpty) {
      map.remove(subId.toString());
    } else {
      map[subId.toString()] = trimmed;
    }
    _storage.write(_key, map);
  }
}
