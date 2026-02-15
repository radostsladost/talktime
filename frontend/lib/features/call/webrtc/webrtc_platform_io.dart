// IO (mobile/desktop): choose Android bridge on Android, Flutter WebRTC otherwise.

import 'dart:io';

import 'types.dart';
import 'android_webrtc_impl.dart';
import 'flutter_webrtc_impl.dart';

IWebRTCPlatform getWebRTCPlatform() {
  if (Platform.isAndroid) {
    return AndroidGoogleWebRTCPlatform();
  }
  return FlutterWebRTCPlatform();
}
