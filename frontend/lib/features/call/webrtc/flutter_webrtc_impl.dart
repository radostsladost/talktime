// Flutter WebRTC implementation of the WebRTC platform interfaces.
// Used on iOS, Web, and Desktop (non-Android).

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import 'types.dart';

// ============== Track wrapper ==============

class MediaStreamTrackWrapper implements IMediaStreamTrack {
  MediaStreamTrackWrapper(this._track) {
    _track.onMute = () => onMute?.call();
    _track.onUnMute = () => onUnMute?.call();
    _track.onEnded = () => onEnded?.call();
  }
  final webrtc.MediaStreamTrack _track;

  @override
  String get kind => _track.kind ?? '';

  @override
  String? get label => _track.label;

  @override
  bool get enabled => _track.enabled;

  @override
  set enabled(bool value) => _track.enabled = value;

  @override
  bool get muted => _track.muted ?? false;

  @override
  void stop() => _track.stop();

  @override
  void Function()? onMute;

  @override
  void Function()? onUnMute;

  @override
  void Function()? onEnded;

  webrtc.MediaStreamTrack get nativeTrack => _track;
}

// ============== Stream wrapper ==============

class MediaStreamWrapper implements IMediaStream {
  /// Use [wrap] to get a cached wrapper for identity-stable stream objects.
  MediaStreamWrapper(this._stream) {
    _wireNativeEvents();
  }

  MediaStreamWrapper._internal(this._stream) {
    _wireNativeEvents();
  }

  final webrtc.MediaStream _stream;

  // Cache: same native stream -> same wrapper, so callbacks stay attached.
  static final Map<String, MediaStreamWrapper> _streamCache = {};

  /// Get or create a wrapper for [s], preserving identity across onTrack calls.
  static MediaStreamWrapper wrap(webrtc.MediaStream s) {
    return _streamCache.putIfAbsent(s.id, () => MediaStreamWrapper._internal(s));
  }

  void _wireNativeEvents() {
    _stream.onAddTrack = (webrtc.MediaStreamTrack nativeTrack) {
      final wrapped = _wrapTrack(nativeTrack);
      onAddTrack?.call(this, wrapped);
    };
    _stream.onRemoveTrack = (webrtc.MediaStreamTrack nativeTrack) {
      final wrapped = _wrapTrack(nativeTrack);
      onRemoveTrack?.call(this, wrapped);
    };
  }

  @override
  String get id => _stream.id;

  @override
  List<IMediaStreamTrack> getTracks() =>
      _stream.getTracks().map((t) => _wrapTrack(t)).toList();

  @override
  List<IMediaStreamTrack> getAudioTracks() =>
      _stream.getAudioTracks().map((t) => _wrapTrack(t)).toList();

  @override
  List<IMediaStreamTrack> getVideoTracks() =>
      _stream.getVideoTracks().map((t) => _wrapTrack(t)).toList();

  static final Map<webrtc.MediaStreamTrack, MediaStreamTrackWrapper> _trackCache = {};

  static MediaStreamTrackWrapper _wrapTrack(webrtc.MediaStreamTrack t) {
    return _trackCache.putIfAbsent(t, () => MediaStreamTrackWrapper(t));
  }

  @override
  Future<void> addTrack(IMediaStreamTrack track) async {
    if (track is MediaStreamTrackWrapper) {
      await _stream.addTrack(track.nativeTrack);
    }
  }

