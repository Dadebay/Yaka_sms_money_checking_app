import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:sms_app/app/initialize/color_constants.dart';
import 'package:sms_app/app/initialize/custom_app_bar.dart';
import 'package:sms_app/app/services/transaction_log_store.dart';

/// Shows the recorded log of failed transaction requests: for each failure,
/// the request body and (masked) headers, the response status code and the
/// server message or exception text.
class TransactionLogView extends StatefulWidget {
  const TransactionLogView({super.key});

  @override
  State<TransactionLogView> createState() => _TransactionLogViewState();
}

class _TransactionLogViewState extends State<TransactionLogView> {
  final TransactionLogStore _store = TransactionLogStore();
  late List<Map<String, dynamic>> _logs;

  static const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

  @override
  void initState() {
    super.initState();
    _logs = _store.read();
  }

  void _confirmClear() {
    Get.defaultDialog(
      title: "Очистить журнал",
      middleText: "Удалить все записи об ошибках?",
      textConfirm: "Да",
      textCancel: "Нет",
      confirmTextColor: Colors.white,
      onConfirm: () {
        _store.clear();
        Get.back();
        setState(() => _logs = []);
      },
    );
  }

  String _formatTimestamp(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String _entryAsText(Map<String, dynamic> entry) => _pretty.convert(entry);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: "Журнал ошибок",
        showBackButton: true,
        actionButton: _logs.isEmpty
            ? null
            : IconButton(
                onPressed: _confirmClear,
                tooltip: "Очистить журнал",
                icon: const Icon(Icons.delete_outline,
                    color: ColorConstants.whiteColor),
              ),
      ),
      body: _logs.isEmpty
          ? Center(
              child: Text("Нет ошибок",
                  style: context.general.textTheme.titleLarge!
                      .copyWith(fontWeight: FontWeight.bold)),
            )
          : ListView.builder(
              padding: context.padding.normal,
              itemCount: _logs.length,
              itemBuilder: (context, index) => _buildLogCard(_logs[index]),
            ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> entry) {
    final int statusCode = (entry['statusCode'] ?? 0) as int;
    final String timestamp = _formatTimestamp(entry['timestamp'] as String?);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text("HTTP $statusCode",
                      style: context.general.textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.bold, color: Colors.red)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(timestamp,
                      style: context.general.textTheme.bodySmall!
                          .copyWith(color: ColorConstants.greyColor)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: "Копировать",
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _entryAsText(entry)));
                    Get.snackbar(
                      'Скопировано',
                      'Запись скопирована в буфер обмена',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            _section(context, "Ответ сервера",
                (entry['responseMessage'] ?? '').toString()),
            _section(context, "Тело запроса",
                _pretty.convert(entry['requestBody'] ?? {})),
            _section(context, "Заголовки",
                _pretty.convert(entry['requestHeaders'] ?? {})),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String content) {
    if (content.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: context.general.textTheme.bodySmall!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ColorConstants.greyColor)),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(content,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
