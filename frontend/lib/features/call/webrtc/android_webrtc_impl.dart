// Android implementation: Google WebRTC via MethodChannel bridge.
// Used only when Platform.isAndroid. No flutter_webrtc import.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'types.dart';

const _channelName = 'talktime_webrtc';
const _eventChannelName = 'talktime_webrtc_events';

final _methodChannel = MethodChannel(_channelName);
final EventChannel _eventChannel = EventChannel(_eventChannelName);

bool _eventChannelInitialized = false;

// Registry for peer connection callbacks (pcId -> wrapper)
final Map<String, _PeerConnectionWrapper> _pcRegistry = {};

void _initEventChannel() {
  if (_eventChannelInitialized) return;
  _eventChannelInitialized = true;
  _eventChannel.receiveBroadcastStream().listen((dynamic event) {
    if (event is! Map) return;
    final pcId = event['pcId'] as String?;
    if (pcId == null) return;
    final wrapper = _pcRegistry[pcId];
    if (wrapper == null) return;

    switch (event['event'] as String?) {
      case 'onTrack':
        final streamId = event['streamId'] as String?;
        final trackId = event['trackId'] as String?;
        final kind = event['kind'] as String? ?? 'video';
        if (streamId != null && trackId != null) {
          final track = _AndroidMediaStreamTrack(trackId, kind);
          final stream = _AndroidMediaStream(streamId, initialTracks: [track]);
          wrapper.onTrack?.call(RTCTrackEventDto([stream], track));
        }
        break;
      case 'onIceCandidate':
        wrapper.onIceCandidate?.call(RTCIceCandidateDto(
          event['candidate'] as String?,
          event['sdpMid'] as String?,
          (event['sdpMLineIndex'] as num?)?.toInt(),
        ));
        break;
      case 'onIceConnectionState':
        final stateStr = event['state'] as String?;
        wrapper.onIceConnectionState?.call(_iceStateFromString(stateStr));
        break;
    }
  }, onError: (Object e, StackTrace st) {
    debugPrint('talktime_webrtc event error: $e');
  });
}

RTCIceConnectionStateDto _iceStateFromString(String? s) {
  switch (s) {
    case 'new':
      return RTCIceConnectionStateDto.new_;
    case 'checking':
      return RTCIceConnectionStateDto.checking;
    case 'connected':
      return RTCIceConnectionStateDto.connected;
    case 'completed':
      return RTCIceConnectionStateDto.completed;
    case 'failed':
      return RTCIceConnectionStateDto.failed;
    case 'disconnected':
      return RTCIceConnectionStateDto.disconnected;
    case 'closed':
      return RTCIceConnectionStateDto.closed;
    default:
      return RTCIceConnectionStateDto.new_;
  }
}

RTCSignalingStateDto _signalingStateFromString(String? s) {
  switch (s) {
    case 'stable':
      return RTCSignalingStateDto.stable;
    case 'have-local-offer':
      return RTCSignalingStateDto.haveLocalOffer;
    case 'have-remote-offer':
      return RTCSignalingStateDto.haveRemoteOffer;
    case 'have-local-pranswer':
      return RTCSignalingStateDto.haveLocalPranswer;
    case 'have-remote-pranswer':
      return RTCSignalingStateDto.haveRemotePranswer;
    case 'closed':
      return RTCSignalingStateDto.closed;
    default:
      return RTCSignalingStateDto.stable;
  }
}

// ============== Android track (handle) ==============

class _AndroidMediaStreamTrack implements IMediaStreamTrack {
  _AndroidMediaStreamTrack(this.trackId, this._kind);

  final String trackId;
  final String _kind;
  bool _enabled = true;

  @override
  String get kind => _kind;

  @override
  String? get label => null;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    _methodChannel.invokeMethod('trackSetEnabled', {'trackId': trackId, 'enabled': value});
  }

  @override
  bool get muted => false;

  @override
  void stop() {
    _methodChannel.invokeMethod('trackStop', {'trackId': trackId});
  }

  @override
  void Function()? onMute;

  @override
  void Function()? onUnMute;

  @override
  void Function()? onEnded;
}

