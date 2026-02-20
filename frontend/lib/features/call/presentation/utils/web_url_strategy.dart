import 'package:talktime/core/config/environment.dart';

/// Stub for non-web platforms. These are no-ops.

String getWebOrigin() => Environment.webBaseUrl;

void pushBrowserUrl(String path, String title) {
  // no-op on non-web platforms
}
