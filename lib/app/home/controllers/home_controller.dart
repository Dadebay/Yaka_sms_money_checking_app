// 📄 HomeController - home_controller.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sms_app/app/services/permission_service.dart';
import 'package:sms_app/app/services/payment_api_service.dart';
import 'package:sms_app/app/services/payment_token_store.dart';
import 'package:sms_app/app/services/sim_service.dart';
import 'package:sms_app/app/services/transaction_log_store.dart';

class HomeController extends GetxController {
  HomeController({PaymentApiService? paymentApi})
      : paymentApi = paymentApi ?? PaymentApiService();

  static const _historyCutoffKey = 'komekciHistoryStartedAtMillisV1';
  static const _legacyHistoryKey = 'phoneNumberListBeforeKomekciV1';

  /// Establish the first-run cutoff and discard payments imported from older
  /// inbox messages by previous releases. Removed payments must not be retried.
  static Future<void> prepareHistory() async {
    final storage = GetStorage();
    final existingCutoff = storage.read<int>(_historyCutoffKey);
    final cutoff = existingCutoff ?? DateTime.now().millisecondsSinceEpoch;
    final raw = storage.read<String>('phoneNumberList') ?? '[]';
    final entries = List<Map<String, dynamic>>.from(jsonDecode(raw));
    if (existingCutoff == null) {
      TransactionLogStore().removeForTransactions(entries);
      await storage.write(_historyCutoffKey, cutoff);
      await storage.write('phoneNumberList', '[]');
    } else {
      final current = entries.where((item) {
        final date = item['dateMillis'];
        return date is int &&
            date >= cutoff &&
            item['importedManually'] != true;
      }).toList();
      if (current.length != entries.length) {
        TransactionLogStore().removeForTransactions(
          entries.where((item) => !current.contains(item)),
        );
        await storage.write('phoneNumberList', jsonEncode(current));
      }
    }
    await storage.remove(_legacyHistoryKey);
  }

  final storage = GetStorage();
  final SimService simService = SimService();
  final TransactionLogStore transactionLogStore = TransactionLogStore();
  final PaymentApiService paymentApi;
  final PaymentTokenStore paymentTokenStore = PaymentTokenStore();

  RxList phoneNumberList = [].obs;
  RxBool agreeButton = false.obs;
  final String targetNumber = "0801";
  RxInt smsCount = 0.obs;

  /// Window (ms) within which two messages with the same payer/amount/SIM are
  /// treated as the same physical SMS. Tolerates the small skew between the
  /// live broadcast timestamp and the inbox `date` for one message, while still
  /// allowing genuine repeats that are minutes apart.
  static const int _dedupWindowMillis = 5000;

  late final int _monitoringStartedAtMillis;

  bool _isCurrentEntry(Map item) {
    final date = item['dateMillis'];
    return date is int &&
        date >= _monitoringStartedAtMillis &&
        item['importedManually'] != true;
  }

  /// Periodic timer driving [runSyncCycle]; null until [_startAutoSync] runs.
  Timer? _cycleTimer;

  /// Whether a sync cycle is currently running. Drives the app-bar progress
  /// bar and doubles as the re-entrancy guard so cycles can't overlap.
  final RxBool isSyncing = false.obs;

  @override
  void onInit() {
    super.onInit();
    _monitoringStartedAtMillis = storage.read<int>(_historyCutoffKey) ??
        DateTime.now().millisecondsSinceEpoch;
    getPhoneNumbersList();
    _startAutoSync();
    unawaited(runSyncCycle());
  }

