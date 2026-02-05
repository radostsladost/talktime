// conference_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/web.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/features/call/presentation/remote_participant_tile.dart';
import 'package:talktime/features/call/presentation/widgets/audio_chooser_popup.dart';
import 'package:talktime/features/call/presentation/widgets/screen_window_chooser_popup.dart';

class ConferencePage extends StatefulWidget {
  final String roomId;
  final List<UserInfo> initialParticipants;

  const ConferencePage({
    super.key,
    required this.roomId,
    required this.initialParticipants,
  });

  @override
  State<ConferencePage> createState() => _ConferencePageState();
}

class _ConferencePageState extends State<ConferencePage> {
  final CallService _callService = CallService(); // Singleton instance
  final Logger _logger = Logger(output: ConsoleOutput());

  // UI Specific Renderers (must be disposed when page closes)
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  bool _isPresentationMode = false;
  String? _focusedParticipantId; // Optional: manually select who to focus
  bool _cam = false;
  bool _screenShare = false;

  // Stream Subscriptions for dynamic updates
  StreamSubscription? _stateSubscription;
  StreamSubscription? _localStreamSubscription;
  StreamSubscription? _cachedVideoSubscription;
  StreamSubscription? _remoteStreamsSubscription;
  StreamSubscription? _micSubscription;
  StreamSubscription? _camSubscription;
  StreamSubscription? _screenShareSubscription;

  @override
  void initState() {
    super.initState();
    _initRenderers();

    _callService
        .initService()
        .catchError((error) {
          _logger.e("Error initializing call service: $error");
        })
        .then((_) {
          // Check if we are already in this call, if not, start it
          if (_callService.currentState == CallState.idle) {
            _callService
                .startCall(widget.roomId, widget.initialParticipants)
                .catchError((error) {
                  _logger.e("Error starting call: $error");
                });
          }

          // Setup listeners and attach existing streams immediately after service is set up/call started
          _setupListeners();
          _attachExistingStreams();
        });

    // Timer.periodic(Duration(seconds: 5), (timer) {
    //   if (_callService.remoteStreams.values.any(
    //         (stream) =>
    //             stream.getVideoTracks()?.any(
    //               (track) => track?.kind == 'video' && track?.enabled == true,
    //             ) ==
    //             false,
    //       ) ==
    //       true) {
    //     print("Remote video track disabled");
    //     setState(() {});
    //   }
    // });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
  }

  void _setupListeners() {
    // Cancel existing listeners if method is called multiple times unexpectedly
    _stateSubscription?.cancel();
    _localStreamSubscription?.cancel();
    _cachedVideoSubscription?.cancel();
    _remoteStreamsSubscription?.cancel();
    _micSubscription?.cancel();
    _camSubscription?.cancel();
    _screenShareSubscription?.cancel();

    // Listen for state changes to trigger UI rebuilds when necessary
    _stateSubscription = _callService.callStateStream.listen((state) {
      if (state == CallState.connected) {
        _attachExistingStreams();
      }
      setState(() {});
    });

    // Listen for local stream changes (rebuild when source object changes)
    _localStreamSubscription = _callService.localStreamStream.listen((stream) {
      setState(() {});
      _attachExistingStreams();
    });

    // Listen for local stream changes (rebuild when source object changes)
    _cachedVideoSubscription = _callService.cachedVideoStreamStream.listen((
      stream,
    ) {
      setState(() {});
      _attachExistingStreams();
    });

    // Listen for remote stream map changes (crucial for mobile/reliability)
    _remoteStreamsSubscription = _callService.remoteStreamsStream.listen(
      _handleRemoteStreamsUpdate,
    );

    // Listen for mic/camera state changes
    _micSubscription = _callService.micStateStream.listen((_) {
      setState(() {});
      _attachExistingStreams();
    });
    _camSubscription = _callService.camStateStream.listen((val) {
      setState(() {});
      _cam = val;
      _attachExistingStreams();
    });
    _screenShareSubscription = _callService.isScreenSharing.listen((isSharing) {
      setState(() {});
      _screenShare = isSharing;
      _attachExistingStreams();
    });
  }

  void _attachExistingStreams() {
    try {
      // 1. Attach local stream if it exists right away
      final currentLocalStream = _callService.cachedVideoStream;
      if (currentLocalStream != null && _localRenderer.srcObject == null) {
        _localRenderer.srcObject = currentLocalStream;
      }

      // Set initial mic/cam state reflected in controls based on service state
      if (_micSubscription == null) {
        // Ensure mic state is set if control stream hasn't started yet
        // Though StreamBuilder should handle initialData={false}, this is for safety
        _callService.micStateStream
            .listen((isMuted) => setState(() {}))
            .cancel(); // Only to check value, canceling immediately
      }

      // 2. Initialize and attach all existing remote renderers
      _handleRemoteStreamsUpdate(_callService.remoteStreams);
    } catch (error) {
      _logger.e('Error attaching existing streams: $error');
    }
  }

