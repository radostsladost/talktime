// conference_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/web.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/call/data/echo_reduction_web.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/features/call/presentation/remote_participant_tile.dart';
import 'package:talktime/features/call/presentation/widgets/audio_chooser_popup.dart';
import 'package:talktime/features/call/presentation/widgets/screen_window_chooser_popup.dart';
import 'package:talktime/features/call/webrtc/webrtc_platform.dart';
import 'package:talktime/features/chat/presentation/pages/message_list_page.dart';
import 'package:talktime/shared/models/conversation.dart';

class ConferencePage extends StatefulWidget {
  final String roomId;
  final List<UserInfo> initialParticipants;
  final Conversation? conversation;

  const ConferencePage({
    super.key,
    required this.roomId,
    required this.initialParticipants,
    this.conversation,
  });

  @override
  State<ConferencePage> createState() => _ConferencePageState();
}

class _ConferencePageState extends State<ConferencePage> {
  final CallService _callService = CallService(); // Singleton instance
  final Logger _logger = Logger(output: ConsoleOutput());

  // UI Specific Renderers (must be disposed when page closes)
  late final IVideoRenderer _localRenderer;
  final Map<String, IVideoRenderer> _remoteRenderers = {};
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
  StreamSubscription? _speakerStateSubscription;
  StreamSubscription? _speakerDeviceIdSubscription;

  /// Web only: dispose callback for receive-side echo reduction.
  void Function()? _echoReductionDispose;

  @override
  void initState() {
    super.initState();
    _localRenderer = getWebRTCPlatform().createVideoRenderer();
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
    _localRenderer.muted = true;
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
    _speakerStateSubscription?.cancel();
    _speakerDeviceIdSubscription?.cancel();

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
    _speakerStateSubscription = _callService.speakerStateStream.listen((_) {
      setState(() {});
    });
    _speakerDeviceIdSubscription = _callService.speakerDeviceIdStream.listen((
      _,
    ) {
      setState(() {});
    });
  }

