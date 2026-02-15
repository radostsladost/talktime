import 'package:talktime/features/call/webrtc/webrtc_platform.dart';

import 'echo_reduction_stub.dart'
    if (dart.library.html) 'echo_reduction_web_impl.dart' as echo_reduction;

/// Starts receive-side echo reduction: plays (remote_audio - delayed_local_audio)
/// so the PC hears less of its own voice. Web only; no-op on other platforms.
/// Returns a dispose callback. [delaySeconds] ~0.2–0.4 for typical RTT.
void Function() startEchoReduction(
  IMediaStream remoteStream,
  IMediaStream localStream, {
  double delaySeconds = 0.3,
}) =>
    echo_reduction.startEchoReduction(
      remoteStream,
      localStream,
      delaySeconds: delaySeconds,
    );
