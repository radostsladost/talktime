// conference_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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

  // UI Specific Renderers (must be disposed when page closes)
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  @override
  void initState() {
    super.initState();
    _initRenderers();

    _callService.initService().catchError((error) {
      print(error);
    });
    // Check if we are already in this call, if not, start it
    if (_callService.currentState == CallState.idle) {
      _callService
          .startCall(widget.roomId, widget.initialParticipants)
          .catchError((error) {
            print(error);
          });
    } else {
      // We re-entered the page, attach existing streams immediately
      _attachExistingStreams();
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
  }

  void _attachExistingStreams() {
    // In a real app, you'd grab the current value from the service and set srcObject
  }

  @override
  void dispose() {
    // IMPORTANT: We dispose the RENDERERS (UI), but we DO NOT stop the call.
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
                  if (snapshot.hasData && snapshot.data != null) {
                    _localRenderer.srcObject = snapshot.data;
                    return RTCVideoView(_localRenderer, mirror: true);
                  }
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
