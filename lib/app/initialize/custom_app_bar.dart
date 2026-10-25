import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:sms_app/app/initialize/color_constants.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final Widget? actionButton;
  final String? subtitle;
  final PreferredSizeWidget? bottom;

  const CustomAppBar({super.key, required this.title, required this.showBackButton, this.actionButton, this.subtitle, this.bottom});

  bool get _hasSubtitle => subtitle != null && subtitle!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title.tr,
      style: context.general.textTheme.headlineMedium!.copyWith(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
    );
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
                Icons.arrow_circle_left_outlined,
                color: ColorConstants.whiteColor,
              ),
            )
          : null,
      title: _hasSubtitle
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                titleText,
                Text(
                  subtitle!,
                  style: context.general.textTheme.bodySmall!.copyWith(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            )
          : titleText,
      actions: [
        actionButton ?? const SizedBox.shrink(),
      ],
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight((_hasSubtitle ? kToolbarHeight + 16 : kToolbarHeight) + (bottom?.preferredSize.height ?? 0));
}
