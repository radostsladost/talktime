import 'package:talktime/features/call/webrtc/webrtc_platform.dart';

/// Stub: no echo reduction (used on non-web platforms).
/// Returns a no-op dispose callback.
void Function() startEchoReduction(
  IMediaStream remoteStream,
  IMediaStream localStream, {
  double delaySeconds = 0.3,
}) {
  return () {};
}
