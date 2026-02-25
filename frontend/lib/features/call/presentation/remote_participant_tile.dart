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
  IVideoRenderer? _renderer;
  bool _isRendererReady = false;
  bool _hasActiveVideo = false;
  bool _hasActiveAudio = true;
  bool _allVideoTracksMuted = false;
  Timer? _trackPollTimer;
  int _videoTrackCount = 0;
  DateTime? _lastWebReattachAt;
  bool _rendererRecreateInProgress = false;
  /// One-time reattach after first layout so the <video> element has size and displays (web).
  bool _didPostFrameReattach = false;

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
    final renderer = _renderer;
    if (renderer == null) return;
    await renderer.initialize();
    renderer.srcObject = widget.stream;
    if (widget.speakerDeviceId != null) {
      try {
        if ((kIsWeb || !Platform.isAndroid) && widget.speakerDeviceId != null) {
          await renderer.audioOutput(widget.speakerDeviceId!);
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
      // Force re-assign srcObject so the renderer picks up the new track.
      // On web, a null->stream bounce is more reliable after renegotiation.
      if (_isRendererReady) {
        final renderer = _renderer;
        if (renderer == null) return;
        if (kIsWeb) {
          renderer.srcObject = null;
        }
        renderer.srcObject = widget.stream;
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
      debugPrint(
        '[diag-tile] ${widget.participantId} ${track.kind} onMute '
        'enabled=${track.enabled} muted=${track.muted}',
      );
      if (mounted) _checkAndUpdateTrackStates();
    };

    track.onUnMute = () {
      debugPrint(
        '[diag-tile] ${widget.participantId} ${track.kind} onUnMute '
        'enabled=${track.enabled} muted=${track.muted}',
      );
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
    final oldMuted = _allVideoTracksMuted;
    _updateTrackStatesInternal();

    final trackConfigChanged = oldVideo != _hasActiveVideo ||
        oldAudio != _hasActiveAudio ||
        oldCount != _videoTrackCount;
    if (trackConfigChanged || oldMuted != _allVideoTracksMuted) {
      debugPrint(
        '[diag-tile] ${widget.participantId} state changed: '
        'video=$_hasActiveVideo audio=$_hasActiveAudio videoCount=$_videoTrackCount',
      );
      // Re-assign srcObject only when track configuration actually changed (new
      // track or count). Do NOT bounce srcObject when only muted state changes:
      // the <video> element can show frames while the track is still "muted"
      // until media flows; bouncing or recreating the renderer can freeze the
      // image on the receiver.
      if (_isRendererReady && _hasActiveVideo && trackConfigChanged) {
        final renderer = _renderer;
        if (renderer != null) {
          if (kIsWeb) {
            renderer.srcObject = null;
          }
          renderer.srcObject = widget.stream;
        }
      }
      if (mounted) setState(() {});
    }

    // Web workaround: only if video never appeared after a long time, try
    // recreating the renderer once. Do NOT recreate every 2s when muted — that
    // disposes the renderer that showed the first frame and freezes the image.
    if (kIsWeb &&
        _isRendererReady &&
        _hasActiveVideo &&
        _allVideoTracksMuted &&
        _videoTrackCount > 0) {
      final now = DateTime.now();
      final canReattach = _lastWebReattachAt == null ||
          now.difference(_lastWebReattachAt!) > const Duration(seconds: 8);
      if (canReattach) {
        _lastWebReattachAt = now;
        debugPrint(
          '[diag-tile] ${widget.participantId} web muted-video renderer recreate (delayed fallback)',
        );
        unawaited(_recreateRenderer());
      }
    }
  }

  Future<void> _recreateRenderer() async {
    if (_rendererRecreateInProgress || !mounted) return;
    _rendererRecreateInProgress = true;
    final oldRenderer = _renderer;
    final newRenderer = getWebRTCPlatform().createVideoRenderer();
    try {
      await newRenderer.initialize();
      newRenderer.srcObject = widget.stream;
      if ((kIsWeb || !Platform.isAndroid) && widget.speakerDeviceId != null) {
        await newRenderer.audioOutput(widget.speakerDeviceId!);
      }
      if (!mounted) {
        newRenderer.dispose();
        return;
      }
      _renderer = newRenderer;
      _isRendererReady = true;
      setState(() {});
      oldRenderer?.dispose();
    } catch (_) {
      newRenderer.dispose();
    } finally {
      _rendererRecreateInProgress = false;
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

    _allVideoTracksMuted =
        videoTracks.isNotEmpty && videoTracks.every((track) => track.muted);

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
      _renderer?.audioOutput(widget.speakerDeviceId!).catchError((_) {});
    }
    if (oldWidget.stream.id != widget.stream.id) {
      _disposeStreamListeners();
      _renderer?.srcObject = widget.stream;
      _setupStreamListeners();
      _updateTrackStates();
      _didPostFrameReattach = false; // re-run post-frame reattach for new stream
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
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = _hasActiveVideo;

    // Web: after first layout the <video> element has real size; reattach stream
    // once so it actually displays (otherwise it can stay black until layout is
    // recreated e.g. on window resize).
    if (kIsWeb &&
        _isRendererReady &&
        hasVideo &&
        _renderer != null &&
        !_didPostFrameReattach) {
      _didPostFrameReattach = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _renderer == null) return;
        _renderer!.srcObject = null;
        _renderer!.srcObject = widget.stream;
      });
    }

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
              if (_isRendererReady && hasVideo && _renderer != null)
                _renderer!.buildView(
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
