import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sms_app/app/home/controllers/home_controller.dart';
import 'package:sms_app/app/services/payment_api_service.dart';
import 'package:sms_app/app/services/payment_token_store.dart';

void main() {
  late Directory storageDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    storageDirectory = await Directory.systemTemp.createTemp('sms-import-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => storageDirectory.path,
    );
    await GetStorage('GetStorage', storageDirectory.path).initStorage;
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await storageDirectory.delete(recursive: true);
  });

  test('pre-installation SMS is rejected and new SMS is imported once',
      () async {
    final storage = GetStorage();
    final installationTime = DateTime(2026, 10, 17, 18).millisecondsSinceEpoch;
    final oldSmsTime = DateTime(2026, 10, 17, 17, 39, 7).millisecondsSinceEpoch;
    final newSmsTime = DateTime(2026, 10, 17, 18, 5).millisecondsSinceEpoch;
    await storage.write('komekciHistoryStartedAtMillisV1', installationTime);
    await storage.write('phoneNumberList', '[]');
    await PaymentTokenStore().save('test-token');

    var posted = 0;
    final api = PaymentApiService(client: MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response('{"phone":"+99364030911"}', 200);
      }
      posted++;
      return http.Response('{"success":true}', 200);
    }));
    final controller = HomeController(paymentApi: api)..onInit();
    addTearDown(controller.onClose);

    const oldPayment =
        '17/10/2026 17:39:07 gecirilen 20.00 manat. Su 99371821848';
    const newPayment =
        '17/10/2026 18:05:00 gecirilen 20.00 manat. Su 99371821848';
    const confirmation =
        '17/10/2026 17:43:12 99371821848 gecirilen 20.00 manat Saklanan 0.10 manat';

    expect(await controller.parseSmsAndAddToList(oldPayment, oldSmsTime, '0801', -1),
        isFalse);
    expect(
        await controller.parseSmsAndAddToList(newPayment, newSmsTime, '0801', 2),
        isTrue);
    expect(
        await controller.parseSmsAndAddToList(
            confirmation, newSmsTime + 5 * 60 * 1000, '0801', -1),
        isFalse);
    expect(
        await controller.parseSmsAndAddToList(newPayment, newSmsTime, '0801', -1),
        isFalse);
    expect(posted, 1);
    expect(controller.phoneNumberList, hasLength(1));
    expect(controller.phoneNumberList.first['importedManually'], isNull);
    expect(controller.phoneNumberList.first['statusCode'], 200);

    controller.getPhoneNumbersList();
    expect(controller.phoneNumberList, hasLength(1));
    expect(jsonDecode(storage.read<String>('phoneNumberList')!), hasLength(1));
  });
}
