import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:sms_app/app/initialize/color_constants.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final Widget? actionButton;

  const CustomAppBar({super.key, required this.title, required this.showBackButton, this.actionButton});
  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: ColorConstants.primaryColor,
      scrolledUnderElevation: 0.0,
      elevation: 0.0,
      centerTitle: false,
      systemOverlayStyle: const SystemUiOverlayStyle(statusBarColor: ColorConstants.primaryColor, statusBarIconBrightness: Brightness.dark),
      leading: showBackButton
          ? IconButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: const Icon(
                IconlyLight.arrowLeftCircle,
                color: ColorConstants.whiteColor,
              ),
            )
          : null,
      title: Text(
        title.tr,
        style: context.general.textTheme.headlineMedium!.copyWith(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
      ),
      actions: [
        actionButton ?? const SizedBox.shrink(),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