  @override
  Future<void> removeTrack(IMediaStreamTrack track) async {
    if (track is MediaStreamTrackWrapper) {
      try {
        await _stream.removeTrack(track.nativeTrack);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _streamCache.remove(_stream.id);
    _stream.dispose();
  }

  @override
  AddTrackEventCallback? onAddTrack;

  @override
  RemoveTrackEventCallback? onRemoveTrack;

  webrtc.MediaStream get nativeStream => _stream;
}

// ============== Transceiver / Sender wrappers ==============

class RTPSenderWrapper implements IRTPSender {
  RTPSenderWrapper(this._sender);
  final webrtc.RTCRtpSender _sender;

  @override
  IMediaStreamTrack? get track {
    final t = _sender.track;
    return t == null ? null : MediaStreamWrapper._wrapTrack(t);
  }

  @override
  Future<void> replaceTrack(IMediaStreamTrack? track) async {
    await _sender.replaceTrack(
      track == null ? null : (track as MediaStreamTrackWrapper).nativeTrack,
    );
  }
}

class RTPTransceiverWrapper implements IRTPTransceiver {
  RTPTransceiverWrapper(this._transceiver);
  final webrtc.RTCRtpTransceiver _transceiver;

  @override
  IRTPSender get sender => RTPSenderWrapper(_transceiver.sender);

  @override
  IMediaStreamTrack? get receiverTrack {
    final t = _transceiver.receiver.track;
    return t == null ? null : MediaStreamWrapper._wrapTrack(t);
  }
}

// ============== State mapping ==============

RTCSignalingStateDto _signalingStateFromNative(webrtc.RTCSignalingState s) {
  switch (s) {
    case webrtc.RTCSignalingState.RTCSignalingStateStable:
      return RTCSignalingStateDto.stable;
    case webrtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer:
      return RTCSignalingStateDto.haveLocalOffer;
    case webrtc.RTCSignalingState.RTCSignalingStateHaveRemoteOffer:
      return RTCSignalingStateDto.haveRemoteOffer;
    case webrtc.RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer:
      return RTCSignalingStateDto.haveLocalPranswer;
    case webrtc.RTCSignalingState.RTCSignalingStateHaveRemotePrAnswer:
      return RTCSignalingStateDto.haveRemotePranswer;
    case webrtc.RTCSignalingState.RTCSignalingStateClosed:
      return RTCSignalingStateDto.closed;
  }
}

RTCIceConnectionStateDto _iceStateFromNative(webrtc.RTCIceConnectionState s) {
  switch (s) {
    case webrtc.RTCIceConnectionState.RTCIceConnectionStateNew:
      return RTCIceConnectionStateDto.new_;
    case webrtc.RTCIceConnectionState.RTCIceConnectionStateChecking:
      return RTCIceConnectionStateDto.checking;
    case webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected:
      return RTCIceConnectionStateDto.connected;
    case webrtc.RTCIceConnectionState.RTCIceConnectionStateCompleted:
      return RTCIceConnectionStateDto.completed;
    case webrtc.RTCIceConnectionState.RTCIceConnectionStateFailed:
      return RTCIceConnectionStateDto.failed;
    case webrtc.RTCIceConnectionState.RTCIceConnectionStateDisconnected:
      return RTCIceConnectionStateDto.disconnected;
    case webrtc.RTCIceConnectionState.RTCIceConnectionStateClosed:
      return RTCIceConnectionStateDto.closed;
    default:
      return RTCIceConnectionStateDto.new_;
  }
}

// ============== PeerConnection wrapper ==============

class PeerConnectionWrapper implements IPeerConnection {
  PeerConnectionWrapper(this._pc);
  final webrtc.RTCPeerConnection _pc;

  @override
  Future<void> addTrack(IMediaStreamTrack track, IMediaStream stream) async {
    if (track is MediaStreamTrackWrapper && stream is MediaStreamWrapper) {
      await _pc.addTrack(track.nativeTrack, stream.nativeStream);
    }
  }

  @override
  Future<RTCSessionDescriptionDto> createOffer() async {
    final offer = await _pc.createOffer();
    return RTCSessionDescriptionDto(offer.sdp, offer.type ?? 'offer');
  }

  @override
  Future<RTCSessionDescriptionDto> createAnswer() async {
    final answer = await _pc.createAnswer();
    return RTCSessionDescriptionDto(answer.sdp, answer.type ?? 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescriptionDto description) async {
    await _pc.setLocalDescription(
      webrtc.RTCSessionDescription(description.sdp, description.type),
    );
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescriptionDto description) async {
    await _pc.setRemoteDescription(
      webrtc.RTCSessionDescription(description.sdp, description.type),
    );
  }

  @override
  Future<void> addIceCandidate(RTCIceCandidateDto candidate) async {
    await _pc.addCandidate(
      webrtc.RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid ?? '',
        candidate.sdpMLineIndex ?? 0,
      ),
    );
  }

  @override
  Future<RTCSignalingStateDto> getSignalingState() async {
    final s = await _pc.getSignalingState();
    if (s == null) return RTCSignalingStateDto.stable;
    return _signalingStateFromNative(s);
  }

  @override
  Future<RTCSessionDescriptionDto?> getRemoteDescription() async {
    final desc = await _pc.getRemoteDescription();
    return desc == null ? null : RTCSessionDescriptionDto(desc.sdp, desc.type ?? '');
  }

  @override
  Future<List<IRTPTransceiver>> getTransceivers() async {
    final list = await _pc.getTransceivers();
    return list.map((t) => RTPTransceiverWrapper(t)).toList();
  }

  @override
  Future<void> close() => _pc.close();

  @override
  void Function(RTCTrackEventDto event)? onTrack;

  @override
  void Function(RTCIceCandidateDto candidate)? onIceCandidate;

  @override
  void Function(RTCIceConnectionStateDto state)? onIceConnectionState;
}

// ============== Video renderer wrapper ==============

class VideoRendererWrapper implements IVideoRenderer {
  VideoRendererWrapper() : _renderer = webrtc.RTCVideoRenderer();

  final webrtc.RTCVideoRenderer _renderer;

  @override
  Future<void> initialize() => _renderer.initialize();

  @override
  void dispose() => _renderer.dispose();

  @override
  IMediaStream? get srcObject {
    final s = _renderer.srcObject;
    return s == null ? null : MediaStreamWrapper(s);
  }

  @override
  set srcObject(IMediaStream? value) {
    _renderer.srcObject =
        value == null ? null : (value as MediaStreamWrapper).nativeStream;
  }

  @override
  bool get muted => _renderer.muted;

  @override
  set muted(bool value) => _renderer.muted = value;

  @override
  Future<void> audioOutput(String? deviceId) async {
    if (deviceId != null) {
      try {
        await _renderer.audioOutput(deviceId);
      } catch (_) {}
    }
  }

  @override
  Widget buildView({
    bool mirror = false,
    VideoObjectFit objectFit = VideoObjectFit.cover,
  }) {
    return webrtc.RTCVideoView(
      _renderer,
      mirror: mirror,
      objectFit: objectFit == VideoObjectFit.contain
          ? webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
          : webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

// ============== Platform ==============

class FlutterWebRTCPlatform implements IWebRTCPlatform {
  @override
  Future<void> initialize() async {
    // No-op on non-Android; Android-specific init is in the Android impl.
  }

  @override
  Future<IMediaStream?> getUserMedia(Map<String, dynamic> constraints) async {
    final stream = await webrtc.navigator.mediaDevices.getUserMedia(constraints);
    return MediaStreamWrapper(stream);
  }

  @override
  Future<IMediaStream?> getDisplayMedia(Map<String, dynamic> constraints) async {
    final stream = await webrtc.navigator.mediaDevices.getDisplayMedia(constraints);
    return MediaStreamWrapper(stream);
  }

  @override
  Future<IPeerConnection> createPeerConnection(Map<String, dynamic> config) async {
    final pc = await webrtc.createPeerConnection(config);
    final wrapper = PeerConnectionWrapper(pc);

    pc.onTrack = (webrtc.RTCTrackEvent event) {
      final streams = event.streams;
      if (streams != null && streams.isNotEmpty) {
        final streamList = streams.map((s) => MediaStreamWrapper.wrap(s)).toList();
        final track = event.track;
        if (track != null) {
          wrapper.onTrack?.call(RTCTrackEventDto(streamList, MediaStreamWrapper._wrapTrack(track)));
        }
      }
    };

    pc.onIceCandidate = (candidate) {
      wrapper.onIceCandidate?.call(RTCIceCandidateDto(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ));
    };

    pc.onIceConnectionState = (state) {
      wrapper.onIceConnectionState?.call(_iceStateFromNative(state));
    };

    return wrapper;
  }

  @override
  Future<List<MediaDeviceInfoDto>> enumerateDevices(String kind) async {
    final devices = await webrtc.Helper.enumerateDevices(kind);
    return devices
        .map((d) => MediaDeviceInfoDto(
              deviceId: d.deviceId,
              label: d.label,
              kind: d.kind ?? kind,
            ))
        .toList();
  }

  @override
  Future<void> setSpeakerphoneOn(bool on) async {
    await webrtc.Helper.setSpeakerphoneOn(on);
  }

  @override
  Future<List<DesktopCapturerSourceDto>> getDesktopSources() async {
    try {
      final sources = await webrtc.desktopCapturer.getSources(
        types: [webrtc.SourceType.Screen, webrtc.SourceType.Window],
        thumbnailSize: webrtc.ThumbnailSize(180, 80),
      );
      return sources
          .map((s) => DesktopCapturerSourceDto(
                id: s.id,
                name: s.name,
                thumbnailPath: '', // DesktopCapturerSource has thumbnail (bytes), not path
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  IVideoRenderer createVideoRenderer() => VideoRendererWrapper();
}
