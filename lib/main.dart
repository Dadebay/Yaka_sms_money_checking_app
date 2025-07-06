import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sms_app/app/home/controllers/home_controller.dart';
import 'package:sms_app/app/initialize/theme_contants.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/home/views/connection_chack_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  WakelockPlus.enable();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final HomeController homeController = Get.put(HomeController());

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: "YAKA sms app",
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling), child: child!),
      useInheritedMediaQuery: true,
      theme: AppThemes.lightTheme,
      fallbackLocale: const Locale('tr'),
      defaultTransition: Transition.fade,
      home: const ConnectionCheckpage(),
    );
  }
}
