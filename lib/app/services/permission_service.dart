import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request SMS read permission
  static Future<bool> requestSmsPermission() async {
    try {
      final status = await Permission.sms.request();

      if (status.isDenied) {
        print("❌ SMS permission denied");
        return false;
      } else if (status.isPermanentlyDenied) {
        print(
          "⚠️ SMS permission permanently denied - user needs to enable in settings",
        );
        openAppSettings();
        return false;
      } else if (status.isGranted) {
        print("✅ SMS permission granted");
        return true;
      } else if (status.isLimited) {
        print("⚠️ SMS permission limited");
        return true;
      }

      return false;
    } catch (e) {
      print("❌ Error requesting SMS permission: $e");
      return false;
    }
  }

  /// Request phone permission (READ_PHONE_STATE / READ_PHONE_NUMBERS), needed to
  /// read active SIM subscription info and SIM phone numbers.
  static Future<bool> requestPhonePermission() async {
    try {
      final status = await Permission.phone.request();
      if (status.isGranted || status.isLimited) {
        print("✅ Phone permission granted");
        return true;
      }
      print("⚠️ Phone permission not granted: $status");
      return false;
    } catch (e) {
      print("❌ Error requesting phone permission: $e");
      return false;
    }
  }

  /// Check if SMS permission is already granted
  static Future<bool> checkSmsPermission() async {
    try {
      final status = await Permission.sms.status;
      return status.isGranted || status.isLimited;
    } catch (e) {
      print("❌ Error checking SMS permission: $e");
      return false;
    }
  }

  /// Get the current SMS permission status
  static Future<PermissionStatus> getSmsPermissionStatus() async {
    try {
      return await Permission.sms.status;
    } catch (e) {
      print("❌ Error getting SMS permission status: $e");
      return PermissionStatus.denied;
    }
  }

  /// Request multiple permissions at once (useful for future expansion)
  static Future<Map<Permission, PermissionStatus>> requestMultiplePermissions(
    List<Permission> permissions,
  ) async {
    try {
      return await permissions.request();
    } catch (e) {
      print("❌ Error requesting multiple permissions: $e");
      return {};
    }
  }

  /// Check all required permissions for the app
  static Future<bool> checkAllPermissions() async {
    try {
      final smsGranted = await checkSmsPermission();
      return smsGranted;
    } catch (e) {
      print("❌ Error checking all permissions: $e");
      return false;
    }
  }
}
