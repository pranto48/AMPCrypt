import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class VersionCheckService {
  static const String updateServerUrl = 'https://ampcrypt.itsupport.com.bd/desktop';

  /// Checks if a newer version is available online at https://ampcrypt.itsupport.com.bd/desktop
  static Future<bool> isUpdateAvailable() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version.isNotEmpty ? pkg.version : '0.65.0';

      // Query update version endpoint
      final response = await http.get(
        Uri.parse('$updateServerUrl/version.json'),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = data['version'] as String?;
        if (latestVersion != null && _isVersionHigher(latestVersion, currentVersion)) {
          return true;
        }
      }
    } catch (_) {
      // Offline or endpoint unavailable — do not display update banner
    }
    return false;
  }

  static bool _isVersionHigher(String latest, String current) {
    try {
      final lParts = latest.split('.').map(int.parse).toList();
      final cParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < lParts.length && i < cParts.length; i++) {
        if (lParts[i] > cParts[i]) return true;
        if (lParts[i] < cParts[i]) return false;
      }
      return lParts.length > cParts.length;
    } catch (_) {
      return false;
    }
  }
}
