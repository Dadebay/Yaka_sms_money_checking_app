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
    List<Map<String, dynamic>> logs;
    if (raw is String && raw.isNotEmpty) {
      try {
        logs = List<Map<String, dynamic>>.from(jsonDecode(raw));
      } catch (_) {
        return [];
      }
    } else if (raw is List) {
      logs = List<Map<String, dynamic>>.from(raw);
    } else {
      return [];
    }

    // Older releases stored the body token in plain text. Mask those entries
    // when read and rewrite the sanitized log so copies no longer expose it.
    var changed = false;
    for (final entry in logs) {
      final body = entry['requestBody'];
      if (body is Map && body['token'] != null && body['token'] != '***') {
        entry['requestBody'] = {...body, 'token': '***'};
        changed = true;
      }
    }
    if (changed) _storage.write(_key, jsonEncode(logs));
    return logs;
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
      'requestBody': {
        ...requestBody,
        if (requestBody.containsKey('token')) 'token': '***',
      },
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

  /// Removes failure logs belonging to payments purged from local history.
  /// Match all three fields so another payment from the same sender is kept.
  void removeForTransactions(Iterable<Map<String, dynamic>> transactions) {
    final keys = transactions.map(_transactionKey).whereType<String>().toSet();
    if (keys.isEmpty) return;
    final logs = read();
    final retained = logs.where((entry) {
      final body = entry['requestBody'];
      return body is! Map || !keys.contains(_transactionKey(body));
    }).toList();
    if (retained.length != logs.length) {
      _storage.write(_key, jsonEncode(retained));
    }
  }

  String? _transactionKey(Map item) {
    final sender = (item['sender'] ?? item['phone'])?.toString().trim();
    final amount = item['amount']?.toString() ?? item['money']?.toString();
    final time = item['time']?.toString();
    if (sender == null || sender.isEmpty || amount == null || time == null) {
      return null;
    }
    final normalizedSender = sender.startsWith('+') ? sender.substring(1) : sender;
    return '$normalizedSender|$amount|$time';
  }

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