// ============== Android stream (handle) ==============

class _AndroidMediaStream implements IMediaStream {
  _AndroidMediaStream(this.streamId, {List<_AndroidMediaStreamTrack>? initialTracks}) {
    _cachedTracks = initialTracks ?? [];
  }

  final String streamId;
  List<_AndroidMediaStreamTrack> _cachedTracks = [];

  @override
  String get id => streamId;

  @override
  List<IMediaStreamTrack> getTracks() => List<IMediaStreamTrack>.from(_cachedTracks);

  @override
  List<IMediaStreamTrack> getAudioTracks() =>
      _cachedTracks.where((t) => t.kind == 'audio').toList();

  @override
  List<IMediaStreamTrack> getVideoTracks() =>
      _cachedTracks.where((t) => t.kind == 'video').toList();

  @override
  Future<void> addTrack(IMediaStreamTrack track) async {
    if (track is _AndroidMediaStreamTrack) {
      await _methodChannel.invokeMethod('streamAddTrack', {
        'streamId': streamId,
        'trackId': track.trackId,
      });
      if (!_cachedTracks.any((t) => t.trackId == track.trackId)) {
        _cachedTracks.add(track);
      }
    }
  }

  @override
  Future<void> removeTrack(IMediaStreamTrack track) async {
    if (track is _AndroidMediaStreamTrack) {
      try {
        await _methodChannel.invokeMethod('streamRemoveTrack', {
          'streamId': streamId,
          'trackId': track.trackId,
        });
        _cachedTracks.removeWhere((t) => t.trackId == track.trackId);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _methodChannel.invokeMethod('streamDispose', {'streamId': streamId});
  }

  @override
  AddTrackEventCallback? onAddTrack;

  @override
  RemoveTrackEventCallback? onRemoveTrack;
}

// ============== Android transceiver / sender (handle) ==============

class _AndroidRTPSender implements IRTPSender {
  _AndroidRTPSender(this._pcId, this._senderId, this._track);

  final String _pcId;
  final String _senderId;
  IMediaStreamTrack? _track;

  @override
  IMediaStreamTrack? get track => _track;

  @override
  Future<void> replaceTrack(IMediaStreamTrack? track) async {
    await _methodChannel.invokeMethod('senderReplaceTrack', {
      'pcId': _pcId,
      'senderId': _senderId,
      'trackId': track == null ? null : (track is _AndroidMediaStreamTrack ? track.trackId : null),
    });
    _track = track;
  }
}

class _AndroidRTPTransceiver implements IRTPTransceiver {
  _AndroidRTPTransceiver(this._pcId, this._senderId, this._kind, this._senderTrack, this._receiverTrack);

  final String _pcId;
  final String _senderId;
  final String _kind;
  final IMediaStreamTrack? _senderTrack;
  final IMediaStreamTrack? _receiverTrack;

  @override
  IRTPSender get sender => _AndroidRTPSender(_pcId, _senderId, _senderTrack);

  @override
  IMediaStreamTrack? get receiverTrack => _receiverTrack;

  @override
  String get kind => _kind;
}

// ============== Android peer connection (handle) ==============

class _PeerConnectionWrapper implements IPeerConnection {
  _PeerConnectionWrapper(this.pcId) {
    _pcRegistry[pcId] = this;
  }

  final String pcId;

  @override
  Future<void> addTrack(IMediaStreamTrack track, IMediaStream stream) async {
    if (track is _AndroidMediaStreamTrack && stream is _AndroidMediaStream) {
      await _methodChannel.invokeMethod('pcAddTrack', {
        'pcId': pcId,
        'trackId': track.trackId,
        'streamId': stream.streamId,
      });
    }
  }

  @override
  Future<RTCSessionDescriptionDto> createOffer() async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('pcCreateOffer', {'pcId': pcId});
    final m = result ?? {};
    return RTCSessionDescriptionDto(m['sdp'] as String?, m['type'] as String? ?? 'offer');
  }

  @override
  Future<RTCSessionDescriptionDto> createAnswer() async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('pcCreateAnswer', {'pcId': pcId});
    final m = result ?? {};
    return RTCSessionDescriptionDto(m['sdp'] as String?, m['type'] as String? ?? 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescriptionDto description) async {
    await _methodChannel.invokeMethod('pcSetLocalDescription', {
      'pcId': pcId,
      'sdp': description.sdp,
      'type': description.type,
    });
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescriptionDto description) async {
    await _methodChannel.invokeMethod('pcSetRemoteDescription', {
      'pcId': pcId,
      'sdp': description.sdp,
      'type': description.type,
    });
  }

  @override
  Future<void> addIceCandidate(RTCIceCandidateDto candidate) async {
    await _methodChannel.invokeMethod('pcAddIceCandidate', {
      'pcId': pcId,
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }

  @override
  Future<RTCSignalingStateDto> getSignalingState() async {
    final s = await _methodChannel.invokeMethod<String>('pcGetSignalingState', {'pcId': pcId});
    return _signalingStateFromString(s);
  }

  @override
  Future<RTCSessionDescriptionDto?> getRemoteDescription() async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('pcGetRemoteDescription', {'pcId': pcId});
    if (result == null) return null;
    return RTCSessionDescriptionDto(result['sdp'] as String?, result['type'] as String? ?? '');
  }

  @override
  Future<List<IRTPTransceiver>> getTransceivers() async {
    final list = await _methodChannel.invokeMethod<List<dynamic>>('pcGetTransceivers', {'pcId': pcId});
    if (list == null) return [];
    return list.map<IRTPTransceiver>((t) {
      final m = t as Map;
      final senderId = m['senderId'] as String? ?? '';
      final kind = m['kind'] as String? ?? 'video';

      final senderTrackId = m['senderTrackId'] as String?;
      final senderTrackKind = m['senderTrackKind'] as String? ?? kind;
      final senderTrack = senderTrackId != null
          ? _AndroidMediaStreamTrack(senderTrackId, senderTrackKind)
          : null;

      final receiverTrackId = m['receiverTrackId'] as String?;
      final receiverTrackKind = m['receiverTrackKind'] as String? ?? kind;
      final receiverTrack = receiverTrackId != null
          ? _AndroidMediaStreamTrack(receiverTrackId, receiverTrackKind)
          : null;

      return _AndroidRTPTransceiver(pcId, senderId, kind, senderTrack, receiverTrack);
    }).toList();
  }

  @override
  Future<void> close() async {
    _pcRegistry.remove(pcId);
    await _methodChannel.invokeMethod('pcClose', {'pcId': pcId});
  }

  @override
  void Function(RTCTrackEventDto event)? onTrack;

  @override
  void Function(RTCIceCandidateDto candidate)? onIceCandidate;

  @override
  void Function(RTCIceConnectionStateDto state)? onIceConnectionState;
}

// ============== Android video renderer (texture) ==============

class _AndroidVideoRenderer implements IVideoRenderer {
  _AndroidVideoRenderer({int? textureId}) : _textureId = textureId;

  int? _textureId;
  IMediaStream? _srcObject;
  bool _muted = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    if (_textureId != null) return;
    final id = await _methodChannel.invokeMethod<int>('createVideoRenderer');
    _textureId = id;
    // Replay pending srcObject that was set before texture was ready
    if (_srcObject is _AndroidMediaStream) {
      _attachStream(_srcObject as _AndroidMediaStream);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_textureId != null) {
      _methodChannel.invokeMethod('disposeVideoRenderer', {'textureId': _textureId});
    }
  }

  void _attachStream(_AndroidMediaStream stream) {
    if (_textureId == null || _disposed) return;
    _methodChannel.invokeMethod('videoRendererSetStream', {
      'textureId': _textureId,
      'streamId': stream.streamId,
    }).catchError((e) {
      debugPrint('[AndroidVideoRenderer] setStream error (ignored): $e');
    });
  }

  @override
  IMediaStream? get srcObject => _srcObject;

  @override
  set srcObject(IMediaStream? value) {
    _srcObject = value;
    if (value is _AndroidMediaStream) {
      _attachStream(value);
    }
  }

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) => _muted = value;

