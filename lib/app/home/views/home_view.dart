import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:sms_app/app/initialize/color_constants.dart';
import 'package:sms_app/app/initialize/custom_app_bar.dart';
import 'package:sms_app/app/services/app_info_service.dart';
import 'package:sms_app/app/services/sim_service.dart';

import '../controllers/home_controller.dart';
import 'sim_settings_view.dart';
import 'transaction_log_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  final HomeController _controller = Get.put(HomeController());
  final String targetNumber = "0801";
  StreamSubscription<IncomingSms>? _smsSubscription;

  /// Fills 0->1 over one cycle period as a countdown to the next sync; reset
  /// each time a sync finishes so it stays aligned with the real cycle.
  late final AnimationController _cycleAnim;
  Worker? _syncWorker;

  @override
  void initState() {
    super.initState();
    _cycleAnim = AnimationController(
      vsync: this,
      duration: const Duration(minutes: 1),
    )..forward();
    _syncWorker = ever(_controller.isSyncing, (bool syncing) {
      if (!syncing) _cycleAnim.forward(from: 0);
    });
    listenForSms();
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    _syncWorker?.dispose();
    _cycleAnim.dispose();
    super.dispose();
  }

  void listenForSms() {
    _smsSubscription = _controller.simService.incomingSms().listen((message) {
      if (message.address.endsWith(targetNumber)) {
        print('new message ${message.body}');
        _controller.parseSmsAndAddToList(
          message.body,
          message.dateMillis,
          message.address,
          message.subId,
        );
      }
    });
  }

  String _formatDate(dynamic dateMillis) {
    final int millis = (dateMillis is int)
        ? dateMillis
        : int.tryParse(dateMillis?.toString() ?? '') ?? 0;
    if (millis == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${dt.year}-${two(dt.month)}-${two(dt.day)}';
    final time = '${two(dt.hour)}:${two(dt.minute)}';
    return '$date     Sagat: $time';
  }

  void showStatusLegendDialog() {
    Get.defaultDialog(
      title: "Обозначения статуса",
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 20, height: 20, color: Colors.green),
                const SizedBox(width: 10),
                const Text("Успешно отправлено"),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(width: 20, height: 20, color: Colors.black),
                const SizedBox(width: 10),
                const Text("Пользователь не найден"),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(width: 20, height: 20, color: Colors.red),
                const SizedBox(width: 10),
                const Text("Ошибка при отправке (другие коды)"),
              ],
            ),
          ],
        ),
      ),
      textConfirm: "Закрыть",
      confirmTextColor: Colors.white,
    );
  }

  void confirmFetchSms() {
    Get.defaultDialog(
      title: "Получить SMS",
      middleText: "Вы действительно хотите получить SMS заново?",
      textConfirm: "Да",
      textCancel: "Нет",
      confirmTextColor: Colors.white,
      onConfirm: () {
        Get.back();
        _controller.fetchSmsFrom0801();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: "SMS страница",
        subtitle: AppInfo.subtitle,
        showBackButton: false,
        actionButton: Row(
          children: [
            IconButton(
              onPressed: showStatusLegendDialog,
              icon: const Icon(Icons.info_outline,
                  color: ColorConstants.whiteColor),
            ),
            IconButton(
              onPressed: () => Get.to(() => const SimSettingsView()),
              icon:
                  const Icon(Icons.sim_card, color: ColorConstants.whiteColor),
            ),
            IconButton(
              onPressed: () => Get.to(() => const TransactionLogView()),
              tooltip: "Журнал ошибок",
              icon: const Icon(Icons.receipt_long,
                  color: ColorConstants.whiteColor),
            ),
            IconButton(
              onPressed: confirmFetchSms,
              tooltip: "Получить SMS",
              icon: const Icon(Icons.download_rounded,
                  color: ColorConstants.whiteColor),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Obx(
            () => _controller.isSyncing.value
                // Active sync: indeterminate animated bar.
                ? const LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  )
                // Idle: countdown bar filling toward the next cycle.
                : AnimatedBuilder(
                    animation: _cycleAnim,
                    builder: (_, __) => LinearProgressIndicator(
                      value: _cycleAnim.value,
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Colors.white70),
                    ),
                  ),
          ),
        ),
      ),
      body: Obx(() {
        if (_controller.phoneNumberList.isEmpty) {
          return Center(
            child: Text("Нет SMS",
                style: context.general.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.bold)),
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ListView.builder(
            padding:
                const EdgeInsets.only(top: 20, right: 20, left: 20, bottom: 80),
            itemCount: _controller.phoneNumberList.length,
            reverse: true,
            shrinkWrap: true,
            itemBuilder: (context, index) {
              final item = _controller.phoneNumberList[index];
              final int statusCode = item["statusCode"] ?? 0;
              final bool isSuccess = statusCode == 200 || statusCode == 201;
              final bool isPending = statusCode == 0;
              final Color backgroundColor = isSuccess
                  ? Colors.green.withOpacity(0.1)
                  : isPending
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1);

              return Container(
                margin: context.padding.onlyTopNormal,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text("  ${index + 1}",
                        style: context.general.textTheme.bodyLarge!.copyWith(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    Expanded(
                      child: ListTile(
                        title: Row(
                          children: [
                            Expanded(
                                child: Text("+${item["phone"]}",
                                    style: context.general.textTheme.bodyLarge!
                                        .copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18))),
                            Text("${item["money"]} м",
                                style: context.general.textTheme.bodyLarge!
                                    .copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18)),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                                child: Text(_formatDate(item["dateMillis"]),
                                    style: context.general.textTheme.bodyLarge!
                                        .copyWith(
                                            color: ColorConstants.greyColor))),
                            if (isPending)
                              IconButton(
                                onPressed: () => _controller.retrySmsPost(item),
                                icon: const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.orange),
                                ),
                              )
                            else if (!isSuccess)
                              IconButton(
                                icon: const Icon(Icons.refresh,
                                    color: Colors.red),
                                onPressed: () => _controller.retrySmsPost(item),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
