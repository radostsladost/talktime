import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

const _cookiePath = '/';
const _cookieMaxAgeDays = 365;

String? _readCookie(String name) {
  final cookie = web.document.cookie ?? '';
  if (cookie.isEmpty) return null;
  for (final part in cookie.split('; ')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final key = part.substring(0, eq).trim();
    if (key == name) {
      final value = part.substring(eq + 1).trim();
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }
  }
  return null;
}

void _writeCookie(String name, String value) {
  final encoded = Uri.encodeComponent(value);
  final maxAge = _cookieMaxAgeDays * 24 * 60 * 60;
  web.document.cookie = '$name=$encoded; path=$_cookiePath; max-age=$maxAge; SameSite=Lax';
}

void _deleteCookie(String name) {
  web.document.cookie = '$name=; path=$_cookiePath; max-age=0';
}

/// Web implementation: SharedPreferences + cookie backup so tokens survive
/// localStorage clears (e.g. browser data, private session).
Future<String?> getStoredString(String key) async {
  final prefs = await SharedPreferences.getInstance();
  var value = prefs.getString(key);
  if (value == null || value.isEmpty) {
    value = _readCookie(key);
    if (value != null && value.isNotEmpty) {
      await prefs.setString(key, value);
    }
  }
  return value;
}

Future<void> setStoredString(String key, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
  _writeCookie(key, value);
}

Future<void> removeStoredString(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(key);
  _deleteCookie(key);
}
