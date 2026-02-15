// Web: only Flutter WebRTC implementation (no dart:io, no Android impl).

import 'types.dart';
import 'flutter_webrtc_impl.dart';

IWebRTCPlatform getWebRTCPlatform() => FlutterWebRTCPlatform();