  void _handleRemoteStreamsUpdate(Map<String, MediaStream> streams) {
    // 1. Sync up _remoteRenderers map with incoming streams map
    final activeIds = streams.keys.toSet();
    final currentIds = _remoteRenderers.keys.toSet();

    // Remove renderers for participants who left
    for (final id in currentIds.difference(activeIds)) {
      _remoteRenderers[id]?.dispose();
      _remoteRenderers.remove(id);
    }

    // Initialize/Attach renderers for new/current participants
    for (final id in activeIds) {
      if (!_remoteRenderers.containsKey(id)) {
        // Initialize new renderer if one doesn't exist for this ID
        final newRenderer = RTCVideoRenderer();
        newRenderer.initialize().then((_) {
          // After initialization, assign the stream object we already have
          newRenderer.srcObject = streams[id];
          // Update state to trigger UI redraw with the new tile
          if (mounted) setState(() {});
        });
        _remoteRenderers[id] = newRenderer;
      } else {
        // Update existing renderer's stream object (Handles track changes/reconnects)
        _remoteRenderers[id]!.srcObject = streams[id];
      }
    }

    // Trigger a rebuild to reflect the updated map/state
    setState(() {});
  }

  void _presentationMode(String id, bool hasVideo) {
    setState(() {
      if (!hasVideo) {
        return;
      }

      if (_isPresentationMode && _focusedParticipantId != id) {
        _focusedParticipantId = id;
        return;
      }

      _isPresentationMode = !_isPresentationMode;
      if (_isPresentationMode) {
        _focusedParticipantId = id;
      } else {
        _focusedParticipantId = null;
      }
    });
  }

