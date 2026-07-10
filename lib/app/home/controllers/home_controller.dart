// 📄 HomeController - home_controller.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sms_app/app/services/permission_service.dart';
import 'package:sms_app/app/services/sim_number_store.dart';
import 'package:sms_app/app/services/sim_service.dart';
import 'package:sms_app/app/services/transaction_log_store.dart';

class HomeController extends GetxController {
  final storage = GetStorage();
  final SimService simService = SimService();
  final SimNumberStore simNumberStore = SimNumberStore();
  final TransactionLogStore transactionLogStore = TransactionLogStore();

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
  static const int _dedupWindowMillis = 5000;

  /// Cache of subId -> active SIM number, refreshed from the device.
  final Map<int, String> _simNumbers = {};

  /// Periodic timer driving [runSyncCycle]; null until [_startAutoSync] runs.
  Timer? _cycleTimer;

  /// Whether a sync cycle is currently running. Drives the app-bar progress
  /// bar and doubles as the re-entrancy guard so cycles can't overlap.
  final RxBool isSyncing = false.obs;

  @override
  void onInit() {
    super.onInit();
    getPhoneNumbersList();
    refreshSimNumbers();
    _startAutoSync();
  }

  @override
  void onClose() {
    _cycleTimer?.cancel();
    super.onClose();
  }

