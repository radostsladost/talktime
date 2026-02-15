// Single entry point for WebRTC platform. Exports types and platform getter.
// On web: only Flutter WebRTC. On IO: Android impl on Android, Flutter WebRTC elsewhere.

export 'types.dart';

import 'types.dart';
import 'webrtc_platform_io.dart' if (dart.library.html) 'webrtc_platform_web.dart' as impl;

IWebRTCPlatform getWebRTCPlatform() => impl.getWebRTCPlatform();
