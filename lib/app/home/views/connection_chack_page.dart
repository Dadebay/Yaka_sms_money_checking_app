// ignore_for_file: file_names, always_use_package_imports

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_app/app/home/views/home_view.dart';
import 'package:sms_app/app/initialize/agree_button.dart';
import 'package:sms_app/app/initialize/color_constants.dart';
import 'package:sms_app/app/initialize/string_constants.dart';
import 'package:sms_app/app/initialize/widget_sizes.dart';

class ConnectionCheckpage extends StatefulWidget {
  const ConnectionCheckpage({super.key});

  @override
  _ConnectionCheckpageState createState() => _ConnectionCheckpageState();
}

class _ConnectionCheckpageState extends State<ConnectionCheckpage> {
  @override
  void initState() {
    super.initState();
    checkConnection();
  }

  void checkConnection() async {
    final permissionStatus = await Permission.sms.request();
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        await Future.delayed(const Duration(seconds: 4), () {
          return Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeView()));
        });
      }
    } on SocketException catch (_) {
      showNoConnectionDialog(onRetry: () {}, context: context);
    }
  }

  static void showNoConnectionDialog({required VoidCallback onRetry, required BuildContext context}) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: context.border.normalBorderRadius),
        elevation: 0.0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.only(top: 100, left: 15, right: 15),
          decoration: BoxDecoration(color: ColorConstants.whiteColor, borderRadius: context.border.normalBorderRadius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                StringConstants.noConnectionTitle.tr,
                style: context.general.textTheme.bodyLarge,
              ),
              Padding(
                padding: context.padding.normal,
                child: Text(
                  'noConnection2'.tr,
                  textAlign: TextAlign.center,
                  style: context.general.textTheme.bodyMedium,
                ),
              ),
              AgreeButton(
                onTap: () {},
                text: StringConstants.onRetry,
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: context.border.highBorderRadius,
                child: FlutterLogo(
                  size: WidgetSizes.size180.value,
                ),
              ),
            ),
          ),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
