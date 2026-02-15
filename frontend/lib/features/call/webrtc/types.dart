// Platform-agnostic WebRTC types and interfaces.
// Implementations: flutter_webrtc (iOS/Web/Desktop) or Android bridge (Android).

import 'package:flutter/material.dart';

// ============== DTOs (signaling) ==============

/// Session description for offer/answer (SDP).
class RTCSessionDescriptionDto {
  const RTCSessionDescriptionDto(this.sdp, this.type);
  final String? sdp;
  final String type; // 'offer' | 'answer' | 'rollback'
}

/// ICE candidate.
class RTCIceCandidateDto {
  const RTCIceCandidateDto(this.candidate, this.sdpMid, this.sdpMLineIndex);
  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

/// Device info from enumerateDevices (audioinput, audiooutput, videoinput).
class MediaDeviceInfoDto {
  const MediaDeviceInfoDto({
    required this.deviceId,
    required this.label,
    required this.kind,
  });
  final String deviceId;
  final String label;
  final String kind;
}

/// Video view fit (maps to RTCVideoViewObjectFit).
enum VideoObjectFit {
  contain,
  cover,
}

// ============== Track ==============

/// Platform-agnostic media stream track.
abstract class IMediaStreamTrack {
  String get kind; // 'audio' | 'video'
  String? get label;
  bool get enabled;
  set enabled(bool value);
  bool get muted;
  void stop();

  /// Callbacks (assign to listen).
  void Function()? onMute;
  void Function()? onUnMute;
  void Function()? onEnded;
}

// ============== Stream ==============

/// Event for onAddTrack (stream, track).
typedef AddTrackEventCallback = void Function(
  IMediaStream stream,
  IMediaStreamTrack track,
);

/// Event for onRemoveTrack.
typedef RemoveTrackEventCallback = void Function(
  IMediaStream stream,
  IMediaStreamTrack track,
);

/// Platform-agnostic media stream.
abstract class IMediaStream {
  String get id;

  List<IMediaStreamTrack> getTracks();
  List<IMediaStreamTrack> getAudioTracks();
  List<IMediaStreamTrack> getVideoTracks();

  Future<void> addTrack(IMediaStreamTrack track);
  Future<void> removeTrack(IMediaStreamTrack track);
  void dispose();

  AddTrackEventCallback? onAddTrack;
  RemoveTrackEventCallback? onRemoveTrack;
}

// ============== PeerConnection: transceiver / sender ==============

/// Sender with replaceTrack for renegotiation.
abstract class IRTPSender {
  IMediaStreamTrack? get track;
  Future<void> replaceTrack(IMediaStreamTrack? track);
}

/// Transceiver (sender + receiver) for video track replacement.
abstract class IRTPTransceiver {
  IRTPSender get sender;
  IMediaStreamTrack? get receiverTrack; // receiver.track
}

/// Signaling state.
enum RTCSignalingStateDto {
  stable,
  haveLocalOffer,
  haveRemoteOffer,
  haveLocalPranswer,
  haveRemotePranswer,
  closed,
}

/// ICE connection state.
enum RTCIceConnectionStateDto {
  new_,
  checking,
  connected,
  completed,
  failed,
  disconnected,
  closed,
}

/// Track event: stream(s) and track.
class RTCTrackEventDto {
  const RTCTrackEventDto(this.streams, this.track);
  final List<IMediaStream> streams;
  final IMediaStreamTrack track;
}

/// Platform-agnostic peer connection.
abstract class IPeerConnection {
  /// Add track to this connection; [stream] is the stream the track belongs to.
  Future<void> addTrack(IMediaStreamTrack track, IMediaStream stream);

  Future<RTCSessionDescriptionDto> createOffer();
  Future<RTCSessionDescriptionDto> createAnswer();
  Future<void> setLocalDescription(RTCSessionDescriptionDto description);
  Future<void> setRemoteDescription(RTCSessionDescriptionDto description);
  Future<void> addIceCandidate(RTCIceCandidateDto candidate);

  Future<RTCSignalingStateDto> getSignalingState();
  Future<RTCSessionDescriptionDto?> getRemoteDescription();
  Future<List<IRTPTransceiver>> getTransceivers();
  Future<void> close();

  /// Callbacks.
  void Function(RTCTrackEventDto event)? onTrack;
  void Function(RTCIceCandidateDto candidate)? onIceCandidate;
  void Function(RTCIceConnectionStateDto state)? onIceConnectionState;
}

// ============== Video renderer ==============

/// Platform-agnostic video renderer (local preview or remote video).
abstract class IVideoRenderer {
  Future<void> initialize();
  void dispose();

  IMediaStream? get srcObject;
  set srcObject(IMediaStream? value);

  /// Mute local preview (no local audio playback).
  bool get muted;
  set muted(bool value);

  /// Set audio output device (desktop/web); no-op on Android (routing via platform).
  Future<void> audioOutput(String? deviceId);

  /// Build the widget to display the video (mirror for front camera, objectFit for layout).
  Widget buildView({bool mirror = false, VideoObjectFit objectFit = VideoObjectFit.cover});
}

// ============== Platform ==============

/// Source for desktop screen/window capture (flutter_webrtc only; Android uses getDisplayMedia with different semantics).
class DesktopCapturerSourceDto {
  const DesktopCapturerSourceDto({
    required this.id,
    required this.name,
    required this.thumbnailPath,
  });
  final String id;
  final String name;
  final String thumbnailPath;
}

/// Platform-agnostic WebRTC factory and media APIs.
abstract class IWebRTCPlatform {
  /// One-time initialization (e.g. Android PeerConnectionFactory with AEC).
  Future<void> initialize();

  Future<IMediaStream?> getUserMedia(Map<String, dynamic> constraints);
  Future<IMediaStream?> getDisplayMedia(Map<String, dynamic> constraints);

  /// Create peer connection; [config] has 'iceServers' and optional 'sdpSemantics'.
  Future<IPeerConnection> createPeerConnection(Map<String, dynamic> config);

  Future<List<MediaDeviceInfoDto>> enumerateDevices(String kind);
  Future<void> setSpeakerphoneOn(bool on);

  /// Get desktop capture sources for screen picker (non-Android). Returns empty on Android/web.
  Future<List<DesktopCapturerSourceDto>> getDesktopSources();

  /// Create a video renderer for local preview or remote video.
  IVideoRenderer createVideoRenderer();
}
