// ignore_for_file: file_names, must_be_immutable

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:sms_app/app/home/controllers/home_controller.dart';
import 'package:sms_app/app/initialize/color_constants.dart';
import 'package:sms_app/app/initialize/widget_sizes.dart';

class AgreeButton extends StatelessWidget {
  final Function() onTap;
  final String? text;
  final HomeController signInPageController = Get.find();

  AgreeButton({
    required this.onTap,
    Key? key,
    this.text,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Obx(() {
        return animatedContaner(context);
      }),
    );
  }

  AnimatedContainer animatedContaner(BuildContext context) {
    return AnimatedContainer(
      decoration: BoxDecoration(borderRadius: context.border.normalBorderRadius, color: ColorConstants.primaryColor),
      padding: EdgeInsets.symmetric(horizontal: signInPageController.agreeButton.value ? 0 : 8),
      width: signInPageController.agreeButton.value ? 60 : Get.size.width,
      duration: const Duration(milliseconds: 1000),
      height: WidgetSizes.size50.value,
      alignment: Alignment.center,
      child: signInPageController.agreeButton.value
          ? _loading()
          : Text(
              text?.tr ?? 'agree'.tr,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.general.textTheme.titleLarge!.copyWith(color: ColorConstants.whiteColor, fontWeight: FontWeight.w800),
            ),
    );
  }

  Center _loading() {
    return Center(
      child: SizedBox(
        width: WidgetSizes.size32.value,
        height: WidgetSizes.size32.value,
        child: const CircularProgressIndicator(
          color: ColorConstants.whiteColor,
        ),
      ),
    );
  }
}
