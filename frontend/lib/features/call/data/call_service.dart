// features/call/service/call_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/features/auth/data/auth_service.dart';

enum CallState { idle, connecting, connected, ended }

class CallService {
  // Singleton pattern
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final Logger _logger = Logger();
  SignalingService? _signalingService;

  // State Variables
  CallState _state = CallState.idle;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, UserInfo> _participantInfo = {};
  final Set<String> _participantIds = {};

  // Stream Controllers (To update UI)
  final _stateController = StreamController<CallState>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamsController =
      StreamController<Map<String, MediaStream>>.broadcast();
  final _micStateController = StreamController<bool>.broadcast();
  final _camStateController = StreamController<bool>.broadcast();

  // Public Getters
  Stream<CallState> get callStateStream => _stateController.stream;
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;
  Stream<Map<String, MediaStream>> get remoteStreamsStream =>
      _remoteStreamsController.stream;
  Stream<bool> get micStateStream => _micStateController.stream;
  Stream<bool> get camStateStream => _camStateController.stream;

  CallState get currentState => _state;
  Map<String, UserInfo> get participantInfo => _participantInfo;

  String? _currentRoomId;
  bool _isMuted = false;
  bool _isCameraOff = false;

  // =========================================================
  // INITIALIZATION & CONNECTION
  // =========================================================

  Future<void> initService() async {
    // Basic setup, get token, etc.
    final token = await ApiClient().getToken();
    if (token != null &&
        (_signalingService == null || !_signalingService!.isConnected)) {
      _signalingService = SignalingService(token);
      await _signalingService!.connect();
      _setupSignalingListeners();
    }
  }

  Future<void> startCall(
    String roomId,
    List<UserInfo> initialParticipants,
  ) async {
    if (_state != CallState.idle) return; // Already in a call

    _currentRoomId = roomId;
    _updateState(CallState.connecting);

    try {
      // 1. Get Permissions & Media
      await _getUserMedia();
      await _startBackgroundService(roomId);

      // 2. Setup initial participants
      final selfId = (await AuthService().getCurrentUser()).id;
      for (var user in initialParticipants) {
        if (user.id != selfId) {
          _participantIds.add(user.id);
          _participantInfo[user.id] = user;
          await _createPeerConnection(user.id);
        }
      }

      // 3. Join Room via Signaling
      _signalingService?.createRoom(roomId); // Or joinRoom based on logic

      _updateState(CallState.connected);

      // 4. Send Offers
      if (_participantIds.isNotEmpty) {
        await _createAndSendOffers();
      }
    } catch (e) {
      _logger.e("Start call failed: $e");
      endCall();
    }
  }

  Future<void> endCall() async {
    try {
      if (_currentRoomId != null) {
        await _signalingService?.leaveRoom(_currentRoomId!);
      }
    } catch (e) {
      _logger.e("Error leaving room: $e");
    }

    // Clean up WebRTC
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;

    for (var pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();
    _remoteStreams.clear();
    _participantIds.clear();

    _currentRoomId = null;
    _updateState(CallState.idle);
    _localStreamController.add(null);
    _remoteStreamsController.add({});

    // 2. Kill the service when call is done
    await _stopBackgroundService();
  }

  // =========================================================
  // MEDIA CONTROL
  // =========================================================

  void toggleMic() {
    if (_localStream != null) {
      final tracks = _localStream!.getAudioTracks();
      if (tracks.isNotEmpty) {
        _isMuted = !_isMuted;
        tracks[0].enabled = !_isMuted;
        _micStateController.add(_isMuted);
      }
    }
  }

  void toggleCamera() {
    if (_localStream != null) {
      final tracks = _localStream!.getVideoTracks();
      if (tracks.isNotEmpty) {
        _isCameraOff = !_isCameraOff;
        tracks[0].enabled = !_isCameraOff;
        _camStateController.add(_isCameraOff);
      }
    }
  }

  void _updateState(CallState newState) {
    _state = newState;
    _stateController.add(newState);
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

    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStream = stream;
    _localStreamController.add(_localStream);
  }

  // =========================================================
  // WEBRTC INTERNALS
  // =========================================================

  Future<void> _createPeerConnection(String participantId) async {
    if (_peerConnections.containsKey(participantId)) return;

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
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

    // Handle Remote Stream
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStreams[participantId] = event.streams[0];
        // Notify UI
        _remoteStreamsController.add(Map.from(_remoteStreams));
      }
    };

