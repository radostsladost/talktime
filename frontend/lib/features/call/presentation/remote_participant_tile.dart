import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:talktime/features/call/webrtc/types.dart';
import 'package:talktime/features/call/webrtc/webrtc_platform.dart';

class RemoteParticipantTile extends StatefulWidget {
  final String participantId;
  final String username;
  final IMediaStream stream;
  final Function(String, bool)? onParticipantTap;
  final bool? fitInRect;

  /// Override for video fit (cover/contain). If null, uses fitInRect (true => contain, false => cover).
  final VideoObjectFit? objectFit;

  /// Output device for this participant's audio (desktop/web only).
  final String? speakerDeviceId;

  const RemoteParticipantTile({
    super.key,
    required this.participantId,
    required this.username,
    required this.stream,
    this.onParticipantTap,
    this.fitInRect,
    this.objectFit,
    this.speakerDeviceId,
  });

  @override
  State<RemoteParticipantTile> createState() => _RemoteParticipantTileState();
}

class _RemoteParticipantTileState extends State<RemoteParticipantTile> {
  late final IVideoRenderer _renderer;
  bool _isRendererReady = false;
  bool _hasActiveVideo = false;
  bool _hasActiveAudio = true;
  Timer? _trackPollTimer;
  int _videoTrackCount = 0;

  @override
  void initState() {
    super.initState();
    _renderer = getWebRTCPlatform().createVideoRenderer();
    _initRenderer();
    _setupStreamListeners();

    // Poll track states as a safety net for platforms where events are unreliable
    // (e.g. Safari). Short interval at first, then backs off.
    _trackPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkAndUpdateTrackStates();
    });
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream;
    if (widget.speakerDeviceId != null) {
      try {
        if ((kIsWeb || !Platform.isAndroid) && widget.speakerDeviceId != null) {
          await _renderer.audioOutput(widget.speakerDeviceId!);
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRendererReady = true;
        _updateTrackStates();
      });
    }
  }

  void _setupStreamListeners() {
    widget.stream.onAddTrack = (_, track) {
      _setupTrackListeners(track);
      _checkAndUpdateTrackStates();
      // Force re-assign srcObject so the renderer picks up the new track
      if (_isRendererReady) {
        _renderer.srcObject = widget.stream;
      }
    };

    widget.stream.onRemoveTrack = (_, track) {
      _checkAndUpdateTrackStates();
    };

    for (final track in widget.stream.getTracks()) {
      _setupTrackListeners(track);
    }
  }

  void _setupTrackListeners(IMediaStreamTrack track) {
    track.onMute = () {
      if (mounted) _checkAndUpdateTrackStates();
    };

    track.onUnMute = () {
      if (mounted) _checkAndUpdateTrackStates();
    };

    track.onEnded = () {
      if (mounted) _checkAndUpdateTrackStates();
    };
  }

  /// Check if track state actually changed, and only call setState if it did.
  void _checkAndUpdateTrackStates() {
    final oldVideo = _hasActiveVideo;
    final oldAudio = _hasActiveAudio;
    final oldCount = _videoTrackCount;
    _updateTrackStatesInternal();

    if (oldVideo != _hasActiveVideo ||
        oldAudio != _hasActiveAudio ||
        oldCount != _videoTrackCount) {
      // Track configuration changed — re-assign srcObject to ensure renderer
      // picks up new tracks (especially important after renegotiation).
      if (_isRendererReady && _hasActiveVideo) {
        _renderer.srcObject = widget.stream;
      }
      if (mounted) setState(() {});
    }
  }

  void _updateTrackStates() {
    _updateTrackStatesInternal();
    if (mounted) setState(() {});
  }

  void _updateTrackStatesInternal() {
    final videoTracks = widget.stream.getVideoTracks();
    final audioTracks = widget.stream.getAudioTracks();

    _videoTrackCount = videoTracks.length;

    // Show the video renderer if any video track exists and is enabled.
    // We intentionally do NOT require track.muted == false because Safari
    // reports remote tracks as muted until media starts flowing — the
    // <video> element will display frames the moment they arrive.
    _hasActiveVideo =
        videoTracks.isNotEmpty &&
        videoTracks.any((track) => track.enabled);

    _hasActiveAudio =
        audioTracks.isEmpty ||
        audioTracks.any((track) => track.enabled);
  }

  void _disposeStreamListeners() {
    try {
      for (final track in widget.stream.getTracks()) {
        track.onMute = null;
        track.onUnMute = null;
        track.onEnded = null;
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant RemoteParticipantTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speakerDeviceId != widget.speakerDeviceId &&
        widget.speakerDeviceId != null) {
      _renderer.audioOutput(widget.speakerDeviceId!).catchError((_) {});
    }
    if (oldWidget.stream.id != widget.stream.id) {
      _disposeStreamListeners();
      _renderer.srcObject = widget.stream;
      _setupStreamListeners();
      _updateTrackStates();
    } else {
      // Same stream — re-check tracks (new tracks may have been added via
      // renegotiation without changing the stream object).
      _checkAndUpdateTrackStates();
    }
  }

  @override
  void dispose() {
    _trackPollTimer?.cancel();
    _disposeStreamListeners();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = _hasActiveVideo;

    return Material(
      child: InkWell(
        onTap: () => widget.onParticipantTap?.call(
          widget.participantId,
          _isRendererReady && hasVideo,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Video Layer
              if (_isRendererReady && hasVideo)
                _renderer.buildView(
                  objectFit: widget.objectFit ??
                      (widget.fitInRect == true
                          ? VideoObjectFit.contain
                          : VideoObjectFit.cover),
                  mirror: false,
                )
              else
                Container(
                  color: Colors.grey[800],
                  child: Center(
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.deepPurple,
                      child: Text(
                        widget.username.isNotEmpty
                            ? widget.username.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

              // 2. Name Tag
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.username,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),

              // 3. Audio Mute Indicator
              if (!_hasActiveAudio)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.mic_off, color: Colors.red, size: 20),
                ),

              // 4. Video Off Indicator (when in avatar mode)
              if (!hasVideo)
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Icon(Icons.videocam_off, color: Colors.red, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