  @override
  void dispose() {
    // IMPORTANT: Cancel subscriptions
    _stateSubscription?.cancel();
    _localStreamSubscription?.cancel();
    _cachedVideoSubscription?.cancel();
    _remoteStreamsSubscription?.cancel();
    _micSubscription?.cancel();
    _camSubscription?.cancel();
    _screenShareSubscription?.cancel();

    // Dispose the RENDERERS (UI), but DO NOT stop the call.
    // The call lives in the service.
    _localRenderer.dispose();
    for (var r in _remoteRenderers.values) r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // REMOTE STREAMS GRID
          StreamBuilder<Map<String, MediaStream>>(
            stream: _callService.remoteStreamsStream,
            initialData: _callService.remoteStreams,
            builder: (context, snapshot) {
              final streams = snapshot.data ?? {};
              return _buildGrid(streams);
            },
          ),

          // LOCAL VIDEO (PIP)
          if (_cam || _screenShare)
            Positioned(
              right: 20,
              bottom: 100,
              child: SizedBox(
                width: 100,
                height: 150,
                child: StreamBuilder<MediaStream?>(
                  stream: _callService.cachedVideoStreamStream,
                  initialData: _callService.cachedVideoStream,
                  builder: (context, snapshot) {
                    final stream = snapshot.data;
                    // print('Local stream: $stream');

                    if (stream != null &&
                        stream.getVideoTracks()?.isNotEmpty == true) {
                      // CRITICAL FIX: Only update srcObject if reference changes
                      // to prevent flickering/detaching native resources.
                      if (_localRenderer.srcObject != stream) {
                        _localRenderer.srcObject = stream;
                      }
                      return RTCVideoView(_localRenderer, mirror: _screenShare);
                    }

                    // If stream is null, display placeholder.
                    // This happens on endCall or during initialization if media acquisition fails.
                    return Container(color: Colors.transparent);
                  },
                ),
              ),
            ),

          // CONTROLS AT BOTTOM
          Positioned(left: 0, right: 0, bottom: 40, child: _buildControls()),
        ],
      ),
    );
  }

  Widget _buildGrid(Map<String, MediaStream> streams) {
    // Logic to sync _remoteRenderers map with streams map
    // and render RTCVideoView for each
    // ...
    // 1. Prepare data
    final participants = streams.keys.toList();
    // Use the service to get user info (names)
    final userInfoMap = _callService.participantInfo;

    // 2. Calculate Grid Dimensions
    // Note: We don't include local participant in this count if it's in a separate PiP view.
    // If you want local user in the grid, add +1 to totalTiles.
    final totalTiles = participants.length;

    if (totalTiles == 0) {
      return const Center(
        child: Text(
          "Waiting for others to join...",
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    if (totalTiles == 1 && streams.length == 1) {
      final id = participants.first;
      final stream = streams[id]!;
      final user = userInfoMap[id];

      return Center(
        child: RemoteParticipantTile(
          key: ValueKey(id),
          participantId: id,
          stream: stream,
          username: user?.username ?? '???',
          onParticipantTap: (id, hasVideo) => _presentationMode(id, hasVideo),
          fitInRect: _isPresentationMode,
        ),
      );
    }

    if (_isPresentationMode) {
      String? focusedId = _focusedParticipantId;

      if (focusedId == null || !streams.containsKey(focusedId)) {
        // Fallback: pick first participant
        focusedId = participants.first;
      }

      final otherParticipants = participants
          .where((id) => id != focusedId)
          .toList();

      // Main large tile
      final mainTile = Center(
        child: SizedBox.expand(
          child: RemoteParticipantTile(
            key: ValueKey(focusedId),
            participantId: focusedId,
            stream: streams[focusedId]!,
            username: userInfoMap[focusedId]?.username ?? '???',
            onParticipantTap: (id, hasVideo) => _presentationMode(id, hasVideo),
            fitInRect: true,
          ),
        ),
      );

      // Small vertical list on the RIGHT side
      final smallThumbnails = Positioned(
        right: 16,
        top: 80, // Leave space for controls & avoid overlap
        bottom: 80, // Avoid bottom controls
        child: SingleChildScrollView(
          child: Column(
            children: otherParticipants.map((id) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  width: 80,
                  height: 100,
                  child: RemoteParticipantTile(
                    key: ValueKey(id),
                    participantId: id,
                    stream: streams[id]!,
                    username: userInfoMap[id]?.username ?? '???',
                    onParticipantTap: (id, hasVideo) =>
                        _presentationMode(id, hasVideo),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );

      return Stack(children: [mainTile, smallThumbnails]);
    }

    final columns = totalTiles <= 2
        ? 1
        : 2; // Simple logic: 1 col for 1-2 people, 2 for more

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 8.0;
        // Max width available for tiles
        final maxWidth = constraints.maxWidth - (columns + 1) * spacing;
        final tileWidth = min(maxWidth / columns, 400.0); // max 300px wide

        return Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: spacing,
            runSpacing: spacing,
            children: participants.map((id) {
              final stream = streams[id]!;
              final user = userInfoMap[id];

              return SizedBox(
                width: tileWidth,
                // We use a Key to ensure Flutter doesn't destroy/recreate
                // the renderer unnecessarily when the list order changes.
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: RemoteParticipantTile(
                    key: ValueKey(id),
                    participantId: id,
                    stream: stream,
                    username: user?.username ?? '???',
                    onParticipantTap: (id, hasVideo) =>
                        _presentationMode(id, hasVideo),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _toggleScreenSharing() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (_callService.isScreenSharingValue) {
        _callService.toggleScreenShare().catchError((error) {
          _logger.e('Error toggling screen share: $error');
        });
        return;
      }

      final selectedSource = await ScreenWindowPopupChooser.show(
        context: context,
      );
      if (selectedSource != null) {
        _callService.toggleScreenShare(source: selectedSource).catchError((
          error,
        ) {
          _logger.e('Error starting screen share: $error');
        });
      }
    } else {
      _callService.toggleScreenShare().catchError((error) {
        _logger.e('Error toggling screen share: $error');
      });
    }
  }

  void _showAudioDeviceSelector() async {
    final selectedDevice = await AudioDevicePopupChooser.show(context: context);
    if (selectedDevice != null) {
      try {
        await _callService.changeAudioDevice(selectedDevice.deviceId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Switched to ${selectedDevice.label.isNotEmpty ? selectedDevice.label : "selected microphone"}',
              ),
            ),
          );
        }
      } catch (e) {
        _logger.e('Error switching audio device: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to switch audio device'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (kIsWeb || Platform.isAndroid || Platform.isIOS)
            IconButton(
              icon: const Icon(Icons.switch_camera),
              color: Colors.white,
              onPressed: () => _callService.changeCameraDevice(),
            ),
          StreamBuilder<bool>(
            stream: _callService.camStateStream,
            initialData: false,
            builder: (context, snapshot) {
              final isCameraOn = snapshot.data ?? false;
              return IconButton(
                icon: Icon(!isCameraOn ? Icons.videocam_off : Icons.videocam),
                color: !isCameraOn ? Colors.red : Colors.white,
                onPressed: () => _callService.toggleCamera(),
              );
            },
          ),
          StreamBuilder<bool>(
            stream: _callService.micStateStream,
            initialData: false,
            builder: (context, snapshot) {
              final isMuted = !(snapshot.data ?? false);
              return IconButton(
                icon: Icon(isMuted ? Icons.mic_off : Icons.mic),
                color: isMuted ? Colors.red : Colors.white,
                onPressed: () => _callService.toggleMic(),
              );
            },
          ),
          StreamBuilder<bool>(
            stream: _callService.isScreenSharing,
            initialData: false,
            builder: (context, snapshot) {
              final isScreenSharing = snapshot.data ?? false;
              return IconButton(
                icon: Icon(Icons.screen_share),
                color: isScreenSharing ? Colors.green : Colors.white,
                onPressed: _toggleScreenSharing,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.volume_up),
            color: Colors.white,
            onPressed: _showAudioDeviceSelector,
          ),
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.red),
            onPressed: () {
              _callService.endCall().catchError((error) {
                _logger.e('Error ending call: $error');
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
