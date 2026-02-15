// Web-only: receive-side echo reduction using Web Audio API.
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:talktime/features/call/webrtc/flutter_webrtc_impl.dart';
import 'package:talktime/features/call/webrtc/webrtc_platform.dart';
import 'package:web/web.dart' as web;

web.MediaStream _getJsStream(MediaStream stream) {
  final s = stream as dynamic;
  return s.jsStream as web.MediaStream;
}

void Function() startEchoReduction(
  IMediaStream remoteStream,
  IMediaStream localStream, {
  double delaySeconds = 0.3,
}) {
  web.MediaStream? remoteJs;
  web.MediaStream? localJs;
  try {
    if (remoteStream is MediaStreamWrapper && localStream is MediaStreamWrapper) {
      remoteJs = _getJsStream(remoteStream.nativeStream);
      localJs = _getJsStream(localStream.nativeStream);
    } else {
      return () {};
    }
  } catch (_) {
    return () {};
  }

  late final web.AudioContext ctx;
  final audioTracksToRestore = <IMediaStreamTrack>[];

  try {
    ctx = web.AudioContext();

    final remoteSrc = ctx.createMediaStreamSource(remoteJs);
    final localSrc = ctx.createMediaStreamSource(localJs);
    final delay = ctx.createDelay(1.0);
    delay.delayTime.value = delaySeconds.clamp(0.0, 1.0);
    final gain = ctx.createGain();
    gain.gain.value = -1.0;

    remoteSrc.connect(ctx.destination);
    localSrc.connect(delay);
    delay.connect(gain);
    gain.connect(ctx.destination);

    for (final track in remoteStream.getAudioTracks()) {
      if (track.enabled) {
        track.enabled = false;
        audioTracksToRestore.add(track);
      }
    }
  } catch (_) {
    return () {};
  }

  return () {
    for (final track in audioTracksToRestore) {
      try {
        track.enabled = true;
      } catch (_) {}
    }
    try {
      ctx.close();
    } catch (_) {}
  };
}
