import 'dart:convert';

import 'package:get_storage/get_storage.dart';

/// Persists a rolling log of failed transaction requests for later diagnosis.
///
/// Every time a POST to the transactions endpoint fails — either a non-success
/// HTTP status or a thrown network exception — [add] records the request body
/// and headers alongside the response status code and message. Entries are
/// stored newest-first in [GetStorage] under [_key] and capped at [_maxEntries]
/// so the log can't grow without bound.
class TransactionLogStore {
  static const String _key = 'transactionErrorLog';

  /// Keep only the most recent N failures; older entries are dropped.
  static const int _maxEntries = 200;

  /// Header names whose values are masked before storage, so secrets (the
  /// bearer token) aren't written to persistent storage in plain text.
  static const Set<String> _sensitiveHeaders = {'authorization'};

  final GetStorage _storage = GetStorage();

  /// All recorded failures, newest first.
  List<Map<String, dynamic>> read() {
    final raw = _storage.read(_key);
    if (raw is String && raw.isNotEmpty) {
      try {
        return List<Map<String, dynamic>>.from(jsonDecode(raw));
      } catch (_) {
        return [];
      }
    }
    if (raw is List) {
      return List<Map<String, dynamic>>.from(raw);
    }
    return [];
  }

  /// Records one failed transaction request.
  ///
  /// [statusCode] is the HTTP response status (or a synthetic code such as `0`
  /// for a thrown exception). [responseMessage] is the raw response body or the
  /// exception text. Sensitive header values are masked via [_maskHeaders].
  void add({
    required int statusCode,
    required Map<String, dynamic> requestBody,
    required Map<String, String> requestHeaders,
    required String responseMessage,
    String? error,
  }) {
    final entry = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'statusCode': statusCode,
      'requestBody': requestBody,
      'requestHeaders': _maskHeaders(requestHeaders),
      'responseMessage': responseMessage,
      if (error != null) 'error': error,
    };

    final logs = read();
    logs.insert(0, entry);
    if (logs.length > _maxEntries) {
      logs.removeRange(_maxEntries, logs.length);
    }
    _storage.write(_key, jsonEncode(logs));
  }

  /// Removes all recorded failures.
  void clear() => _storage.write(_key, jsonEncode([]));

  /// Returns a copy of [headers] with sensitive values replaced by `***`.
  Map<String, String> _maskHeaders(Map<String, String> headers) {
    return headers.map((key, value) {
      if (_sensitiveHeaders.contains(key.toLowerCase())) {
        return MapEntry(key, '***');
      }
      return MapEntry(key, value);
    });
  }
}
