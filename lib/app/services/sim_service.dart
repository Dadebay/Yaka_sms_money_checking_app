import 'package:flutter/services.dart';

/// Info about an active SIM / subscription on the device.
class SimInfo {
  final int subId;
  final int slotIndex;

  /// Carrier-provisioned number. Frequently empty on these SIMs, hence the
  /// manual mapping fallback in [SimNumberStore].
  final String number;
  final String displayName;
  final String carrierName;

  const SimInfo({
    required this.subId,
    required this.slotIndex,
    required this.number,
    required this.displayName,
    required this.carrierName,
  });

  factory SimInfo.fromMap(Map map) {
    return SimInfo(
      subId: (map['subId'] as num?)?.toInt() ?? -1,
      slotIndex: (map['slotIndex'] as num?)?.toInt() ?? -1,
      number: (map['number'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      carrierName: (map['carrierName'] ?? '').toString(),
    );
  }
}

/// An incoming SMS as delivered by the native broadcast receiver.
class IncomingSms {
  final String address;
  final String body;

  /// Carrier timestamp in milliseconds since epoch.
  final int dateMillis;
  final int subId;

  const IncomingSms({
    required this.address,
    required this.body,
    required this.dateMillis,
    required this.subId,
  });

  factory IncomingSms.fromMap(Map map) {
    return IncomingSms(
      address: (map['address'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      dateMillis: (map['date'] as num?)?.toInt() ?? 0,
      subId: (map['subId'] as num?)?.toInt() ?? -1,
    );
  }
}

/// A single inbox SMS row read natively from the SMS content provider.
class InboxSms {
  final String address;
  final String body;
  final int dateMillis;
  final int subId;

  const InboxSms({
    required this.address,
    required this.body,
    required this.dateMillis,
    required this.subId,
  });

  factory InboxSms.fromMap(Map map) {
    return InboxSms(
      address: (map['address'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      dateMillis: (map['date'] as num?)?.toInt() ?? 0,
      subId: (map['subId'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Thin wrapper over the native `sim_sms_channel` method channel and the
/// `sim_sms_events` event channel. Replaces `flutter_sms_inbox` and
/// `easy_sms_receiver`, additionally exposing the receiving SIM's subId.
class SimService {
  static const MethodChannel _method = MethodChannel('sim_sms_channel');
  static const EventChannel _events = EventChannel('sim_sms_events');

  /// Active SIMs on the device (requires READ_PHONE_STATE).
  Future<List<SimInfo>> getActiveSims() async {
    final result = await _method.invokeMethod<List<dynamic>>('getActiveSims');
    if (result == null) return [];
    return result
        .whereType<Map>()
        .map((e) => SimInfo.fromMap(e))
        .toList();
  }

  /// Reads the SMS inbox (requires READ_SMS). [address] matches the tail of the
  /// sender address (e.g. "0801"); pass "" for all messages.
  Future<List<InboxSms>> queryInbox(String address) async {
    final result = await _method.invokeMethod<List<dynamic>>(
      'queryInbox',
      {'address': address},
    );
    if (result == null) return [];
    return result
        .whereType<Map>()
        .map((e) => InboxSms.fromMap(e))
        .toList();
  }

  /// Stream of incoming SMS (requires RECEIVE_SMS). Emits while there is a
  /// listener; the native receiver is registered on subscribe and torn down on
  /// cancel.
  Stream<IncomingSms> incomingSms() {
    return _events
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => IncomingSms.fromMap(event as Map));
  }
}
