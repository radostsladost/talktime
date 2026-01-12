import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// This widget is the "smart" component. When you navigate away and come back,
// this widget re-mounts, initializes a fresh renderer,
// and attaches the existing stream from the service immediately.
class RemoteParticipantTile extends StatefulWidget {
  final String participantId;
  final String username;
  final MediaStream stream;

  const RemoteParticipantTile({
    super.key,
    required this.participantId,
    required this.username,
    required this.stream,
  });

  @override
  State<RemoteParticipantTile> createState() => _RemoteParticipantTileState();
}

class _RemoteParticipantTileState extends State<RemoteParticipantTile> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _isRendererReady = false;
  bool _hasActiveVideo = false;
  bool _hasActiveAudio = true;

  StreamSubscription? _onAddTrackSubscription;
  StreamSubscription? _onRemoveTrackSubscription;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _setupStreamListeners();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream;
    if (mounted) {
      setState(() {
        _isRendererReady = true;
        _updateTrackStates();
      });
    }
  }

  void _setupStreamListeners() {
    // Listen for track additions
    widget.stream.onAddTrack = (event) {
      _updateTrackStates();
      _setupTrackListeners(event);
    };

    // Listen for track removals
    widget.stream.onRemoveTrack = (event) {
      _updateTrackStates();
    };

    // Setup listeners for existing tracks
    for (final track in widget.stream.getTracks()) {
      _setupTrackListeners(track);
    }
  }

  void _setupTrackListeners(MediaStreamTrack track) {
    // Listen for mute/unmute events on the track
    track.onMute = () {
      if (mounted) {
        setState(() => _updateTrackStates());
      }
    };

    track.onUnMute = () {
      if (mounted) {
        setState(() => _updateTrackStates());
      }
    };

    track.onEnded = () {
      if (mounted) {
        setState(() => _updateTrackStates());
      }
    };
  }

  void _updateTrackStates() {
    final videoTracks = widget.stream.getVideoTracks();
    final audioTracks = widget.stream.getAudioTracks();

    // Check video: track exists, is enabled, and is not muted
    _hasActiveVideo =
        videoTracks.isNotEmpty &&
        videoTracks.any(
          (track) => track.enabled == true && track.muted == false,
          // && track.readyState == 'live',
        );

    // Check audio: track exists and is enabled and not muted
    _hasActiveAudio =
        audioTracks.isEmpty ||
        audioTracks.any(
          (track) => track.enabled == true && track.muted == false,
        );

    if (mounted) {
      setState(() {});
    }
  }

  void _disposeStreamListeners() {
    _onAddTrackSubscription?.cancel();
    _onRemoveTrackSubscription?.cancel();

    // Clear track listeners
    for (final track in widget.stream.getTracks()) {
      track.onMute = null;
      track.onUnMute = null;
      track.onEnded = null;
    }
  }

  @override
  void didUpdateWidget(covariant RemoteParticipantTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the stream reference changes (rare, but possible), update the renderer
    if (oldWidget.stream.id != widget.stream.id) {
      // Dispose old stream listeners
      _disposeStreamListeners();

      // Setup new stream
      _renderer.srcObject = widget.stream;
      _setupStreamListeners();
      _updateTrackStates();
    } else {
      // Same stream, but tracks might have changed
      _updateTrackStates();
    }
  }

  @override
  void dispose() {
    _disposeStreamListeners();
    // Only dispose the UI renderer, NOT the stream (which lives in CallService)
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-check track states on every build for safety
    final videoTracks = widget.stream.getVideoTracks();
    final hasVideo =
        videoTracks.isNotEmpty &&
        videoTracks.any(
          (track) => track.enabled == true && track.muted == false,
          // && track.readyState == 'live',
        );

    // Update renderer source if we have active video
    if (hasVideo && _isRendererReady) {
      _renderer.srcObject = widget.stream;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Video Layer
          if (_isRendererReady && hasVideo)
            RTCVideoView(
              _renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
                    style: const TextStyle(fontSize: 24, color: Colors.white),
                  ),
                ),
              ),
            ),

          // 2. Name Tag
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }
}
