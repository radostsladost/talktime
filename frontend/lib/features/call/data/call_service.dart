// features/call/service/call_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path/path.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:talktime/core/global_key.dart';

enum CallState { idle, connecting, connected, ended }

class CallService {
  // Singleton pattern
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final Logger _logger = Logger(output: ConsoleOutput());
  SignalingService? _signalingService;

  // State Variables
  CallState _state = CallState.idle;
  MediaStream? _localStream;
  MediaStream? _cachedVideoStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, UserInfo> _participantInfo = {};
  final Set<String> _participantIds = {};

  // Stream Controllers (To update UI)
  final _stateController = StreamController<CallState>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _cachedVideoStreamController =
      StreamController<MediaStream?>.broadcast();
  final _remoteStreamsController =
      StreamController<Map<String, MediaStream>>.broadcast();
  final _micStateController = StreamController<bool>.broadcast();
  final _camStateController = StreamController<bool>.broadcast();
  final _isScreenSharingController = StreamController<bool>.broadcast();

  // Public Getters
  Stream<bool> get isScreenSharing => _isScreenSharingController.stream;
  bool get isScreenSharingValue => _isScreenSharing;
  Stream<CallState> get callStateStream => _stateController.stream;
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;
  Stream<MediaStream?> get cachedVideoStreamStream =>
      _cachedVideoStreamController.stream;
  Stream<Map<String, MediaStream>> get remoteStreamsStream =>
      _remoteStreamsController.stream;
  Stream<bool> get micStateStream => _micStateController.stream;
  Stream<bool> get camStateStream => _camStateController.stream;
  // State Getters for UI initialization on navigation return
  MediaStream? get localStream => _localStream;
  MediaStream? get cachedVideoStream => _cachedVideoStream;
  Map<String, MediaStream> get remoteStreams => Map.from(_remoteStreams);
  CallState get currentState => _state;
  Map<String, UserInfo> get participantInfo => _participantInfo;

