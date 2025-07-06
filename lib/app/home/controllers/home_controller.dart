// 📄 HomeController - home_controller.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_sms_inbox/flutter_sms_inbox.dart' as sms_inbox;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

class HomeController extends GetxController {
  final storage = GetStorage();
  RxList phoneNumberList = [].obs;
  RxBool agreeButton = false.obs;
  final String targetNumber = "0801";

  @override
  void onInit() {
    super.onInit();
    getPhoneNumbersList();
    readOldSmsFromStorage();
  }

  Future<int> sendTransactionSMS({
    required String sender,
    required String amount,
    required String? receiver,
  }) async {
    final String? phoneNumber = await getPhoneNumberWithRetries();

    print(sender);
    print(phoneNumber);
    print(receiver);
    String receiverNumber = "+99364030911";

    if (receiver != null && receiver != "") {
      receiverNumber = receiver;
    } else if (phoneNumber != null) {
      receiverNumber = phoneNumber;
    }
    print(receiverNumber);
    final response = await http.post(
      Uri.parse('https://yashelektrik.com/api/v1/transactions'),
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
        HttpHeaders.authorizationHeader: 'Bearer cAzP4oPFBBhS0oPUboKZRLD6Eh2ShWeEt4X2po67muTNUWLXhgbYZ3TfHx25',
      },
      body: jsonEncode(<String, dynamic>{
        'sender': "+$sender",
        'receiver': receiverNumber,
        'amount': amount,
        'token': "BYAhDQAAAIOyop/ximLMMwI=",
      }),
    );

    print(response.body);
    print(response.statusCode);
    return response.statusCode;
  }

  Future<String?> getPhoneNumberWithRetries() async {
    final response = await http.get(
      Uri.parse('https://yashelektrik.com/api/v1/phone'),
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
      },
    );
    final result = json.decode(response.body);
    final phone = result['data'][0];
    if (phone != null && phone.toString().isNotEmpty) {
      return phone;
    }

    await Future.delayed(const Duration(seconds: 1));
    return '';
  }

  void parseSmsAndAddToList(String sms, String date, String senderNumber, {int? simSlot}) {
    if (!senderNumber.endsWith(targetNumber)) return;

    RegExp regExp1 = RegExp(r'(?<money>\d+,\d{2}|\d+\.\d{2}) manat\. Su (?<phone>\d{11})');
    RegExp regExp2 = RegExp(r'Sizin hasabynyz (?<money>\d+,\d{2}|\d+\.\d{2}) manat kopeldi.*');

    var match1 = regExp1.firstMatch(sms);
    var match2 = regExp2.firstMatch(sms);

    if (match1 != null) {
      String phone = match1.namedGroup('phone')!;
      String money = match1.namedGroup('money')!.replaceAll(',', '.');
      String id = "$phone-$money-${date.substring(0, 16)}";
      addPhoneNumber(phone: phone, dateAndTime: date, money: money, simSlot: simSlot, id: id);
    } else if (match2 != null) {
      String money = match2.namedGroup('money')!.replaceAll(',', '.');
      String phone = "Terminaldan Gecdi";
      String id = "$phone-$money-${date.substring(0, 16)}";
      addPhoneNumber(phone: phone, dateAndTime: date, money: money, simSlot: simSlot, id: id);
    }
  }

  void readOldSmsFromStorage() {
    List<String> oldSmsList = storage.read('oldSmsList') ?? [];
    for (var sms in oldSmsList) {
      parseSmsAndAddToList(sms, "", targetNumber);
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
      receiver: item['receiver'],
    );
    item['statusCode'] = status;
    phoneNumberList.refresh();
    storage.write("phoneNumberList", jsonEncode(phoneNumberList));
  }

  Future<List<sms_inbox.SmsMessage>> fetchSmsFrom0801() async {
    final sms_inbox.SmsQuery query = sms_inbox.SmsQuery();
    List<sms_inbox.SmsMessage> messages = await query.querySms(
      kinds: [sms_inbox.SmsQueryKind.inbox],
      address: "0801",
    );

    for (var element in messages) {
      bool exists = phoneNumberList.any((e) => e["phone"] == element.address && e["date"] == element.date.toString());

      if (!exists) {
        parseSmsAndAddToList(
          element.body ?? "",
          element.date.toString(),
          element.address ?? "",
          simSlot: null,
        );
      }
    }
    return messages;
  }

  void getPhoneNumbersList() {
    final result = storage.read('phoneNumberList') ?? "[]";
    phoneNumberList.value = List<Map<String, dynamic>>.from(jsonDecode(result));
  }

  Future<void> addPhoneNumber({
    required String phone,
    required String dateAndTime,
    required String money,
    int? simSlot,
    String? id,
  }) async {
    String uniqueId = id ?? "$phone-$money-${dateAndTime.substring(0, 16)}";

    bool exists = phoneNumberList.any((e) => e["id"] == uniqueId);
    if (!exists) {
      final String? phoneNumber = await getPhoneNumberWithRetries();

      int status = await sendTransactionSMS(sender: phone, amount: money, receiver: phoneNumber);

      phoneNumberList.add({
        "id": uniqueId,
        "phone": phone,
        "money": money,
        "date": dateAndTime,
        "simSlot": simSlot,
        "receiver": phoneNumber,
        "statusCode": status,
      });

      storage.write("phoneNumberList", jsonEncode(phoneNumberList));
    }
  }
}