  @override
  void onClose() {
    _cycleTimer?.cancel();
    paymentApi.close();
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
    } catch (e) {
      debugPrint('❌ SMS sync failed: $e');
    } finally {
      isSyncing.value = false;
    }
  }

  Future<int> sendTransactionSMS({
    required String sender,
    required String amount,
    required String time,
  }) async {
    // The receiver comes from the payment backend, not from the device's SIM.
    // If that lookup fails, avoid sending money to a stale fallback number.
    late final String receiver;
    try {
      receiver = await paymentApi.fetchReceiver();
    } catch (e) {
      transactionLogStore.add(
        statusCode: 503,
        requestBody: {'sender': sender, 'amount': amount, 'time': time},
        requestHeaders: const {'Accept': 'application/json'},
        responseMessage: 'GET /api/phone: $e',
      );
      return 503;
    }

    late final Map<String, dynamic> requestBody;
    try {
      requestBody = PaymentApiService.requestBody(
        sender: sender,
        receiver: receiver,
        amount: amount,
        time: time,
        token: paymentTokenStore.token,
      );
    } on FormatException catch (e) {
      transactionLogStore.add(
        statusCode: 400,
        requestBody: {
          'sender': sender,
          'receiver': receiver,
          'amount': amount,
          'time': time
        },
        requestHeaders: PaymentApiService.transactionHeaders,
        responseMessage: e.message,
      );
      return 400;
    }

    try {
      final response = await paymentApi.postTransaction(requestBody);

      debugPrint(response.body);
      debugPrint(response.statusCode.toString());

      // Anything other than a 2xx success is a failed transaction: log the
      // request that was sent and the server's error response for diagnosis.
      if (response.statusCode < 200 || response.statusCode >= 300) {
        transactionLogStore.add(
          statusCode: response.statusCode,
          requestBody: requestBody,
          requestHeaders: PaymentApiService.transactionHeaders,
          responseMessage: response.body,
        );
      }
      return response.statusCode;
    } catch (e) {
      debugPrint("❌ Error sending transaction: $e");
      // The POST may have reached the server. Keep it pending so the minute
      // timer cannot automatically submit the same payment a second time.
      transactionLogStore.add(
        statusCode: 0,
        requestBody: requestBody,
        requestHeaders: PaymentApiService.transactionHeaders,
        responseMessage: e.toString(),
        error: e.toString(),
      );
      return 0;
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

  Future<bool> parseSmsAndAddToList(
    String sms,
    int dateMillis,
    String senderNumber,
    int subId,
  ) async {
    if (!senderNumber.trim().endsWith(targetNumber)) return false;
    if (dateMillis < _monitoringStartedAtMillis) {
      return false;
    }

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
      return addPhoneNumber(
          phone: phone,
          dateMillis: dateMillis,
          money: money,
          subId: subId,
          time: time,
          body: sms);
    } else if (match2 != null) {
      String money = match2.namedGroup('money')!.replaceAll(',', '.');
      String phone = "Terminaldan Gecdi";
      return addPhoneNumber(
          phone: phone,
          dateMillis: dateMillis,
          money: money,
          subId: subId,
          time: time,
          body: sms);
    }
    return false;
  }

  void clearSmsList() {
    phoneNumberList.clear();
    storage.write("phoneNumberList", jsonEncode([]));
  }

  void retrySmsPost(Map<String, dynamic> item) async {
    if (!_isCurrentEntry(item)) return;
    final int status = await sendTransactionSMS(
      sender: item['phone'],
      amount: item['money'],
      time: item['time'] ?? _formatTime(item['dateMillis'] ?? 0),
    );
    item['statusCode'] = status;
    phoneNumberList.refresh();
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));
  }

  Future<int> fetchSmsFrom0801() async {
    // Check and request SMS permission before reading
    bool hasPermission = await PermissionService.checkSmsPermission();
    if (!hasPermission) {
      debugPrint("❌ SMS permission not granted. Requesting...");
      hasPermission = await PermissionService.requestSmsPermission();
      if (!hasPermission) {
        debugPrint("❌ Cannot read SMS - permission denied");
        throw StateError('SMS okuma izni verilmedi');
      }
    }
    if (isSyncing.value) {
      throw StateError('SMS senkronizasyonu sürüyor; birazdan tekrar deneyin');
    }
    isSyncing.value = true;
    try {
      return await _fetchInbox();
    } finally {
      isSyncing.value = false;
    }
  }

  /// Inbox sweep for the auto-sync cycle. Only *checks* permission (never
  /// prompts), so it can't pop a dialog every minute. No-op if not granted.
  Future<void> _fetchInboxSilently() async {
    final bool hasPermission = await PermissionService.checkSmsPermission();
    if (!hasPermission) return;
    await _fetchInbox();
  }

  /// Reads SMS from [targetNumber] received since the first-run cutoff. Dedup
  /// in [addPhoneNumber] ensures already-recorded messages are not re-sent.
  Future<int> _fetchInbox() async {
    final List<InboxSms> messages = await simService.queryInbox(targetNumber);
    smsCount.value = messages
        .where((sms) => sms.dateMillis >= _monitoringStartedAtMillis)
        .length;
    var imported = 0;
    for (final element in messages) {
      if (element.dateMillis < _monitoringStartedAtMillis) continue;
      if (await parseSmsAndAddToList(
        element.body,
        element.dateMillis,
        element.address,
        element.subId,
      )) {
        imported++;
      }
    }
    return imported;
  }

  /// Re-sends transactions that definitively failed (any status other than
  /// pending `0` or a 2xx success). Skipping `0` avoids double-charging
  /// in-flight or timed-out requests that may have actually landed.
  Future<void> retryFailedTransactions() async {
    bool changed = false;
    for (final item in List<Map<String, dynamic>>.from(phoneNumberList)) {
      if (!_isCurrentEntry(item)) continue;
      final int code = (item['statusCode'] ?? 0) as int;
      if (code == 0 || (code >= 200 && code < 300)) continue;
      final int status = await sendTransactionSMS(
        sender: item['phone'],
        amount: item['money'],
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
    phoneNumberList.value = List<Map<String, dynamic>>.from(jsonDecode(result))
        .where(_isCurrentEntry)
        .toList();
  }

  /// True if an existing entry represents the same physical SMS.
  ///
  /// Primary key is the SMS [body]: the body text is identical
  /// whether the message was captured via the live broadcast or re-read from
  /// the inbox sweep, even when a provider omits the subscription id. The
  /// body also embeds the transaction timestamp, so distinct payments differ.
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
      final String? existingBody = e["body"] as String?;
      if (existingBody != null) {
        return existingBody.trim() == key;
      }

      // Legacy entry without a stored body.
      final oldSubId = (e["subId"] ?? -1) as int;
      if (oldSubId >= 0 && subId >= 0 && oldSubId != subId) return false;
      if (e["phone"] != phone || e["money"] != money) return false;
      final int existing = (e["dateMillis"] ?? 0) as int;
      return (existing - dateMillis).abs() < _dedupWindowMillis;
    });
  }

  Future<bool> addPhoneNumber({
    required String phone,
    required int dateMillis,
    required String money,
    required int subId,
    required String time,
    required String body,
  }) async {
    if (dateMillis < _monitoringStartedAtMillis) {
      return false;
    }
    // Atomic check-and-reserve: Dart is single-threaded, so as long as we add
    // the (pending) entry before any `await`, a concurrent call (live + fetch)
    // sees it and bails — guaranteeing the transaction is POSTed only once.
    if (_isDuplicate(
        phone: phone,
        money: money,
        subId: subId,
        dateMillis: dateMillis,
        body: body)) {
      return false;
    }

    final entry = <String, dynamic>{
      "id": "$subId-$phone-$money-$dateMillis",
      "phone": phone,
      "money": money,
      "dateMillis": dateMillis,
      "subId": subId,
      "time": time,
      "body": body.trim(),
      "statusCode": 0, // pending
    };
    phoneNumberList.add(entry);
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));

    final int status = await sendTransactionSMS(
      sender: phone,
      amount: money,
      time: time,
    );
    entry["statusCode"] = status;
    phoneNumberList.refresh();
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));
    return true;
  }
}
