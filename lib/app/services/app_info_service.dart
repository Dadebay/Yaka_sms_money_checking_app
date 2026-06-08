import 'package:package_info_plus/package_info_plus.dart';

/// Holds app version + build info, loaded once at startup so widgets can read
/// it synchronously.
///
/// Version and build number come from [PackageInfo] (the `pubspec.yaml`
/// version). The build date/time is injected at build time via
/// `--dart-define=BUILD_TIME=...` — use `tool/build.sh` / `tool/run.sh`, which
/// stamp the current UTC time automatically. When the define is absent (e.g. a
/// plain `flutter run`), [buildTime] is null and the date is simply omitted.
class AppInfo {
  AppInfo._();

  static String version = '';
  static String buildNumber = '';
  static DateTime? buildTime;

  static Future<void> load() async {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
    buildNumber = info.buildNumber;
    const raw = String.fromEnvironment('BUILD_TIME');
    if (raw.isNotEmpty) buildTime = DateTime.tryParse(raw)?.toLocal();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// e.g. "v1.0.3 (4) • 2026-06-08 14:30" — the date is dropped when the build
  /// timestamp is unavailable.
  static String get subtitle {
    final buffer = StringBuffer('v$version');
    if (buildNumber.isNotEmpty) buffer.write(' ($buildNumber)');
    final dt = buildTime;
    if (dt != null) {
      final date = '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
      final time = '${_two(dt.hour)}:${_two(dt.minute)}';
      buffer.write(' • $date $time');
    }
    return buffer.toString();
  }
}
