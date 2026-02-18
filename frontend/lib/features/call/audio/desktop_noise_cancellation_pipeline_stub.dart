// Stub for platforms where desktop NC pipeline is not used (e.g. web).
// The real implementation is in desktop_noise_cancellation_pipeline_io.dart.

import 'package:talktime/features/call/webrtc/types.dart';

/// No-op implementation when not on desktop (e.g. web).
class DesktopNoiseCancellationPipeline {
  Future<void> start({String? deviceId}) async {}

  Future<void> stop() async {}

  /// Returns null; no pushable track without native bridge.
  IMediaStreamTrack? getTrack() => null;

  bool get isRunning => false;
}
