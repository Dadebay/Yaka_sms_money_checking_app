// 📄 HomeController - home_controller.dart
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sms_app/app/services/permission_service.dart';
import 'package:sms_app/app/services/sim_number_store.dart';
import 'package:sms_app/app/services/sim_service.dart';

class HomeController extends GetxController {
  final storage = GetStorage();
  final SimService simService = SimService();
  final SimNumberStore simNumberStore = SimNumberStore();

  RxList phoneNumberList = [].obs;
  RxBool agreeButton = false.obs;
  final String targetNumber = "0801";
  RxInt smsCount = 0.obs;

  /// Fallback receiver when a SIM number can't be resolved.
  static const String _fallbackReceiver = "+99364030911";

  /// Window (ms) within which two messages with the same payer/amount/SIM are
  /// treated as the same physical SMS. Tolerates the small skew between the
  /// live broadcast timestamp and the inbox `date` for one message, while still
  /// allowing genuine repeats that are minutes apart.
  static const int _dedupWindowMillis = 1000;

  /// Cache of subId -> active SIM number, refreshed from the device.
  final Map<int, String> _simNumbers = {};

  @override
  void onInit() {
    super.onInit();
    getPhoneNumbersList();
    refreshSimNumbers();
  }

  /// Loads carrier-provisioned numbers for active SIMs (best effort).
  Future<void> refreshSimNumbers() async {
    try {
      final sims = await simService.getActiveSims();
      _simNumbers.clear();
      for (final sim in sims) {
        if (sim.number.trim().isNotEmpty) {
          _simNumbers[sim.subId] = sim.number.trim();
        }
      }
    } catch (e) {
      print("⚠️ Could not read active SIMs: $e");
    }
  }

  /// Resolves the receiver number for the SIM that received the SMS:
  /// carrier number (auto) -> manual mapping -> hardcoded fallback.
  String resolveReceiver(int subId) {
    final auto = _simNumbers[subId];
    if (auto != null && auto.isNotEmpty) return auto;

    final manual = simNumberStore.numberFor(subId);
    if (manual != null && manual.isNotEmpty) return manual;

    return _fallbackReceiver;
  }

  Future<int> sendTransactionSMS({
    required String sender,
    required String amount,
    required String receiver,
  }) async {
    print("sender: $sender / receiver: $receiver / amount: $amount");
    try {
      final response = await http.post(
        Uri.parse('https://yashelektrik.com/api/v1/transactions'),
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
          HttpHeaders.authorizationHeader:
              'Bearer cAzP4oPFBBhS0oPUboKZRLD6Eh2ShWeEt4X2po67muTNUWLXhgbYZ3TfHx25',
        },
        body: jsonEncode(<String, dynamic>{
          'sender': "+$sender",
          'receiver': receiver,
          'amount': amount,
          'token': "BYAhDQAAAIOyop/ximLMMwI=",
        }),
      );

      print(response.body);
      print(response.statusCode);
      return response.statusCode;
    } catch (e) {
      print("❌ Error sending transaction: $e");
      return 0;
    }
  }

  void parseSmsAndAddToList(
    String sms,
    int dateMillis,
    String senderNumber,
    int subId,
  ) {
    if (!senderNumber.endsWith(targetNumber)) return;

    RegExp regExp1 =
        RegExp(r'(?<money>\d+,\d{2}|\d+\.\d{2}) manat\. Su (?<phone>\d{11})');
    RegExp regExp2 = RegExp(
        r'Sizin hasabynyz (?<money>\d+,\d{2}|\d+\.\d{2}) manat kopeldi.*');

    var match1 = regExp1.firstMatch(sms);
    var match2 = regExp2.firstMatch(sms);

    if (match1 != null) {
      String phone = match1.namedGroup('phone')!;
      String money = match1.namedGroup('money')!.replaceAll(',', '.');
      addPhoneNumber(
          phone: phone, dateMillis: dateMillis, money: money, subId: subId);
    } else if (match2 != null) {
      String money = match2.namedGroup('money')!.replaceAll(',', '.');
      String phone = "Terminaldan Gecdi";
      addPhoneNumber(
          phone: phone, dateMillis: dateMillis, money: money, subId: subId);
    }
  }

  void clearSmsList() {
    phoneNumberList.clear();
    storage.write("phoneNumberList", jsonEncode([]));
  }

  void retrySmsPost(Map<String, dynamic> item) async {
    final int status = await sendTransactionSMS(
      sender: item['phone'],
      amount: item['money'],
      receiver: item['receiver'] ?? _fallbackReceiver,
    );
    item['statusCode'] = status;
    phoneNumberList.refresh();
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));
  }

  Future<void> fetchSmsFrom0801() async {
    // Check and request SMS permission before reading
    bool hasPermission = await PermissionService.checkSmsPermission();
    if (!hasPermission) {
      print("❌ SMS permission not granted. Requesting...");
      hasPermission = await PermissionService.requestSmsPermission();
      if (!hasPermission) {
        print("❌ Cannot read SMS - permission denied");
        return;
      }
    }

    await refreshSimNumbers();

    final List<InboxSms> messages = await simService.queryInbox(targetNumber);
    smsCount.value = messages.length;
    for (final element in messages) {
      parseSmsAndAddToList(
        element.body,
        element.dateMillis,
        element.address,
        element.subId,
      );
    }
  }

  void getPhoneNumbersList() {
    final result = storage.read('phoneNumberList') ?? "[]";
    phoneNumberList.value = List<Map<String, dynamic>>.from(jsonDecode(result));
  }

  /// True if an existing entry represents the same physical SMS: same payer
  /// phone + amount + SIM, within [_dedupWindowMillis] of [dateMillis].
  bool _isDuplicate({
    required String phone,
    required String money,
    required int subId,
    required int dateMillis,
  }) {
    return phoneNumberList.any((e) {
      if (e["phone"] != phone || e["money"] != money) return false;
      if ((e["subId"] ?? -1) != subId) return false;
      final int existing = (e["dateMillis"] ?? 0) as int;
      return (existing - dateMillis).abs() < _dedupWindowMillis;
    });
  }

  Future<void> addPhoneNumber({
    required String phone,
    required int dateMillis,
    required String money,
    required int subId,
  }) async {
    // Atomic check-and-reserve: Dart is single-threaded, so as long as we add
    // the (pending) entry before any `await`, a concurrent call (live + fetch)
    // sees it and bails — guaranteeing the transaction is POSTed only once.
    if (_isDuplicate(
        phone: phone, money: money, subId: subId, dateMillis: dateMillis)) {
      return;
    }

    final String receiver = resolveReceiver(subId);
    final entry = <String, dynamic>{
      "id": "$subId-$phone-$money-$dateMillis",
      "phone": phone,
      "money": money,
      "dateMillis": dateMillis,
      "subId": subId,
      "receiver": receiver,
      "statusCode": 0, // pending
    };
    phoneNumberList.add(entry);
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));

    final int status = await sendTransactionSMS(
      sender: phone,
      amount: money,
      receiver: receiver,
    );
    entry["statusCode"] = status;
    phoneNumberList.refresh();
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));
  }
}
