import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:talktime/core/config/environment.dart';
import 'package:talktime/features/call/presentation/utils/web_url_strategy.dart'
    if (dart.library.html) 'package:talktime/features/call/presentation/utils/web_url_strategy_real.dart';

/// Generates shareable call links and updates the browser URL on web.
class CallUrlHelper {
  /// Build the shareable deep link for a call using the invite key.
  /// The invite key is a 64-char secret that allows guests to join.
  static String getCallLink(String inviteKey) {
    if (kIsWeb) {
      final origin = getWebOrigin();
      return '$origin?key=$inviteKey';
    }
    return '${Environment.webBaseUrl}/?key=$inviteKey';
  }

  /// On web, push the invite-key URL into the browser address bar
  /// so the user can copy it directly.
  static void pushCallUrl(String inviteKey) {
    if (!kIsWeb) return;
    pushBrowserUrl('?key=$inviteKey', 'TalkTime Call');
  }

  /// Restore the browser URL to the root when leaving the call.
  static void restoreUrl() {
    if (!kIsWeb) return;
    pushBrowserUrl('/', 'TalkTime');
  }
}