  /// Runs [runSyncCycle] every minute to recover missed SMS and failed POSTs.
  void _startAutoSync() {
    _cycleTimer?.cancel();
    _cycleTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => runSyncCycle());
  }

  /// One sync pass: sweep the inbox for missed SMS, then re-send transactions
  /// that definitively failed. Skipped if the previous cycle is still running.
  Future<void> runSyncCycle() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    try {
      await _fetchInboxSilently();
      await retryFailedTransactions();
    } finally {
      isSyncing.value = false;
    }
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
      debugPrint("⚠️ Could not read active SIMs: $e");
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
    required String time,
  }) async {
    debugPrint(
        "sender: $sender / receiver: $receiver / amount: $amount / time: $time");

    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
      HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
      HttpHeaders.authorizationHeader:
          'Bearer cAzP4oPFBBhS0oPUboKZRLD6Eh2ShWeEt4X2po67muTNUWLXhgbYZ3TfHx25',
    };
    final requestBody = <String, dynamic>{
      'sender': "+$sender",
      'receiver': receiver,
      'amount': amount,
      'time': time,
      'token': "BYAhDQAAAIOyop/ximLMMwI=",
    };

    try {
      final response = await http.post(
        Uri.parse('https://yashelektrik.com/api/v1/transactions'),
        headers: headers,
        body: jsonEncode(requestBody),
      );

      debugPrint(response.body);
      debugPrint(response.statusCode.toString());

      // Anything other than a 2xx success is a failed transaction: log the
      // request that was sent and the server's error response for diagnosis.
      if (response.statusCode < 200 || response.statusCode >= 300) {
        transactionLogStore.add(
          statusCode: response.statusCode,
          requestBody: requestBody,
          requestHeaders: headers,
          responseMessage: response.body,
        );
      }
      return response.statusCode;
    } catch (e) {
      debugPrint("❌ Error sending transaction: $e");
      // Network/exception failure: no HTTP status, so record a synthetic 400
      // alongside the error text.
      transactionLogStore.add(
        statusCode: 400,
        requestBody: requestBody,
        requestHeaders: headers,
        responseMessage: e.toString(),
        error: e.toString(),
      );
      return 400;
    }
  }

  /// Matches a timestamp like `02/06/2026 15:34:12` anywhere in the SMS body.
  static final RegExp _timeRegExp =
      RegExp(r'(?<time>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2})');

  /// Formats epoch millis as `dd/MM/yyyy HH:mm:ss` (fallback when the SMS body
  /// has no embedded timestamp).
  String _formatTime(int dateMillis) {
    final d = DateTime.fromMillisecondsSinceEpoch(dateMillis);
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.day)}/${two(d.month)}/${d.year} "
        "${two(d.hour)}:${two(d.minute)}:${two(d.second)}";
  }

  void parseSmsAndAddToList(
    String sms,
    int dateMillis,
    String senderNumber,
    int subId,
  ) {
    if (!senderNumber.endsWith(targetNumber)) return;

    // Money: `20.0`, `20,00`, `20.00`, etc. Phone: 11 digits after "Su".
    RegExp regExp1 =
        RegExp(r'(?<money>\d+[.,]\d{1,2}) manat\. Su (?<phone>\d{11})');
    RegExp regExp2 =
        RegExp(r'Sizin hasabynyz (?<money>\d+[.,]\d{1,2}) manat kopeldi.*');

    var match1 = regExp1.firstMatch(sms);
    var match2 = regExp2.firstMatch(sms);

    // Prefer the timestamp embedded in the SMS; fall back to the inbox date.
    String time = _timeRegExp.firstMatch(sms)?.namedGroup('time') ??
        _formatTime(dateMillis);

    if (match1 != null) {
      String phone = match1.namedGroup('phone')!;
      String money = match1.namedGroup('money')!.replaceAll(',', '.');
      addPhoneNumber(
          phone: phone,
          dateMillis: dateMillis,
          money: money,
          subId: subId,
          time: time,
          body: sms);
    } else if (match2 != null) {
      String money = match2.namedGroup('money')!.replaceAll(',', '.');
      String phone = "Terminaldan Gecdi";
      addPhoneNumber(
          phone: phone,
          dateMillis: dateMillis,
          money: money,
          subId: subId,
          time: time,
          body: sms);
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
      time: item['time'] ?? _formatTime(item['dateMillis'] ?? 0),
    );
    item['statusCode'] = status;
    phoneNumberList.refresh();
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));
  }

  Future<void> fetchSmsFrom0801() async {
    // Check and request SMS permission before reading
    bool hasPermission = await PermissionService.checkSmsPermission();
    if (!hasPermission) {
      debugPrint("❌ SMS permission not granted. Requesting...");
      hasPermission = await PermissionService.requestSmsPermission();
      if (!hasPermission) {
        debugPrint("❌ Cannot read SMS - permission denied");
        return;
      }
    }

    await _fetchInbox();
  }

  /// Inbox sweep for the auto-sync cycle. Only *checks* permission (never
  /// prompts), so it can't pop a dialog every minute. No-op if not granted.
  Future<void> _fetchInboxSilently() async {
    final bool hasPermission = await PermissionService.checkSmsPermission();
    if (!hasPermission) return;
    await _fetchInbox();
  }

  /// Reads all SMS from [targetNumber] and parses each. Dedup in
  /// [addPhoneNumber] ensures already-recorded messages are not re-sent.
  Future<void> _fetchInbox() async {
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

  /// Re-sends transactions that definitively failed (any status other than
  /// pending `0` or success `200`/`201`). Skipping `0` avoids double-charging
  /// in-flight or timed-out requests that may have actually landed.
  Future<void> retryFailedTransactions() async {
    bool changed = false;
    for (final item in List<Map<String, dynamic>>.from(phoneNumberList)) {
      final int code = (item['statusCode'] ?? 0) as int;
      if (code == 0 || code == 200 || code == 201) continue;
      final int status = await sendTransactionSMS(
        sender: item['phone'],
        amount: item['money'],
        receiver: item['receiver'] ?? _fallbackReceiver,
        time: item['time'] ?? _formatTime(item['dateMillis'] ?? 0),
      );
      item['statusCode'] = status;
      changed = true;
    }
    if (changed) {
      phoneNumberList.refresh();
      storage.write("phoneNumberList", jsonEncode(phoneNumberList));
    }
  }

  void getPhoneNumbersList() {
    final result = storage.read('phoneNumberList') ?? "[]";
    phoneNumberList.value = List<Map<String, dynamic>>.from(jsonDecode(result));
  }

  /// True if an existing entry represents the same physical SMS.
  ///
  /// Primary key is the SMS [body] + [subId]: the body text is identical
  /// whether the message was captured via the live broadcast or re-read from
  /// the inbox sweep, and on every cycle, so the same physical SMS can never be
  /// recorded twice. The body also embeds the transaction's own timestamp, so
  /// genuinely distinct payments still differ.
  ///
  /// Legacy fallback: entries recorded before the `body` field existed are
  /// matched by phone + amount + SIM within [_dedupWindowMillis] of [dateMillis]
  /// so pre-update transactions aren't re-added/re-POSTed. Can be dropped once
  /// such entries have aged out.
  bool _isDuplicate({
    required String phone,
    required String money,
    required int subId,
    required int dateMillis,
    required String body,
  }) {
    final String key = body.trim();
    return phoneNumberList.any((e) {
      if ((e["subId"] ?? -1) != subId) return false;

      final String? existingBody = e["body"] as String?;
      if (existingBody != null) {
        return existingBody.trim() == key;
      }

      // Legacy entry without a stored body.
      if (e["phone"] != phone || e["money"] != money) return false;
      final int existing = (e["dateMillis"] ?? 0) as int;
      return (existing - dateMillis).abs() < _dedupWindowMillis;
    });
  }

  Future<void> addPhoneNumber({
    required String phone,
    required int dateMillis,
    required String money,
    required int subId,
    required String time,
    required String body,
  }) async {
    // Atomic check-and-reserve: Dart is single-threaded, so as long as we add
    // the (pending) entry before any `await`, a concurrent call (live + fetch)
    // sees it and bails — guaranteeing the transaction is POSTed only once.
    if (_isDuplicate(
        phone: phone,
        money: money,
        subId: subId,
        dateMillis: dateMillis,
        body: body)) {
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
      "time": time,
      "body": body.trim(),
      "statusCode": 0, // pending
    };
    phoneNumberList.add(entry);
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));

    final int status = await sendTransactionSMS(
      sender: phone,
      amount: money,
      receiver: receiver,
      time: time,
    );
    entry["statusCode"] = status;
    phoneNumberList.refresh();
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));
  }
}
