import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sms_app/app/home/controllers/home_controller.dart';

void main() {
  late Directory storageDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    storageDirectory = await Directory.systemTemp.createTemp('sms-history-');
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

  test('old and manually imported entries are deleted without touching new SMS',
      () async {
    final storage = GetStorage();
    final oldDate = DateTime(2026, 8, 21).millisecondsSinceEpoch;
    final cutoff = DateTime(2026, 10, 17, 18).millisecondsSinceEpoch;
    final oldEntry = <String, dynamic>{
      'phone': '99361234567',
      'money': '50.00',
      'dateMillis': oldDate,
      'time': '21/08/2026 19:18:00',
      'subId': 1,
      'statusCode': 400,
    };
    await storage.write('phoneNumberList', jsonEncode([oldEntry]));
    await storage.write('phoneNumberListBeforeKomekciV1', jsonEncode([oldEntry]));
    await storage.write('transactionErrorLog', jsonEncode([
      {
        'requestBody': {
          'sender': '+99361234567',
          'amount': '50.00',
          'time': '21/08/2026 19:18:00',
        }
      },
    ]));
    await HomeController.prepareHistory();

    expect(storage.read<String>('phoneNumberList'), '[]');
    expect(storage.read('phoneNumberListBeforeKomekciV1'), isNull);
    expect(jsonDecode(storage.read<String>('transactionErrorLog')!), isEmpty);
    final firstRunCutoff = storage.read<int>('komekciHistoryStartedAtMillisV1')!;
    expect(firstRunCutoff, greaterThan(oldDate));

    final controller = HomeController()..onInit();
    addTearDown(controller.onClose);
    expect(controller.phoneNumberList, isEmpty);
    controller.parseSmsAndAddToList(
      '50.00 manat. Su 99361234567',
      oldDate,
      '0801',
      1,
    );
    expect(controller.phoneNumberList, isEmpty);

    final currentEntry = {
      ...oldEntry,
      'dateMillis': cutoff + 1,
      'time': '17/10/2026 18:00:01',
    };
    final manualEntry = {
      ...oldEntry,
      'dateMillis': cutoff + 2,
      'importedManually': true,
    };
    await storage.write('komekciHistoryStartedAtMillisV1', cutoff);
    await storage.write('phoneNumberList',
        jsonEncode([oldEntry, manualEntry, currentEntry]));
    await storage.write('transactionErrorLog', jsonEncode([
      {
        'requestBody': {
          'sender': '+99361234567',
          'amount': '50.00',
          'time': '21/08/2026 19:18:00',
        }
      },
      {
        'requestBody': {
          'sender': '+99361234567',
          'amount': '50.00',
          'time': '17/10/2026 18:00:01',
        }
      },
    ]));
    await HomeController.prepareHistory();
    expect(
        jsonDecode(storage.read<String>('phoneNumberList')!), [currentEntry]);
    expect(jsonDecode(storage.read<String>('transactionErrorLog')!), hasLength(1));
  });
}
