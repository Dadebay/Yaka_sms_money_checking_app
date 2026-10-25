// ignore_for_file: file_names, must_be_immutable, use_key_in_widget_constructors

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:sms_app/app/initialize/color_constants.dart';

class PhoneNumberTextField extends StatelessWidget {
  final TextEditingController controller;
  final bool? disabled;
  final FocusNode mineFocus;
  final FocusNode requestFocus;
  const PhoneNumberTextField({required this.mineFocus, required this.controller, required this.requestFocus, this.disabled});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: context.padding.verticalNormal,
      child: TextFormField(
        enabled: disabled ?? true,
        style: context.general.textTheme.titleLarge!.copyWith(color: ColorConstants.blackColor),
        cursorColor: ColorConstants.blackColor,
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.number,
        focusNode: mineFocus,
        controller: controller,
        validator: (value) {
          if (value!.isEmpty) {
            return 'errorEmpty'.tr;
          } else if (value.length != 8) {
            return 'errorPhoneCount'.tr;
          }
          return null;
        },
        inputFormatters: [
          LengthLimitingTextInputFormatter(8),
        ],
        onEditingComplete: () {
          requestFocus.requestFocus();
        },
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          errorMaxLines: 2,
          errorStyle: context.general.textTheme.titleLarge!.copyWith(color: ColorConstants.redColor),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Text(
              '+ 993',
              style: context.general.textTheme.titleLarge!.copyWith(color: ColorConstants.greyColor.withValues(alpha: .5), fontWeight: FontWeight.w500),
            ),
          ),
          contentPadding: context.padding.normal,
          prefixIconConstraints: const BoxConstraints(minWidth: 80),
          hintText: '65 656565 ',
          fillColor: ColorConstants.primaryColor,
          alignLabelWithHint: true,
          hintStyle: context.general.textTheme.titleLarge!.copyWith(color: ColorConstants.greyColor.withValues(alpha: .5), fontWeight: FontWeight.w500),
          border: OutlineInputBorder(
            borderRadius: context.border.normalBorderRadius,
            borderSide: const BorderSide(color: ColorConstants.greyColor, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: context.border.normalBorderRadius,
            borderSide: BorderSide(color: ColorConstants.greyColor.withValues(alpha: .3), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: context.border.normalBorderRadius,
            borderSide: const BorderSide(color: ColorConstants.primaryColor, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: context.border.normalBorderRadius,
            borderSide: const BorderSide(color: ColorConstants.primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: context.border.normalBorderRadius,
            borderSide: const BorderSide(color: ColorConstants.redColor, width: 2),
          ),
        ),
      ),
    );
  }
}