  String? _currentRoomId;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isScreenSharing = false;
  Timer? _timer;
  User? _currentUser;

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
      await _setupSignalingListeners();
      _currentUser = await AuthService().getCurrentUser();
    }
  }

  Future<void> startCall(
    String roomId,
    List<UserInfo> initialParticipants,
  ) async {
    _logger.i("Start call called: $_state");
    if (_state != CallState.idle) return; // Already in a call

    _currentRoomId = roomId;
    _updateState(CallState.connecting);

    try {
      // 1. Get Permissions & Media
      await _getUserMedia();
      await activateCameraOrScreenShare(newScreenShareValue: false);
      await _startBackgroundService(roomId);

      // 2. Setup initial participants
      final selfId = _currentUser!.id;
      for (var user in initialParticipants) {
        if (user.id != selfId) {
          _participantIds.add(user.id);
          _participantInfo[user.id] = user;
          await _createPeerConnection(user.id);
        }
      }

      // 3. Join Room via Signaling
      await _signalingService?.createRoom(roomId); // Or joinRoom based on logic

      _updateState(CallState.connected);

      // 4. Send Offers
      if (_participantIds.isNotEmpty) {
        await _createAndSendOffers();
      }

      if (_timer != null) {
        _timer!.cancel();
        _timer = null;
      }
      // _timer = Timer.periodic(
      //   Duration(seconds: 30),
      //   (Timer t) => _createAndSendOffers(),
      // );
    } catch (e, stackTrace) {
      _logger.e("Start call failed: $e", error: e, stackTrace: stackTrace);
      endCall();
    }
  }

  Future<void> endCall() async {
    _subscriptions.clear();
    try {
      if (_currentRoomId != null) {
        await _signalingService?.leaveRoom(_currentRoomId!);
        await _signalingService
            ?.disconnect(); // Critical fix: Properly disconnect signaling
      }
    } catch (e) {
      _logger.e("Error leaving room: $e");
    }

    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }

    if (_cachedVideoStream != null) {
      _cachedVideoStream?.dispose();
      _cachedVideoStream = null;
      _cachedVideoStreamController.sink.add(null);
    }

    // Clean up WebRTC
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        // Explicitly stop tracks before disposing the stream object
        if (track.enabled) {
          track.enabled = false; // Disable if enabled
        }
        track.stop();
      }
      _localStream?.dispose();
    }
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

  Future<void> toggleScreenShare({DesktopCapturerSource? source}) async {
    await activateCameraOrScreenShare(newScreenShareValue: !_isScreenSharing);
  }

  Future<void> activateCameraOrScreenShare({
    DesktopCapturerSource? source,
    bool? forceStop,
    bool? newScreenShareValue,
  }) async {
    _logger.i(
      'activateCameraOrScreenShare screenShare: ($_isScreenSharing => $newScreenShareValue), stop: $forceStop',
    );
    try {
      _isScreenSharing = newScreenShareValue ?? false;
      _isScreenSharingController.sink.add(_isScreenSharing);

      MediaStreamTrack? newVideoTrack;
      MediaStream? cachedVideoStream;

      if (_localStream != null) {
        // Remove old video tracks
        final oldVideoTracks = [..._localStream!.getVideoTracks()];
        for (var track in oldVideoTracks) {
          // print("Enumerating oldTracks: ${track.label} - ${track.kind}");
          try {
            await _localStream!.removeTrack(track);
          } catch (_) {}
          try {
            track.stop();
          } catch (_) {}
        }
      }

      if (_cachedVideoStream != null) {
        _cachedVideoStream?.dispose();
        _cachedVideoStream = null;
        _cachedVideoStreamController.sink.add(null);
      }

      if ((_isCameraOff && !_isScreenSharing) || forceStop == true) {
        _camStateController.add(!_isCameraOff);
        await _replaceVideoTrackInPeerConnections(null);
        return;
      }

      if (_isScreenSharing) {
        // Get screen stream and extract video track
        cachedVideoStream = await _getScreenStream(source?.id);
      }
      if (!_isScreenSharing || cachedVideoStream == null) {
        _isScreenSharing = false;
        // Get camera stream and extract video track
        cachedVideoStream = await _getCameraStream();
      }

      if (cachedVideoStream == null) {
        _logger.e('Failed to get media stream');
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          const SnackBar(content: Text('Failed to get video device')),
        );
        if (!_isScreenSharing) {
          _isCameraOff = true;
          _camStateController.add(!_isCameraOff);
        }
        await _replaceVideoTrackInPeerConnections(null);
        return;
      }

      newVideoTrack = cachedVideoStream.getVideoTracks().firstOrNull;

      if (newVideoTrack == null) {
        _logger.e('Failed to get media stream (track)');
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          const SnackBar(content: Text('Failed to get video device (track)')),
        );
        if (!_isScreenSharing) {
          _isCameraOff = true;
          _camStateController.add(!_isCameraOff);
        }
        await _replaceVideoTrackInPeerConnections(null);
        return;
      }

      if (!_isScreenSharing) {
        _isCameraOff = false;
        _camStateController.add(true);
      }
      // Replace video track in local stream
      if (_localStream != null) {
        // Add new video track
        await _localStream!.addTrack(newVideoTrack);

        // Replace track in all peer connections
        await _replaceVideoTrackInPeerConnections(newVideoTrack);

        _logger.i('camera activated successfully');
        _cachedVideoStream = cachedVideoStream;
        _localStreamController.sink.add(_localStream);
        _cachedVideoStreamController.sink.add(_cachedVideoStream);
      } else {
        _logger.e('_localStream is null');
        await _replaceVideoTrackInPeerConnections(null);
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error toggling screen sharing: $e',
        error: e,
        stackTrace: stackTrace,
      );
      _isScreenSharing = false;
      _isScreenSharingController.sink.add(_isScreenSharing);
    }
  }

  Future<void> _replaceVideoTrackInPeerConnections(
    MediaStreamTrack? newTrack,
  ) async {
    for (final pc in _peerConnections.values) {
      final transceivers = await pc.getTransceivers();
      var success = false;
      for (final transceiver in transceivers) {
        // Use transceiver.sender.track?.kind for active tracks,
        // or check the transceiver's mid/receiver for video type when track is null
        final senderTrackKind = transceiver.sender.track?.kind;
        final receiverTrackKind = transceiver.receiver.track?.kind;
        final isVideoTransceiver =
            senderTrackKind == 'video' || receiverTrackKind == 'video';
        if (isVideoTransceiver) {
          await transceiver.sender.replaceTrack(newTrack);
          success = true;
        }
      }
      if (!success && newTrack != null && _localStream != null) {
        _logger.i(
          'Failed to replace video track in peer connection, adding it instead',
        );
        await pc.addTrack(newTrack, _localStream!);
      }
    }
  }

  Future<MediaStream?> _getCameraStream() async {
    // Check permissions first
    final permissions = <Permission>[Permission.camera];
    final statuses = await permissions.request();

    if (statuses[Permission.camera] != PermissionStatus.granted) {
      _logger.i('Camera permission not granted');
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
        const SnackBar(content: Text('Camera permission not granted')),
      );
      return null;
    }

    final constraints = {
      'video': {
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 30},
        'facingMode': _facingMode,
      },
    };

    return await navigator.mediaDevices.getUserMedia(constraints);
  }

  Future<MediaStream> _getScreenStream(String? sourceId) async {
    final constraints = sourceId != null
        ? {
            'video': {
              'deviceId': {'exact': sourceId},
            },
            'audio': false,
          }
        : {
            'video': {'cursor': 'always'},
            'audio': false,
          };

    final stream = await navigator.mediaDevices.getDisplayMedia(constraints);
    return stream;
  }

  void toggleMic() {
    if (_localStream != null) {
      final tracks = _localStream!.getAudioTracks();
      if (tracks.isNotEmpty) {
        _isMuted = !_isMuted;
        tracks[0].enabled = !_isMuted;
        _micStateController.add(!_isMuted);
      }
    }
  }

  void toggleCamera() {
    _isCameraOff = !_isCameraOff;
    if (!_isScreenSharing) {
      if (_isCameraOff) {
        activateCameraOrScreenShare(
          forceStop: true,
          newScreenShareValue: false,
        );
      } else {
        activateCameraOrScreenShare(newScreenShareValue: false);
      }
    }
    _camStateController.add(!_isCameraOff);
  }

  void changeCameraDevice() async {
    if (_facingMode == 'user') {
      _facingMode = 'environment';
    } else {
      _facingMode = 'user';
    }

    try {
      if (!_isScreenSharing) {
        await activateCameraOrScreenShare(newScreenShareValue: false);
      }
    } catch (e) {
      _logger.e('Error changing camera device: $e');
    }
  }

  void _updateState(CallState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  String _facingMode = 'user';
  Future<void> _getUserMedia() async {
    int retries = 0;

    while (retries < 3) {
      try {
        // Check permissions first
        final permissions = <Permission>[
          Permission.camera,
          Permission.microphone,
        ];
        final statuses = await permissions.request();

        // final videoGranted =
        //     statuses[Permission.camera] == PermissionStatus.granted;
        final audioGranted =
            statuses[Permission.microphone] == PermissionStatus.granted;

        if (!audioGranted) {
          break;
        }

        var audioConstraints = audioGranted
            ? {'echoCancellation': true, 'noiseSuppression': true}
            : false;

        // Create single stream with both audio and video
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': audioConstraints,
        });

        _localStream = stream;
        _localStreamController.sink.add(_localStream);

        _micStateController.add(audioGranted);
        return;
      } catch (e) {
        retries++;
        if (retries >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * retries));
        _logger.w('Media retry #$retries due to: $e');
      }
    }
  }

  // =========================================================
  // WEBRTC INTERNALS
  // =========================================================

  Future<void> _createPeerConnection(String participantId) async {
    if (_peerConnections.containsKey(participantId)) return;

    final config = {
      'iceServers': [
        {
          'urls': ['stun:v776682.macloud.host:5349'],
          "username": "turnserver",
          "credential":
              "959212b0629ad5c3e7d8c3f9ccc20771e5c3596370847f1fd85feda871e11d56",
        },
        {
          'urls': ['turns:v776682.macloud.host:5349'],
          "username": "turnserver",
          "credential":
              "959212b0629ad5c3e7d8c3f9ccc20771e5c3596370847f1fd85feda871e11d56",
        },
        {
          'urls': ['stun:stun.l.google.com:19302'],
          "username": "",
          "credential": "",
        },
        {
          'urls': ['stun:stun.rtc.yandex.net'],
          "username": "",
          "credential": "",
        },
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);

    // Add local tracks from single local stream
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    // Handle Remote Stream
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        // Store only the first/primary stream for this participant
        _remoteStreams[participantId] = event.streams.first;
        // Notify UI
        _remoteStreamsController.add(Map.from(_remoteStreams));
      } else {
        // Handle case where no stream is available
        if (_remoteStreams.containsKey(participantId)) {
          _remoteStreams.remove(participantId);
        }
        _remoteStreamsController.add(Map.from(_remoteStreams));
      }
    };

    // pc.onRemoveTrack = (MediaStream stream, MediaStreamTrack track) {
    //   if (_remoteStreams.containsKey(participantId)) {
    //     _remoteStreamsController.add(Map.from(_remoteStreams));
    //   }
    // };
    // pc.onRemoveStream = (MediaStream stream) {
    //   if (_remoteStreams.containsKey(participantId)) {
    //     _remoteStreams.remove(participantId);
    //     _remoteStreamsController.add(Map.from(_remoteStreams));
    //   }
    // };

    pc.onIceCandidate = (candidate) {
      _signalingService!.sendIceCandidate(
        participantId,
        candidate.candidate!,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
        roomId: _currentRoomId,
      );
    };

    pc.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _logger.w('Peer $participantId disconnected');
        _removePeerConnection(participantId).then(
          (_) => Future.delayed(Duration(seconds: 1), () async {
            final pc = _peerConnections[participantId]!;
            final offer = await pc.createOffer();
            await pc.setLocalDescription(offer);
            await _signalingService!.sendOffer(
              participantId,
              offer.sdp!,
              roomId: _currentRoomId,
            );
          }),
        );
      }
    };

    _peerConnections[participantId] = pc; // add
  }

  // ... (Include _handleOffer, _handleAnswer, _handleIceCandidate logic here essentially copied from your original file but removing setState calls)

  Future<void> _createAndSendOffers() async {
    for (final id in _participantIds) {
      if (id == _currentUser!.id) continue;

      // Only send offers if we are the impolite peer (higher ID)
      if (_isPolite(id)) {
        _logger.i('Skipping offer to $id - we are polite');
        continue;
      }

      var pc = _peerConnections[id];
      if (pc == null) {
        await _createPeerConnection(id);
        pc = _peerConnections[id];
      }

      final state = await pc!.getSignalingState();
      if (state == RTCSignalingState.RTCSignalingStateStable) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        _signalingService?.sendOffer(id, offer.sdp!, roomId: _currentRoomId);
        _logger.i('Offer sent to $id');
      } else {
        _logger.w('Skipping offer to $id - not in stable state: $state');
      }
    }
  }

  final List<StreamSubscription> _subscriptions = [];
  Future<void> _setupSignalingListeners() async {
    // Setup listeners similar to your original code,
    // but call internal private methods (_handleOffer, etc)
    // and update the Streams instead of calling setState
    if (_subscriptions.isNotEmpty && _signalingService?.isConnected == true) {
      _logger.i("Signaling listeners already set up. Skipping.");

      if (_currentRoomId != null) {
        _signalingService!.createRoom(_currentRoomId!);
      }
      return;
    }

    final token = await ApiClient().getToken();
    if (token == null) throw Exception('No token');

    if (_signalingService == null || !_signalingService!.isConnected) {
      _signalingService = SignalingService(token);
      await _signalingService!.connect();
    }

    _subscriptions.clear();
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

    if (_currentRoomId != null) _signalingService!.createRoom(_currentRoomId!);
  }

  // Determine if we are the "polite" peer (lower ID is polite, higher ID is impolite)
  bool _isPolite(String otherUserId) {
    return _currentUser!.id.compareTo(otherUserId) < 0;
  }

  Future<void> _handleOffer(SignalingOfferEvent event) async {
    _logger.i('_handleOffer from ${event.fromUserId} to ${event.toUserId}');

    // Only process offers intended for us
    if (event.toUserId != _currentUser!.id) {
      _logger.i('Ignoring offer not intended for us (to: ${event.toUserId})');
      return;
    }

    if (!_peerConnections.containsKey(event.fromUserId)) {
      _participantIds.add(event.fromUserId);
      await _createPeerConnection(event.fromUserId);
    }

    try {
      final pc = _peerConnections[event.fromUserId]!;
      final state = await pc.getSignalingState();
      final polite = _isPolite(event.fromUserId);

      // Perfect negotiation pattern:
      // - If we have a local offer pending (have-local-offer) and we're impolite, ignore incoming offer
      // - If we're polite, we should rollback and accept the incoming offer
      if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        if (!polite) {
          // We are impolite, ignore their offer - our offer wins
          _logger.w(
            "Collision detected. Impolite peer ignoring offer from ${event.fromUserId}",
          );
          return;
        } else {
          // We are polite, rollback our offer and accept theirs
          _logger.i(
            "Collision detected. Polite peer rolling back for ${event.fromUserId}",
          );
          await pc.setLocalDescription(RTCSessionDescription(null, 'rollback'));
        }
      }

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

      _logger.i('_handleOffer sendAnswer to ${event.fromUserId}');
    } catch (e) {
      _logger.e('Error handling offer from ${event.fromUserId}: $e');
    }
  }

  Future<void> _handleAnswer(SignalingAnswerEvent event) async {
    _logger.i('_handleAnswer from ${event.fromUserId} to ${event.toUserId}');

    // Only process answers intended for us
    if (event.toUserId != _currentUser!.id) {
      _logger.i('Ignoring answer not intended for us (to: ${event.toUserId})');
      return;
    }

    final pc = _peerConnections[event.fromUserId];
    if (pc == null) {
      _logger.e('_handleAnswer _peerConnection is null: ${event.fromUserId}');
      return;
    }

    // Wait for syncronization
    await Future.delayed(const Duration(seconds: 1), () {});

    // --- FIX START ---
    // Check if we are actually waiting for an answer
    final state = await pc.getSignalingState();
    if (state == RTCSignalingState.RTCSignalingStateStable) {
      _logger.w(
        "Ignored answer from ${event.fromUserId} because connection is already stable.",
      );
      return;
    }
    // --- FIX END ---

    try {
      final currentState = await pc.getSignalingState();
      if (currentState != RTCSignalingState.RTCSignalingStateHaveRemoteOffer &&
          currentState != RTCSignalingState.RTCSignalingStateStable) {
        final answer = RTCSessionDescription(event.sdp, 'answer');
        await pc.setRemoteDescription(answer);
      }

      if (_state == CallState.connecting) {
        _state = CallState.connected;
      }
    } catch (e) {
      _logger.e('Error handling answer from ${event.fromUserId}: $e');
    }
  }

  Future<void> _handleIceCandidate(SignalingIceCandidateEvent event) async {
    _logger.i(
      '_handleIceCandidate from ${event.fromUserId} to ${event.toUserId}',
    );

    // Only process ICE candidates intended for us
    if (event.toUserId != _currentUser!.id) {
      _logger.i(
        'Ignoring ICE candidate not intended for us (to: ${event.toUserId})',
      );
      return;
    }

    try {
      final pc = _peerConnections[event.fromUserId];
      if (pc == null) {
        _logger.e(
          '_handleIceCandidate _peerConnection is null: ${event.fromUserId}',
        );
        return;
      }

      // if its just sync error
      var remoteDesc = await pc.getRemoteDescription();
      if (remoteDesc == null) {
        int retries = 0;
        while (retries < 3 && remoteDesc == null) {
          retries++;
          await Future.delayed(Duration(seconds: 1 * retries), () async {
            return 1;
          });
          remoteDesc = await pc.getRemoteDescription();
        }

        if (remoteDesc == null) {
          _logger.i(
            '_handleIceCandidate remoteDesc is null: ${event.fromUserId}',
          );
          return;
        }
      }

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
    _logger.i('_handleParticipantJoined  ${event.user.id}');
    if (_currentUser!.id == event.user.id) {
      return;
    }
    await Future.delayed(const Duration(seconds: 1), () {});

    _participantIds.add(event.user.id);
    _participantInfo[event.user.id] = event.user;
    await _createPeerConnection(event.user.id);

    _logger.i('Participant joined: ${event.user.id}');

    // Only the "impolite" peer (higher ID) initiates the offer to avoid glare
    if (!_isPolite(event.user.id)) {
      _logger.i('We are impolite, sending offer to ${event.user.id}');
      final pc = _peerConnections[event.user.id]!;
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _signalingService!.sendOffer(
        event.user.id,
        offer.sdp!,
        roomId: _currentRoomId,
      );
      _logger.i('Participant offer sent: ${event.user.id}');
    } else {
      _logger.i('We are polite, waiting for offer from ${event.user.id}');
    }
  }

  Future<void> _handleParticipantLeft(RoomParticipantUpdate event) async {
    _logger.i('_handleParticipantLeft  ${event.user.id}');
    if (_currentUser!.id == event.user.id) {
      return;
    }

    if (_participantIds.remove(event.user.id)) {
      _participantInfo.remove(event.user.id);

      _removePeerConnection(event.user.id);
      _logger.i('Participant left: ${event.user.id}');
    }
  }

  Future<void> _removePeerConnection(String participantId) async {
    final pc = _peerConnections.remove(participantId);
    _remoteStreams.remove(participantId);
    await pc?.close();

    _remoteStreams.remove(participantId);
    _remoteStreamsController.sink.add(_remoteStreams);
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
}