  @override
  Future<void> audioOutput(String? deviceId) async {
    // No-op on Android; routing is via audio_manager / setSpeakerphoneOn.
  }

  @override
  Widget buildView({
    bool mirror = false,
    VideoObjectFit objectFit = VideoObjectFit.cover,
  }) {
    if (_textureId == null) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }
    final boxFit = objectFit == VideoObjectFit.contain
        ? BoxFit.contain
        : BoxFit.cover;
    return SizedBox.expand(
      child: FittedBox(
        fit: boxFit,
        alignment: Alignment.center,
        child: SizedBox(
          width: 16,
          height: 9,
          child: Texture(textureId: _textureId!),
        ),
      ),
    );
  }
}

// ============== Platform ==============

class AndroidGoogleWebRTCPlatform implements IWebRTCPlatform {
  @override
  Future<void> initialize() async {
    _initEventChannel();
    await _methodChannel.invokeMethod('initialize');
  }

  @override
  Future<IMediaStream?> getUserMedia(Map<String, dynamic> constraints) async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getUserMedia', {'constraints': constraints});
    if (result == null) return null;
    final videoError = result['videoError'] as String?;
    if (videoError != null) {
      debugPrint('[AndroidWebRTC] getUserMedia native video error: $videoError');
    }
    final streamId = result['streamId'] as String?;
    if (streamId == null) return null;
    final tracks = result['tracks'] as List<dynamic>?;
    final list = <_AndroidMediaStreamTrack>[];
    if (tracks != null) {
      for (final t in tracks) {
        final m = t as Map;
        list.add(_AndroidMediaStreamTrack(m['trackId'] as String, m['kind'] as String? ?? 'audio'));
      }
    }
    if (list.isEmpty && videoError != null) {
      debugPrint('[AndroidWebRTC] getUserMedia returned 0 tracks. Native error: $videoError');
    }
    return _AndroidMediaStream(streamId, initialTracks: list);
  }

  @override
  Future<IMediaStream?> getDisplayMedia(Map<String, dynamic> constraints) async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getDisplayMedia', {'constraints': constraints});
    if (result == null) return null;
    final streamId = result['streamId'] as String?;
    if (streamId == null) return null;
    final tracks = result['tracks'] as List<dynamic>?;
    final list = <_AndroidMediaStreamTrack>[];
    if (tracks != null) {
      for (final t in tracks) {
        final m = t as Map;
        list.add(_AndroidMediaStreamTrack(m['trackId'] as String, m['kind'] as String? ?? 'video'));
      }
    }
    return _AndroidMediaStream(streamId, initialTracks: list);
  }

  @override
  Future<IPeerConnection> createPeerConnection(Map<String, dynamic> config) async {
    _initEventChannel();
    final pcId = await _methodChannel.invokeMethod<String>('createPeerConnection', {'config': config});
    if (pcId == null) throw Exception('createPeerConnection returned null');
    return _PeerConnectionWrapper(pcId);
  }

  @override
  Future<List<MediaDeviceInfoDto>> enumerateDevices(String kind) async {
    final list = await _methodChannel.invokeMethod<List<dynamic>>('enumerateDevices', {'kind': kind});
    if (list == null) return [];
    return list.map((d) {
      final m = d as Map;
      return MediaDeviceInfoDto(
        deviceId: m['deviceId'] as String? ?? '',
        label: m['label'] as String? ?? '',
        kind: m['kind'] as String? ?? kind,
      );
    }).toList();
  }

  @override
  Future<void> setSpeakerphoneOn(bool on) async {
    await _methodChannel.invokeMethod('setSpeakerphoneOn', {'on': on});
  }

  @override
  Future<List<DesktopCapturerSourceDto>> getDesktopSources() async {
    return []; // Android: no desktop capturer; use getDisplayMedia for screen share.
  }

  @override
  IVideoRenderer createVideoRenderer() => _AndroidVideoRenderer();
}