    pc.onIceCandidate = (candidate) {
      if (_currentRoomId != null) {
        _signalingService!.sendRoomIceCandidate(
          _currentRoomId!,
          candidate.candidate!,
          candidate.sdpMid,
          candidate.sdpMLineIndex,
        );
      }
    };

    _peerConnections[participantId] = pc;
  }

  // ... (Include _handleOffer, _handleAnswer, _handleIceCandidate logic here essentially copied from your original file but removing setState calls)

  Future<void> _createAndSendOffers() async {
    for (final id in _participantIds) {
      final pc = _peerConnections[id];
      if (pc != null) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        _signalingService?.sendRoomOffer(_currentRoomId!, offer.sdp!);
      }
    }
  }

  final List<StreamSubscription> _subscriptions = [];
  Future<void> _setupSignalingListeners() async {
    // Setup listeners similar to your original code,
    // but call internal private methods (_handleOffer, etc)
    // and update the Streams instead of calling setState
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

    _signalingService!.createRoom(_currentRoomId!);
  }

  Future<void> _handleOffer(SignalingOfferEvent event) async {
    _logger.e('_handleOffer from ${event.fromUserId}');

    if (!_peerConnections.containsKey(event.fromUserId)) {
      _participantIds.add(event.fromUserId);
      await _createPeerConnection(event.fromUserId);
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

        roomId: _currentRoomId!,
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

      if (_state == CallState.connected) {
        _state = CallState.connecting;
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

  Future<void> _handleParticipantJoined(RoomParticipantUpdate event) async {
    if (!_participantIds.contains(event.user.id) &&
        await _getUserId() != event.user.id) {
      _participantIds.add(event.user.id);

      _participantInfo[event.user.id] = event.user;

      await _createPeerConnection(event.user.id);

      _logger.i('Participant joined: ${event.user.id}');

      final pc = _peerConnections[event.user.id]!;

      final offer = await pc.createOffer();

      await pc.setLocalDescription(offer);

      await _signalingService!.sendRoomOffer(_currentRoomId!, offer.sdp!);

      _logger.i('Participant offer sent: ${event.user.id}');
    }
  }

  Future<void> _handleParticipantLeft(RoomParticipantUpdate event) async {
    if (_participantIds.remove(event.user.id) &&
        await _getUserId() != event.user.id) {
      _participantInfo.remove(event.user.id);

      _removePeerConnection(event.user.id);
      _logger.i('Participant left: ${event.user.id}');
    }
  }

  Future<void> _removePeerConnection(String participantId) async {
    final pc = _peerConnections.remove(participantId);
    _remoteStreams.remove(participantId);
    await pc?.close();
  }

  Future<void> _startBackgroundService(String roomName) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final service = FlutterBackgroundService();

    // Check if it's already running to avoid duplicates
    if (!await service.isRunning()) {
      await service.startService();
    }

    // Wait a moment for the isolate to spin up, then update text
    Future.delayed(const Duration(milliseconds: 500), () {
      service.invoke('updateNotification', {
        'title': 'Active Call',
        'content': 'Talking in $roomName',
      });
    });
  }

  /// Stops the notification when the call ends
  Future<void> _stopBackgroundService() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final service = FlutterBackgroundService();
    service.invoke("stopService");
  }

  Future<String> _getUserId() async {
    final authService = new AuthService();
    // Assuming ApiClient can return current user ID
    final u = await authService.getCurrentUser();
    return u.id;
  }
}
