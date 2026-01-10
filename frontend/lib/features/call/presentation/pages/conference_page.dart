// conference_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/web.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/features/call/presentation/remote_participant_tile.dart';

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

  // Stream Subscriptions for dynamic updates
  StreamSubscription? _stateSubscription;
  StreamSubscription? _localStreamSubscription;
  StreamSubscription? _remoteStreamsSubscription;
  StreamSubscription? _micSubscription;
  StreamSubscription? _camSubscription;

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
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
  }

  void _setupListeners() {
    // Cancel existing listeners if method is called multiple times unexpectedly
    _stateSubscription?.cancel();
    _localStreamSubscription?.cancel();
    _remoteStreamsSubscription?.cancel();
    _micSubscription?.cancel();
    _camSubscription?.cancel();

    // Listen for state changes to trigger UI rebuilds when necessary
    _stateSubscription = _callService.callStateStream.listen((state) {
      setState(() {});
    });

    // Listen for local stream changes (rebuild when source object changes)
    _localStreamSubscription = _callService.localStreamStream.listen((stream) {
      setState(() {});
    });

    // Listen for remote stream map changes (crucial for mobile/reliability)
    _remoteStreamsSubscription = _callService.remoteStreamsStream.listen(
      _handleRemoteStreamsUpdate,
    );

    // Listen for mic/camera state changes
    _micSubscription = _callService.micStateStream.listen(
      (_) => setState(() {}),
    );
    _camSubscription = _callService.camStateStream.listen(
      (_) => setState(() {}),
    );
  }

  void _attachExistingStreams() {
    // 1. Attach local stream if it exists right away
    final currentLocalStream = _callService.localStream;
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

  @override
  void dispose() {
    // IMPORTANT: Cancel subscriptions
    _stateSubscription?.cancel();
    _localStreamSubscription?.cancel();
    _remoteStreamsSubscription?.cancel();
    _micSubscription?.cancel();
    _camSubscription?.cancel();

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
            stream: CallService().remoteStreamsStream,
            builder: (context, snapshot) {
              final streams = snapshot.data ?? {};
              return _buildGrid(streams);
            },
          ),

          // LOCAL VIDEO (PIP)
          Positioned(
            right: 20,
            bottom: 100,
            child: SizedBox(
              width: 100,
              height: 150,
              child: StreamBuilder<MediaStream?>(
                stream: CallService().localStreamStream,
                builder: (context, snapshot) {
                  final stream = snapshot.data;

                  if (stream != null) {
                    // CRITICAL FIX: Only update srcObject if reference changes
                    // to prevent flickering/detaching native resources.
                    if (_localRenderer.srcObject != stream) {
                      _localRenderer.srcObject = stream;
                    }
                    return RTCVideoView(_localRenderer, mirror: true);
                  }

                  // If stream is null, display placeholder.
                  // This happens on endCall or during initialization if media acquisition fails.
                  return Container(color: Colors.grey);
                },
              ),
            ),
          ),

          // CONTROLS
          Positioned(bottom: 20, left: 0, right: 0, child: _buildControls()),
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
    final userInfoMap = CallService().participantInfo;

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

    final columns = totalTiles <= 2
        ? 1
        : 2; // Simple logic: 1 col for 1-2 people, 2 for more
    final rows = (totalTiles / columns).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 8.0;
        final availableWidth = constraints.maxWidth - (columns + 1) * spacing;
        final tileWidth = availableWidth / columns;

        // Aspect ratio 3:4 or 9:16 usually works better for mobile portrait
        final tileHeight = constraints.maxHeight / rows - (spacing * 2);

        return SingleChildScrollView(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: spacing,
            runSpacing: spacing,
            children: participants.map((id) {
              final stream = streams[id]!;
              final user = userInfoMap[id];

              return SizedBox(
                width: tileWidth,
                height: tileHeight,
                // We use a Key to ensure Flutter doesn't destroy/recreate
                // the renderer unnecessarily when the list order changes.
                child: RemoteParticipantTile(
                  key: ValueKey(id),
                  participantId: id,
                  stream: stream,
                  username: user?.username ?? '???',
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StreamBuilder<bool>(
          stream: CallService().micStateStream,
          initialData: false,
          builder: (context, snapshot) {
            final isMuted = snapshot.data ?? false;
            return IconButton(
              icon: Icon(isMuted ? Icons.mic_off : Icons.mic),
              color: isMuted ? Colors.red : Colors.white,
              onPressed: () => CallService().toggleMic(),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.call_end, color: Colors.red),
          onPressed: () {
            CallService().endCall();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
