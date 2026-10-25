import 'dart:convert';

import 'package:http/http.dart' as http;

class ReceiverApiException implements Exception {
  const ReceiverApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => '$message (HTTP $statusCode)';
}

class PaymentApiService {
  PaymentApiService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://komekchi.brandsforlesstm.com/api';
  static const _timeout = Duration(seconds: 15);
  static const transactionHeaders = <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=UTF-8',
  };
  final http.Client _client;

  void close() => _client.close();

  Future<String> fetchReceiver() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/phone'),
      headers: {'Accept': 'application/json'},
    ).timeout(_timeout);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReceiverApiException(
        response.statusCode,
        _receiverErrorMessage(body),
      );
    }
    return parseReceiver(body);
  }

  static String _receiverErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        for (final key in ['message_ru', 'error', 'message']) {
          final message = decoded[key];
          if (message is String && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
      }
    } on FormatException {
      // A proxy error page is not a user-facing message.
    }
    return 'Не удалось получить номер получателя';
  }

  static String parseReceiver(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = body;
    }

    dynamic value = decoded;
    for (var depth = 0; depth < 4 && value is Map; depth++) {
      final map = value;
      value = map['phone'] ??
          map['phone_number'] ??
          map['number'] ??
          map['receiver'] ??
          map['data'];
    }
    if (value is! String) {
      throw const FormatException('Alıcı numarası API yanıtında bulunamadı');
    }
    var number = value.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (RegExp(r'^\d{8}$').hasMatch(number)) number = '+993$number';
    if (RegExp(r'^993\d{8}$').hasMatch(number)) number = '+$number';
    if (!RegExp(r'^\+993\d{8}$').hasMatch(number)) {
      throw const FormatException('Alıcı numarası geçersiz');
    }
    return number;
  }

  static String formatTime(String value) {
    final local = RegExp(r'^(\d{2})/(\d{2})/(\d{4}) (\d{2}:\d{2}:\d{2})$')
        .firstMatch(value);
    if (local != null) {
      return '${local[3]}-${local[2]}-${local[1]} ${local[4]}';
    }
    return value;
  }

  static Map<String, dynamic> requestBody({
    required String sender,
    required String receiver,
    required String amount,
    required String time,
    required String token,
  }) {
    final parsedAmount = num.tryParse(amount.replaceAll(',', '.'));
    if (parsedAmount == null || parsedAmount <= 0) {
      throw const FormatException('SMS tutarı geçersiz');
    }
    if (token.trim().isEmpty) {
      throw const FormatException('Ödeme token\'ı ayarlardan girilmelidir');
    }
    return {
      'sender': sender.startsWith('+') ? sender : '+$sender',
      'receiver': receiver,
      'amount': parsedAmount,
      'token': token.trim(),
      'time': formatTime(time),
    };
  }

  Future<http.Response> postTransaction(Map<String, dynamic> body) => _client
      .post(
        Uri.parse('$_baseUrl/transactions'),
        headers: transactionHeaders,
        body: jsonEncode(body),
      )
      .timeout(_timeout);
}
