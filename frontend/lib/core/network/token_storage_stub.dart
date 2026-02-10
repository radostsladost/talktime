import 'package:shared_preferences/shared_preferences.dart';

/// Stub implementation: uses SharedPreferences only (mobile/desktop).
/// For web, token_storage_web.dart adds cookie backup.
Future<String?> getStoredString(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(key);
}

Future<void> setStoredString(String key, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
}

Future<void> removeStoredString(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(key);
}
