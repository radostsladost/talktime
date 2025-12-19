// conference_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:talktime/features/auth/data/auth_service.dart';

enum ConferenceState { connecting, joined, inProgress, ended }

class ConferencePage extends StatefulWidget {
  final String roomId;
  final String conversationId;
  final List<UserInfo> initialParticipants;
  final bool isCreator;

  const ConferencePage({
    super.key,
    required this.roomId,
    required this.conversationId,
    required this.initialParticipants,
    required this.isCreator,
  });

  @override
  State<ConferencePage> createState() => _ConferencePageState();
}

class _ConferencePageState extends State<ConferencePage> {
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;

  SignalingService? _signalingService;
  final Logger _logger = Logger();

  ConferenceState _conferenceState = ConferenceState.connecting;
  bool _isMuted = false;
  bool _isCameraOff = false;

  // Multi-peer maps
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  // Track participants (excluding self)
  Set<String> _participantIds = {};

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _initConference();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
  }

  Future<void> _initConference() async {
    try {
      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        _showErrorAndExit('Permissions required for conference');
        return;
      }

      await _initSignaling();
      await _getUserMedia();

      // Initialize with initial participants (exclude self)
      final selfId = await _getUserId();
      _participantIds = {
        for (var user in widget.initialParticipants)
          if (user.id != selfId) user.id,
      };

      for (final id in _participantIds) {
        await _createPeerConnection(id);
      }

      setState(() {
        _conferenceState = ConferenceState.joined;
      });

      // If creator, send offer to all
      if (widget.isCreator && _participantIds.isNotEmpty) {
        await _createAndSendOffers();
      }
    } catch (e) {
      _logger.e('Init conference error: $e');
      _showErrorAndExit('Failed to join conference');
    }
  }

  Future<String> _getUserId() async {
    final authService = new AuthService();
    // Assuming ApiClient can return current user ID
    final u = await authService.getCurrentUser();
    return u.id;
  }

  Future<bool> _requestPermissions() async {
    final permissions = <Permission>[Permission.microphone, Permission.camera];
    final statuses = await permissions.request();
    return statuses.values.every(
      (status) => status == PermissionStatus.granted,
    );
  }

  Future<void> _initSignaling() async {
    final token = await ApiClient().getToken();
    if (token == null) throw Exception('No token');

    _signalingService = SignalingService(token);
    await _signalingService!.connect();

    _subscriptions
      ..add(_signalingService!.onOffer.listen(_handleOffer))
      ..add(_signalingService!.onAnswer.listen(_handleAnswer))
      ..add(_signalingService!.onIceCandidate.listen(_handleIceCandidate))
      ..add(
        _signalingService!.onParticipantJoined.listen(_handleParticipantJoined),
      )
      ..add(
        _signalingService!.onParticipantLeft.listen(_handleParticipantLeft),
      );

    _signalingService!.createRoom(widget.roomId);
  }

  Future<void> _getUserMedia() async {
    final constraints = {
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
      },
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    if (mounted) {
      setState(() {
        _localRenderer.srcObject = _localStream;
      });
    }
  }

  // ===== PEER CONNECTION MANAGEMENT =====

  Future<void> _createPeerConnection(String participantId) async {
    if (_peerConnections.containsKey(participantId)) return;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _remoteRenderers[participantId] = renderer;

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);

    // Add local tracks
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    // Handle remote stream
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remoteStreams[participantId] = event.streams[0];
          _remoteRenderers[participantId]!.srcObject = event.streams[0];
          if (_conferenceState == ConferenceState.joined) {
            _conferenceState = ConferenceState.inProgress;
          }
        });
      }
    };

    // Handle ICE
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null && _signalingService != null) {
        _signalingService!.sendRoomIceCandidate(
          widget.roomId,
          candidate.candidate!,
          candidate.sdpMid,
          candidate.sdpMLineIndex,
        );
      }
    };

    pc.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _logger.w('Peer $participantId disconnected');
        // Optionally reconnect or remove
      }
    };

    _peerConnections[participantId] = pc;
  }

  Future<void> _removePeerConnection(String participantId) async {
    final pc = _peerConnections.remove(participantId);
    final renderer = _remoteRenderers.remove(participantId);
    _remoteStreams.remove(participantId);

    await pc?.close();
    await renderer?.dispose();
  }

  // ===== SIGNALING HANDLERS =====

  Future<void> _handleParticipantJoined(RoomParticipantUpdate event) async {
    if (!_participantIds.contains(event.user.id) &&
        await _getUserId() != event.user.id) {
      _participantIds.add(event.user.id);
      await _createPeerConnection(event.user.id);

      _logger.i('Participant joined: ${event.user.id}');
      final pc = _peerConnections[event.user.id]!;
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _signalingService!.sendRoomOffer(widget.roomId, offer.sdp!);
      _logger.i('Participant offer sent: ${event.user.id}');
    }
  }

  Future<void> _handleParticipantLeft(RoomParticipantUpdate event) async {
    if (_participantIds.remove(event.user.id) &&
        await _getUserId() != event.user.id) {
      _removePeerConnection(event.user.id);
      if (mounted) setState(() {});
      _logger.i('Participant left: ${event.user.id}');
    }
  }

  Future<void> _handleOffer(SignalingOfferEvent event) async {
    _logger.e('_handleOffer from ${event.fromUserId}');

    if (!_peerConnections.containsKey(event.fromUserId)) {
      await _createPeerConnection(event.fromUserId);
      _participantIds.add(event.fromUserId);
    }

    try {
      final pc = _peerConnections[event.fromUserId]!;
      final offer = RTCSessionDescription(event.sdp, 'offer');
      await pc.setRemoteDescription(offer);

      // Create and send answer
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _signalingService!.sendAnswer(
        event.fromUserId,
        answer.sdp!,
        roomId: widget.roomId,
      );
      _logger.e('_handleOffer sendAnswer from ${event.fromUserId}');
    } catch (e) {
      _logger.e('Error handling offer from ${event.fromUserId}: $e');
    }
  }

  Future<void> _handleAnswer(SignalingAnswerEvent event) async {
    _logger.e('_handleAnswer from ${event.fromUserId}');
    final pc = _peerConnections[event.fromUserId];
    if (pc == null) return;

    try {
      final answer = RTCSessionDescription(event.sdp, 'answer');
      await pc.setRemoteDescription(answer);
      if (mounted && _conferenceState == ConferenceState.joined) {
        setState(() {
          _conferenceState = ConferenceState.inProgress;
        });
      }
    } catch (e) {
      _logger.e('Error handling answer from ${event.fromUserId}: $e');
    }
  }

  Future<void> _handleIceCandidate(SignalingIceCandidateEvent event) async {
    _logger.e('_handleIceCandidate from ${event.fromUserId}');
    final pc = _peerConnections[event.fromUserId];
    if (pc == null) return;

    try {
      final candidate = RTCIceCandidate(
        event.candidate,
        event.sdpMid ?? '',
        event.sdpMLineIndex ?? 0,
      );
      await pc.addCandidate(candidate);
    } catch (e) {
      _logger.e('Error adding ICE candidate: $e');
    }
  }

  // ===== OFFER/ANSWER =====

  Future<void> _createAndSendOffers() async {
    for (final participantId in _participantIds) {
      try {
        final pc = _peerConnections[participantId]!;
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await _signalingService!.sendRoomOffer(widget.roomId, offer.sdp!);
      } catch (e) {
        _logger.e('Error sending offer to $participantId: $e');
      }
    }
  }

  // ===== UI CONTROL =====

  void _toggleMic() {
    final tracks = _localStream?.getAudioTracks();
    if (tracks!.isNotEmpty) {
      final enabled = !tracks[0].enabled;
      tracks[0].enabled = enabled;
      setState(() => _isMuted = !enabled);
    }
  }

  void _toggleCamera() {
    final tracks = _localStream?.getVideoTracks();
    if (tracks!.isNotEmpty) {
      final enabled = !tracks[0].enabled;
      tracks[0].enabled = enabled;
      setState(() => _isCameraOff = !enabled);
    }
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks();
    if (tracks!.isNotEmpty) {
      await Helper.switchCamera(tracks[0]);
    }
  }

  Future<void> _leaveConference() async {
    try {
      await _signalingService?.leaveRoom(widget.roomId);
    } finally {
      _endConference();
    }
  }

  void _endConference() {
    // Clean up all peers
    for (final id in _participantIds.toList()) {
      _removePeerConnection(id);
    }
    _participantIds.clear();

    _localStream?.getTracks().forEach((t) => t.stop());
    _localRenderer.dispose();

    _signalingService?.dispose();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showErrorAndExit(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _endConference();
    for (final sub in _subscriptions) sub.cancel();
    super.dispose();
  }

  // ===== UI BUILD =====

  @override
  Widget build(BuildContext context) {
    final participants = _remoteStreams.keys.toList();
    final totalTiles = participants.length + (_localStream != null ? 1 : 0);
    final columns = totalTiles <= 2 ? 2 : 3;
    final rows = (totalTiles / columns).ceil();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Participant grid
          _conferenceState == ConferenceState.inProgress ||
                  _conferenceState == ConferenceState.joined
              ? GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: totalTiles,
                  itemBuilder: (context, index) {
                    if (index == 0 && _localStream != null) {
                      return _buildLocalTile();
                    }

                    final remoteId =
                        participants[_localStream != null ? index - 1 : index];
                    return _buildRemoteTile(remoteId);
                  },
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 20),
                      Text(
                        'Joining conference...',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),

          // Controls
          Positioned(bottom: 40, left: 0, right: 0, child: _buildControls()),
        ],
      ),
    );
  }

  Widget _buildLocalTile() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          RTCVideoView(
            _localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          if (_isMuted) ...[
            const Positioned.fill(child: ColoredBox(color: Colors.black54)),
            const Positioned(
              bottom: 8,
              right: 8,
              child: Icon(Icons.mic_off, color: Colors.red, size: 24),
            ),
          ],
          if (_isCameraOff)
            const Center(
              child: Icon(Icons.videocam_off, size: 60, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildRemoteTile(String participantId) {
    final renderer = _remoteRenderers[participantId];
    if (renderer == null) {
      return Container(
        color: Colors.grey[800],
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: RTCVideoView(
        renderer,
        mirror: false,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildIconButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          color: _isMuted ? Colors.red : Colors.white,
          onPressed: _toggleMic,
        ),
        const SizedBox(width: 20),
        _buildIconButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: _leaveConference,
          size: 60,
        ),
        const SizedBox(width: 20),
        _buildIconButton(
          icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
          color: _isCameraOff ? Colors.red : Colors.white,
          onPressed: _toggleCamera,
        ),
        const SizedBox(width: 20),
        _buildIconButton(
          icon: Icons.switch_camera,
          color: Colors.white,
          onPressed: _switchCamera,
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 50,
  }) {
    return Material(
      color: color.withOpacity(0.9),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: color == Colors.white ? Colors.black : Colors.white,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}
