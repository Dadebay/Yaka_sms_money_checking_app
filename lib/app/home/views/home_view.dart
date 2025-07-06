import 'package:easy_sms_receiver/easy_sms_receiver.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:sms_app/app/initialize/agree_button.dart';
import 'package:sms_app/app/initialize/color_constants.dart';
import 'package:sms_app/app/initialize/custom_app_bar.dart';

import '../controllers/home_controller.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final HomeController _controller = Get.put(HomeController());
  final easySmsReceiver = EasySmsReceiver.instance;
  final String targetNumber = "0801";

  @override
  void initState() {
    super.initState();
    listenForSms();
    _controller.readOldSmsFromStorage();
  }

  void listenForSms() {
    easySmsReceiver.listenIncomingSms(
      onNewMessage: (message) {
        String senderNumber = message.address ?? "";
        if (senderNumber.endsWith(targetNumber)) {
          _controller.parseSmsAndAddToList(
            message.body!,
            DateTime.now().toString(),
            senderNumber,
            simSlot: null,
          );
        }
      },
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: "SMS страница",
        showBackButton: false,
        actionButton: Row(
          children: [
            IconButton(
              onPressed: showStatusLegendDialog,
              icon: const Icon(Icons.info_outline, color: ColorConstants.whiteColor),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: AgreeButton(
          onTap: _controller.fetchSmsFrom0801,
          text: "Получить SMS",
        ),
      ),
      body: Obx(() {
        if (_controller.phoneNumberList.isEmpty) {
          return Center(
            child: Text("Нет SMS", style: context.general.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold)),
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ListView.builder(
            itemCount: _controller.phoneNumberList.length,
            reverse: true,
            shrinkWrap: true,
            itemBuilder: (context, index) {
              final item = _controller.phoneNumberList[index];
              final int statusCode = item["statusCode"] ?? 0;
              final Color backgroundColor = statusCode == 200 || statusCode == 201 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1);

              return Container(
                margin: context.padding.onlyTopNormal,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text("  ${index + 1}", style: context.general.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.bold, fontSize: 20)),
                    Expanded(
                      child: ListTile(
                        title: Row(
                          children: [
                            Expanded(child: Text("+${item["phone"]}", style: context.general.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.bold, fontSize: 20))),
                            Text("${item["money"]} м", style: context.general.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.bold, fontSize: 20)),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(child: Text(item["date"].toString().substring(0, 16).replaceAll(' ', '     Sagat: '), style: context.general.textTheme.bodyLarge!.copyWith(color: ColorConstants.greyColor))),
                            statusCode == 200 || statusCode == 201
                                ? const SizedBox.shrink()
                                : IconButton(
                                    icon: const Icon(Icons.refresh, color: Colors.red),
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