  void _attachExistingStreams() {
    try {
      // 1. Attach local stream if it exists right away (video-only for preview)
      final currentLocalStream = _callService.cachedVideoStream;
      if (currentLocalStream != null && _localRenderer.srcObject == null) {
        _localRenderer.srcObject = currentLocalStream;
        _localRenderer.muted = true; // avoid local echo
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

  void _handleRemoteStreamsUpdate(Map<String, IMediaStream> streams) {
    if (kIsWeb) {
      _echoReductionDispose?.call();
      _echoReductionDispose = null;
      if (streams.length == 1) {
        final local = _callService.localStream;
        if (local != null && local.getAudioTracks().isNotEmpty) {
          final remote = streams.values.first;
          if (remote.getAudioTracks().isNotEmpty) {
            _echoReductionDispose = startEchoReduction(
              remote,
              local,
              delaySeconds: 0.3,
            );
          }
        }
      }
    }

    final activeIds = streams.keys.toSet();
    final currentIds = _remoteRenderers.keys.toSet();

    for (final id in currentIds.difference(activeIds)) {
      _remoteRenderers[id]?.dispose();
      _remoteRenderers.remove(id);
    }

    for (final id in activeIds) {
      if (!_remoteRenderers.containsKey(id)) {
        final newRenderer = getWebRTCPlatform().createVideoRenderer();
        newRenderer.initialize().then((_) {
          newRenderer.srcObject = streams[id];
          if (mounted) setState(() {});
        });
        _remoteRenderers[id] = newRenderer;
      } else {
        _remoteRenderers[id]!.srcObject = streams[id];
      }
    }

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
    _speakerStateSubscription?.cancel();
    _speakerDeviceIdSubscription?.cancel();

    _echoReductionDispose?.call();
    _echoReductionDispose = null;

    // Dispose the RENDERERS (UI), but DO NOT stop the call.
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
          StreamBuilder<Map<String, IMediaStream>>(
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
                child: StreamBuilder<IMediaStream?>(
                  stream: _callService.cachedVideoStreamStream,
                  initialData: _callService.cachedVideoStream,
                  builder: (context, snapshot) {
                    final stream = snapshot.data;

                    if (stream != null &&
                        stream.getVideoTracks().isNotEmpty) {
                      if (_localRenderer.srcObject != stream) {
                        _localRenderer.srcObject = stream;
                        _localRenderer.muted = true;
                      }
                      return _localRenderer.buildView(mirror: _screenShare);
                    }

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

  Widget _buildGrid(Map<String, IMediaStream> streams) {
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
          speakerDeviceId: _callService.speakerDeviceId,
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
            speakerDeviceId: _callService.speakerDeviceId,
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
                    speakerDeviceId: _callService.speakerDeviceId,
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
                    speakerDeviceId: _callService.speakerDeviceId,
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

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  void _showAudioDeviceSelector() async {
    final selectedDevice = await AudioDevicePopupChooser.show(context: context);
    if (selectedDevice != null) {
      try {
        await _callService.changeAudioDevice(selectedDevice.deviceId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Mic: ${selectedDevice.label.isNotEmpty ? selectedDevice.label : "selected"}',
              ),
            ),
          );
        }
      } catch (e) {
        _logger.e('Error switching audio device: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to switch microphone'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showSpeakerDeviceSelector() async {
    // On mobile, showSpeaker shows only the speaker toggle (via onSpeakerToggle).
    final selectedDevice = await AudioDevicePopupChooser.showSpeaker(
      context: context,
      initialSpeakerOn: _callService.isSpeakerOn,
      onSpeakerToggle: _isMobile
          ? (bool on) {
              _callService.setSpeakerDevice(on ? 'speaker' : 'earpiece');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(on ? 'Speaker phone on' : 'Earpiece'),
                  ),
                );
              }
            }
          : null,
    );
    if (!_isMobile && selectedDevice != null) {
      try {
        _callService.setSpeakerDevice(selectedDevice.deviceId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Speaker: ${selectedDevice.label.isNotEmpty ? selectedDevice.label : "selected"}',
              ),
            ),
          );
        }
      } catch (e) {
        _logger.e('Error setting speaker device: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to set speaker'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// On mobile: opens a dialog with only speaker on/off toggle (no device list).
  void _showSpeakerToggleForMobile() async {
    await AudioDevicePopupChooser.showSpeakerToggle(
      context: context,
      title: 'Speaker phone',
      initialSpeakerOn: _callService.isSpeakerOn,
      onChanged: (bool on) {
        _callService.setSpeakerDevice(on ? 'speaker' : 'earpiece');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(on ? 'Speaker phone on' : 'Earpiece'),
            ),
          );
        }
      },
    );
  }

  void _showAudioSettingsPanel() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AudioSettingsSheet(
        callService: _callService,
        isDesktop: _isDesktop,
        isMobile: _isMobile,
        onSelectMic: _showAudioDeviceSelector,
        onSelectSpeaker: _showSpeakerDeviceSelector,
        onSelectSpeakerToggle: _showSpeakerToggleForMobile,
      ),
    );
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
            icon: const Icon(Icons.settings),
            color: Colors.white,
            tooltip: 'Audio settings',
            onPressed: _showAudioSettingsPanel,
          ),
          if (widget.conversation != null)
            IconButton(
              icon: const Icon(Icons.chat),
              color: Colors.white,
              tooltip: 'View messages',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MessageListPage(
                      conversation: widget.conversation!,
                      onExit: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.red),
            onPressed: () {
              _callService.endCall().catchError((error) {
                _logger.e('Error ending call: $error');
              });
              if (Navigator.of(context).canPop()) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AudioSettingsSheet extends StatelessWidget {
  const _AudioSettingsSheet({
    required this.callService,
    required this.isDesktop,
    required this.isMobile,
    required this.onSelectMic,
    required this.onSelectSpeaker,
    required this.onSelectSpeakerToggle,
  });

  final CallService callService;
  final bool isDesktop;
  final bool isMobile;
  final VoidCallback onSelectMic;
  final VoidCallback onSelectSpeaker;
  final VoidCallback onSelectSpeakerToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Audio',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<bool>(
              stream: callService.micStateStream,
              initialData: true,
              builder: (context, snapshot) {
                final micOn = snapshot.data ?? true;
                return ListTile(
                  leading: Icon(
                    micOn ? Icons.mic : Icons.mic_off,
                    color: micOn ? null : Colors.red,
                  ),
                  title: const Text('Microphone'),
                  subtitle: Text(micOn ? 'On' : 'Muted'),
                  trailing: Switch(
                    value: micOn,
                    onChanged: (_) => callService.toggleMic(),
                  ),
                );
              },
            ),
            StreamBuilder<bool>(
              stream: callService.speakerStateStream,
              initialData: true,
              builder: (context, snapshot) {
                final speakerOn = snapshot.data ?? true;
                return ListTile(
                  leading: Icon(
                    speakerOn ? Icons.volume_up : Icons.volume_off,
                    color: speakerOn ? null : Colors.red,
                  ),
                  title: const Text('Speaker'),
                  subtitle: Text(speakerOn ? 'On' : 'Muted'),
                  trailing: Switch(
                    value: speakerOn,
                    onChanged: (_) => callService.toggleSpeakerMute(),
                  ),
                );
              },
            ),
            const Divider(height: 24),
            if (isDesktop) ...[
              ListTile(
                leading: const Icon(Icons.mic),
                title: const Text('Microphone device'),
                subtitle: const Text('Choose input device'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  onSelectMic();
                },
              ),
              ListTile(
                leading: const Icon(Icons.volume_up),
                title: const Text('Speaker device'),
                subtitle: const Text('Choose output device'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  onSelectSpeaker();
                },
              ),
            ] else if (isMobile) ...[
              ListTile(
                leading: const Icon(Icons.speaker_phone),
                title: const Text('Speaker phone'),
                subtitle: const Text('Loudspeaker or earpiece'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  onSelectSpeakerToggle();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
