import 'package:web/web.dart' as web;

String getWebOrigin() => web.window.location.origin;

void pushBrowserUrl(String path, String title) {
  web.window.history.pushState(null, title, path);
}
