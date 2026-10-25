import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sms_app/app/services/payment_api_service.dart';

void main() {
  test('transaction body rejects an unset payment token', () {
    expect(
      () => PaymentApiService.requestBody(
        sender: '99371821848',
        receiver: '+99364030911',
        amount: '20.00',
        time: '17/10/2026 17:39:07',
        token: '',
      ),
      throwsFormatException,
    );
  });

  test('transaction uses the phone API and the documented JSON contract',
      () async {
    final calls = <String>[];
    final api = PaymentApiService(client: MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.url.path == '/api/phone') {
        return http.Response('{"data":{"phone":"+99364030911"}}', 200);
      }
      expect(request.url.path, '/api/transactions');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(request.body), {
        'sender': '+99371821848',
        'receiver': '+99364030911',
        'amount': 20,
        'token': 'test-token',
        'time': '2026-10-17 17:39:07',
      });
      return http.Response('{"success":true}', 200);
    }));
    addTearDown(api.close);

    final receiver = await api.fetchReceiver();
    final body = PaymentApiService.requestBody(
      sender: '99371821848',
      receiver: receiver,
      amount: '20.00',
      time: '17/10/2026 17:39:07',
      token: 'test-token',
    );
    expect((await api.postTransaction(body)).statusCode, 200);
    expect(calls, ['GET /api/phone', 'POST /api/transactions']);
  });

  test('invalid receiver response fails before a transaction is posted',
      () async {
    var posted = false;
    final api = PaymentApiService(client: MockClient((request) async {
      if (request.method == 'POST') posted = true;
      return http.Response('{"data":{}}', 200);
    }));
    addTearDown(api.close);

    await expectLater(api.fetchReceiver(), throwsFormatException);
    expect(posted, isFalse);
  });

  test('unavailable receiver shows the server message and HTTP status',
      () async {
    final api = PaymentApiService(client: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/phone');
      return http.Response(
        '{"error":"На данный момент нет доступных номеров."}',
        404,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));
    addTearDown(api.close);

    await expectLater(
      api.fetchReceiver(),
      throwsA(isA<ReceiverApiException>()
          .having((e) => e.statusCode, 'statusCode', 404)
          .having((e) => e.message, 'message',
              'На данный момент нет доступных номеров.')),
    );
  });
}
