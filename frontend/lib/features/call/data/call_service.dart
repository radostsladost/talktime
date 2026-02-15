// features/call/service/call_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:path/path.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:pip/pip.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/features/call/webrtc/webrtc_platform.dart';
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
  IWebRTCPlatform get _platform => getWebRTCPlatform();

  // State Variables
  CallState _state = CallState.idle;
  IMediaStream? _localStream;
  IMediaStream? _cachedVideoStream;
  final Map<String, IPeerConnection> _peerConnections = {};
  final Map<String, IMediaStream> _remoteStreams = {};
  final Map<String, UserInfo> _participantInfo = {};
  final Set<String> _participantIds = {};

  // Stream Controllers (To update UI)
  final _stateController = StreamController<CallState>.broadcast();
  final _localStreamController = StreamController<IMediaStream?>.broadcast();
  final _cachedVideoStreamController =
      StreamController<IMediaStream?>.broadcast();
  final _remoteStreamsController =
      StreamController<Map<String, IMediaStream>>.broadcast();
  final _micStateController = StreamController<bool>.broadcast();
  final _camStateController = StreamController<bool>.broadcast();
  final _isScreenSharingController = StreamController<bool>.broadcast();
  final _speakerStateController = StreamController<bool>.broadcast();
  final _speakerDeviceIdController = StreamController<String?>.broadcast();

  // Public Getters
  Stream<bool> get isScreenSharing => _isScreenSharingController.stream;
  Stream<bool> get speakerStateStream => _speakerStateController.stream;
  Stream<String?> get speakerDeviceIdStream =>
      _speakerDeviceIdController.stream;
  bool get isScreenSharingValue => _isScreenSharing;
  Stream<CallState> get callStateStream => _stateController.stream;
  Stream<IMediaStream?> get localStreamStream => _localStreamController.stream;
  Stream<IMediaStream?> get cachedVideoStreamStream =>
      _cachedVideoStreamController.stream;
  Stream<Map<String, IMediaStream>> get remoteStreamsStream =>
      _remoteStreamsController.stream;
  Stream<bool> get micStateStream => _micStateController.stream;
  Stream<bool> get camStateStream => _camStateController.stream;
  // State Getters for UI initialization on navigation return
  IMediaStream? get localStream => _localStream;
  IMediaStream? get cachedVideoStream => _cachedVideoStream;
  Map<String, IMediaStream> get remoteStreams => Map.from(_remoteStreams);
  CallState get currentState => _state;

  /// Room/conversation id of the current call, if any.
  String? get currentRoomId => _currentRoomId;
  Map<String, UserInfo> get participantInfo => _participantInfo;
  bool get isSpeakerMuted => _isSpeakerMuted;
  bool get isMuted => _isMuted;
  String? get speakerDeviceId => _speakerDeviceId;

  /// On Android/iOS: true = loudspeaker, false = earpiece. Only updated when setSpeakerDevice is used.
  bool get isSpeakerOn => _speakerOn;

  String? _currentRoomId;
  bool _isMuted = false;
  bool _isCameraOff = true;
  bool _isScreenSharing = false;
  bool _isSpeakerMuted = false;
  String? _speakerDeviceId;
  bool _speakerOn = true;
  Timer? _timer;
  User? _currentUser;

  // =========================================================
  // INITIALIZATION & CONNECTION
  // =========================================================

  Future<void> initService() async {
    _logger.i('Initializing CallService...');

    // Android: initialize WebRTC (Google WebRTC bridge with AEC) or other platform init.
    if (!kIsWeb && Platform.isAndroid) {
      await _platform.initialize();
      _logger.i('WebRTC platform initialized for Android');
      final ok = await verifyAudioChannel();
      _logger.i(
        'audio_manager channel: ${ok ? "OK" : "not implemented (setAudioMode/Bluetooth will no-op)"}',
      );
    }

    // Always load current user
    try {
      _currentUser = await AuthService().getCurrentUser();
      _logger.i('Current user loaded: ${_currentUser?.id}');
    } catch (e) {
      _logger.e('Failed to load current user: $e');
    }

    // Setup signaling service
    final token = await ApiClient().getToken();
    if (token == null) {
      _logger.w('No token available, skipping signaling setup');
      return;
    }

    if (_signalingService == null || !_signalingService!.isConnected) {
      _logger.i('Setting up signaling service...');
      _signalingService = SignalingService();
      await _signalingService!.connect();
      await _setupSignalingListeners();
      _logger.i('Signaling service connected');
    } else {
      _logger.i('Signaling service already connected');
    }

    _logger.i('CallService initialized successfully');
  }

  Future<void> startCall(
    String roomId,
    List<UserInfo> initialParticipants,
  ) async {
    _logger.i("Start call called: $_state for room: $roomId");
    if (_state != CallState.idle) {
      _logger.w("Call already in progress, ignoring startCall request");
      return; // Already in a call
    }

    setupPip().catchError((error) {
      _logger.e('Error setting auto pip mode: $error', error: error);
    });

    _currentRoomId = roomId;
    _updateState(CallState.connecting);
    _logger.i("Call state updated to connecting for room: $roomId");

    await _setAudioMode(3);

    // CallKit: Start outgoing call
    _callKitStartCall();

    try {
      // 1. Get Permissions & Media
      await _getUserMedia();
      // await activateCameraOrScreenShare(newScreenShareValue: false);
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

      // CallKit: Set call as connected
      _callKitSetConnected();

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
    await _setAudioMode(0);

    final roomIdToEnd = _currentRoomId;
    _logger.i("End call called for room: $roomIdToEnd, current state: $_state");

    if (_state == CallState.idle) {
      _logger.w("No active call to end");
      return;
    }

    disablePip();

    // CallKit: End call before cleanup
    _callKitEndCall();

    _subscriptions.clear();
    try {
      if (_currentRoomId != null) {
        await _signalingService?.leaveRoom(_currentRoomId!);
        await _signalingService
            ?.disconnect(); // Critical fix: Properly disconnect signaling
        _logger.i("Left room and disconnected signaling for: $_currentRoomId");
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

    _logger.i("Call ended successfully, state reset to idle");

    // 2. Kill the service when call is done
    await _stopBackgroundService();
  }

  // =========================================================
  // MEDIA CONTROL
  // =========================================================

  Future<void> toggleScreenShare({DesktopCapturerSourceDto? source}) async {
    await activateCameraOrScreenShare(newScreenShareValue: !_isScreenSharing, source: source);
  }

  Future<void> activateCameraOrScreenShare({
    DesktopCapturerSourceDto? source,
    bool? forceStop,
    bool? newScreenShareValue,
  }) async {
    _logger.i(
      'activateCameraOrScreenShare screenShare: ($_isScreenSharing => $newScreenShareValue), stop: $forceStop',
    );
    try {
      _isScreenSharing = newScreenShareValue ?? false;
      _isScreenSharingController.sink.add(_isScreenSharing);

      IMediaStreamTrack? newVideoTrack;
      IMediaStream? cachedVideoStream;

      if (_localStream != null) {
        // Remove old video tracks
        final oldVideoTracks = [..._localStream!.getVideoTracks()];
        for (var track in oldVideoTracks) {
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
        _logger.i('_replaceVideoTrackInPeerConnections to null');
        _camStateController.add(!_isCameraOff);
        _isScreenSharingController.sink.add(_isScreenSharing);
        await _replaceVideoTrackInPeerConnections(null);
        return;
      }

      if (_isScreenSharing) {
        cachedVideoStream = await _getScreenStream(source?.id);
      }
      if (!_isScreenSharing || cachedVideoStream == null) {
        _logger.i('no cachedVideoStream');
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
          _isScreenSharingController.sink.add(_isScreenSharing);
        }
        await _replaceVideoTrackInPeerConnections(null);
        return;
      }

      newVideoTrack = cachedVideoStream.getVideoTracks().isNotEmpty ? cachedVideoStream.getVideoTracks().first : null;

      if (newVideoTrack == null) {
        _logger.e('Failed to get media stream (track)');
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          const SnackBar(content: Text('Failed to get video device (track)')),
        );
        if (!_isScreenSharing) {
          _isCameraOff = true;
          _isScreenSharingController.sink.add(_isScreenSharing);
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
        _isScreenSharingController.sink.add(_isScreenSharing);
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
    IMediaStreamTrack? newTrack,
  ) async {
    _logger.i(
      'Replacing video track in ${_peerConnections.length} peer connections, '
      'newTrack: ${newTrack?.label ?? "null"}',
    );

    if (_peerConnections.isEmpty) {
      _logger.w('No peer connections to update video track');
      return;
    }

    bool needsRenegotiation = false;

    for (final entry in _peerConnections.entries) {
      final participantId = entry.key;
      final pc = entry.value;

      try {
        final transceivers = await pc.getTransceivers();
        _logger.i(
          'Peer $participantId has ${transceivers.length} transceivers',
        );

        var success = false;
        for (final transceiver in transceivers) {
          final senderTrackKind = transceiver.sender.track?.kind;
          final receiverTrackKind = transceiver.receiverTrack?.kind;
          final isVideoTransceiver =
              senderTrackKind == 'video' || receiverTrackKind == 'video';

          if (isVideoTransceiver) {
            await transceiver.sender.replaceTrack(newTrack);
            _logger.i('Replaced video track for peer $participantId');
            success = true;
            needsRenegotiation = true;
          }
        }

        if (!success && newTrack != null && _localStream != null) {
          _logger.i(
            'No video transceiver found for peer $participantId, adding track instead',
          );
          await pc.addTrack(newTrack, _localStream!);
          needsRenegotiation = true;
        }
      } catch (e) {
        _logger.e('Error replacing video track for peer $participantId: $e');
      }

      // If we added new tracks (not just replaced), we need to renegotiate
      if (needsRenegotiation) {
        _logger.i('New tracks added, triggering renegotiation');
        await _createAndSendOffers(
          onlyParticipantId: participantId,
          forceRenegotiation: true,
        );
      }
    }
  }

  Future<IMediaStream?> _getCameraStream() async {
    if (_usePermissionHandler) {
      final permissions = <Permission>[Permission.camera];
      final statuses = await permissions.request();
      if (statuses[Permission.camera] != PermissionStatus.granted) {
        _logger.i(
          'Camera permission not granted ${statuses[Permission.camera]}',
        );
        if (navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            const SnackBar(content: Text('Camera permission not granted')),
          );
        }
        return null;
      }
    }

    final constraints = Map<String, dynamic>.from({
      'video': Map<String, dynamic>.from({
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 30},
        'facingMode': _facingMode,
      }),
    });

    return await _platform.getUserMedia(constraints);
  }

  Future<IMediaStream?> _getScreenStream(String? sourceId) async {
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

    return await _platform.getDisplayMedia(constraints);
  }

  void toggleMic({bool? forceValue}) {
    final previousMutedState = _isMuted;

    if (forceValue != null) {
      // Force to a specific state: if forceValue is true, we want mic ON (not muted)
      _isMuted = !forceValue;
    } else {
      // Toggle current state
      _isMuted = !_isMuted;
    }

    if (previousMutedState == _isMuted) {
      _logger.i("Mic state unchanged");
      return;
    }

    _logger.i("Toggle mic: $previousMutedState => $_isMuted");

    if (_localStream != null) {
      final tracks = _localStream!.getAudioTracks();
      if (tracks.isNotEmpty) {
        tracks[0].enabled = !_isMuted;
        _micStateController.add(!_isMuted);
        _logger.i("Audio track ${tracks[0].enabled ? 'enabled' : 'disabled'}");
      } else {
        _logger.w("No audio tracks available to toggle");
      }
    } else {
      _logger.w("Local stream is null, cannot toggle mic");
    }

    // CallKit: Update mute state
    if (_currentRoomId != null && _state != CallState.idle) {
      _callKitMuteCall();
    }
  }

  void toggleCamera({bool? forceValue}) {
    final previousCameraState = _isCameraOff;

    if (forceValue != null) {
      // Force to a specific state: if forceValue is true, we want camera ON (not off)
      _isCameraOff = !forceValue;
    } else {
      // Toggle current state
      _isCameraOff = !_isCameraOff;
    }

    _logger.i("Toggle camera: $previousCameraState => $_isCameraOff");

    if (!_isScreenSharing) {
      if (_isCameraOff) {
        activateCameraOrScreenShare(
          forceStop: true,
          newScreenShareValue: false,
        );
      } else {
        activateCameraOrScreenShare(newScreenShareValue: false);
      }
    } else {
      _logger.i("Camera toggle ignored while screen sharing is active");
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

  /// Toggle speaker (remote audio playback) mute. When muted, remote audio
  /// tracks are disabled so no sound is heard.
  void toggleSpeakerMute() {
    _isSpeakerMuted = !_isSpeakerMuted;
    _applySpeakerMuteToRemoteStreams();
    _speakerStateController.add(!_isSpeakerMuted);
    _logger.i('Speaker ${_isSpeakerMuted ? "muted" : "unmuted"}');
  }

  void _applySpeakerMuteToRemoteStreams() {
    for (final stream in _remoteStreams.values) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !_isSpeakerMuted;
      }
    }
  }

  /// Set the audio output device (speaker) for remote playback.
  /// The UI should call [IVideoRenderer.audioOutput(deviceId)] when this changes.
  void setSpeakerDevice(String? deviceId) {
    _logger.i('Speaker device set to: $deviceId');
    if (!kIsWeb && Platform.isAndroid) {
      _routeAudioAndroid(deviceId);
    } else {
      _speakerDeviceId = deviceId;
      _speakerDeviceIdController.add(deviceId);
    }
  }

  Future<void> _routeAudioAndroid(String? deviceId) async {
    try {
      final useSpeaker =
          deviceId?.contains('speaker') == true ||
          deviceId?.contains('loud') == true;
      final useEarpiece =
          deviceId?.contains('earpiece') == true ||
          deviceId?.contains('phone') == true;

      if (deviceId?.contains('bluetooth') == true) {
        await _audioChannel.invokeMethod('startBluetoothSco');
        return;
      }

      // Prefer setCommunicationDevice (API 31+) for better AEC/routing; fallback to setSpeakerphoneOn.
      try {
        final ok = await _audioChannel.invokeMethod<bool>(
          'setCommunicationDevice',
          <String, dynamic>{'speaker': useSpeaker && !useEarpiece},
        );
        if (ok == true) {
          _speakerOn = useSpeaker && !useEarpiece;
          _logger.i(
            'Android audio routed via setCommunicationDevice: $deviceId',
          );
          return;
        }
      } catch (_) {
        // Channel or method not available (old Android), use fallback
      }

      await _setAudioMode(3); // MODE_IN_COMMUNICATION
      if (useSpeaker) {
        _speakerOn = true;
        await _platform.setSpeakerphoneOn(true);
      } else {
        _speakerOn = false;
        await _platform.setSpeakerphoneOn(false);
      }
      _logger.i('Android audio routed via setSpeakerphoneOn: $deviceId');
    } catch (e) {
      _logger.e('Android audio routing failed: $e');
    }
  }

  /// Method channel for Android audio routing (mode, Bluetooth SCO).
  /// Requires native implementation: MainActivity or a plugin must register
  /// a MethodChannel named 'audio_manager' and handle 'setAudioMode' (and
  /// optionally 'startBluetoothSco'). If not implemented, invokeMethod throws
  /// and we log and continue (speaker/earpiece still work via platform.setSpeakerphoneOn).
  static const _audioChannel = MethodChannel('audio_manager');

  /// Call once (e.g. from initService or a debug screen) to verify the native
  /// side responds. Returns true if setAudioMode succeeded, false otherwise.
  static Future<bool> verifyAudioChannel() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      await _audioChannel.invokeMethod('setAudioMode', {'mode': 0});
      return true;
    } catch (e) {
      debugPrint('audio_manager channel not implemented or error: $e');
      return false;
    }
  }

  Future _setAudioMode(int mode) async {
    if (!kIsWeb && !Platform.isAndroid) return;

    try {
      await _audioChannel.invokeMethod('setAudioMode', {'mode': mode});
      _logger.d('Audio mode set to $mode (0=NORMAL, 3=IN_COMMUNICATION)');
    } catch (e) {
      _logger.d('Failed to set audio mode: $e');
    }
  }

  /// Switch the audio input device (microphone) to the given [deviceId].
  /// Replaces the audio track in the local stream and all peer connections.
  Future<void> changeAudioDevice(String deviceId) async {
    try {
      _logger.i('Switching audio device to: $deviceId');

      final audioOpts = <String, dynamic>{
        'deviceId': deviceId,
        ..._audioConstraintsForCall(),
      };
      final newStream = await _platform.getUserMedia({'audio': audioOpts});
      if (newStream == null) throw Exception('getUserMedia returned null');

      final audioTracks = newStream.getAudioTracks();
      if (audioTracks.isEmpty) throw Exception('No audio track in stream');
      final newAudioTrack = audioTracks.first;

      // Replace audio track in local stream
      if (_localStream != null) {
        final oldAudioTracks = _localStream!.getAudioTracks();
        for (final oldTrack in oldAudioTracks) {
          await _localStream!.removeTrack(oldTrack);
          oldTrack.stop();
        }
        await _localStream!.addTrack(newAudioTrack);
      }

      // Replace audio track in all peer connections (via transceivers)
      for (final pc in _peerConnections.values) {
        final transceivers = await pc.getTransceivers();
        for (final transceiver in transceivers) {
          if (transceiver.sender.track?.kind == 'audio') {
            await transceiver.sender.replaceTrack(newAudioTrack);
          }
        }
      }

      _localStreamController.sink.add(_localStream);
      _logger.i('Audio device switched successfully');
    } catch (e) {
      _logger.e('Error changing audio device: $e');
      rethrow;
    }
  }

  void _updateState(CallState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  String _facingMode = 'user';

  /// permission_handler is only implemented on Android/iOS; skip on Linux, Windows, macOS, web.
  bool get _usePermissionHandler =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Audio constraints for the call mic. Strong AEC/AGC/NS to reduce acoustic echo
  /// when using speaker (phone plays remote audio → mic picks it up → remote hears echo).
  Map<String, dynamic> _audioConstraintsForCall() {
    final base = <String, dynamic>{
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    };
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      base['googEchoCancellation'] = true;
      base['googNoiseSuppression'] = true;
      base['googAutoGainControl'] = true;
      base['googHighpassFilter'] = true; // often used with AEC on Android
    }
    return base;
  }

  Future<void> _getUserMedia() async {
    int retries = 0;

    while (retries < 3) {
      try {
        bool audioGranted = true;
        if (_usePermissionHandler) {
          final permissions = <Permission>[
            Permission.camera,
            Permission.microphone,
          ];
          final statuses = await permissions.request();
          audioGranted =
              statuses[Permission.microphone] == PermissionStatus.granted;
        }

        if (!audioGranted) {
          break;
        }

        // Strong AEC/AGC/NS on mobile to reduce acoustic echo (phone speaker → mic → back to PC).
        final audioConstraints = audioGranted
            ? _audioConstraintsForCall()
            : false;

        final stream = await _platform.getUserMedia({
          'audio': audioConstraints,
        });
        if (stream == null) break;

        _localStream = stream;
        _localStreamController.sink.add(_localStream);

        if (_isMuted) {
          Future.delayed(Duration(milliseconds: 300), () {
            toggleMic(forceValue: !_isMuted);
          });
        }

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

    final pc = await _platform.createPeerConnection(config);

    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onTrack = (RTCTrackEventDto event) {
      if (event.streams.isNotEmpty) {
        _logger.i('Received remote stream ${event.streams.first.id}');
        final stream = event.streams.first;
        _remoteStreams[participantId] = stream;
        for (final track in stream.getAudioTracks()) {
          track.enabled = !_isSpeakerMuted;
        }
        if (!kIsWeb && Platform.isAndroid) {
          _setAudioMode(3);
        }
        _remoteStreamsController.add(Map.from(_remoteStreams));
      } else {
        _logger.i('Received remote stream {empty}');
        if (_remoteStreams.containsKey(participantId)) {
          _remoteStreams.remove(participantId);
        }
        _remoteStreamsController.add(Map.from(_remoteStreams));
      }
    };

    pc.onIceCandidate = (candidate) {
      _signalingService!.sendIceCandidate(
        participantId,
        candidate.candidate ?? '',
        candidate.sdpMid,
        candidate.sdpMLineIndex,
        roomId: _currentRoomId,
      );
    };

    pc.onIceConnectionState = (state) {
      _logger.i('ICE connection state for $participantId: $state');

      final isDisconnectedOrFailed =
          state == RTCIceConnectionStateDto.disconnected ||
          state == RTCIceConnectionStateDto.failed;

      if (isDisconnectedOrFailed &&
          _peerConnections.containsKey(participantId)) {
        _logger.w(
          'Peer $participantId disconnected/failed, attempting reconnection',
        );
        _removePeerConnection(participantId).then(
          (_) => Future.delayed(Duration(seconds: 1), () async {
            if (_state != CallState.idle) {
              await _createPeerConnection(participantId);
              await _createAndSendOffers(
                onlyParticipantId: participantId,
                forceRenegotiation: true,
              );
            }
          }),
        );
      }
    };

    _peerConnections[participantId] = pc;
  }

  // ... (Include _handleOffer, _handleAnswer, _handleIceCandidate logic here essentially copied from your original file but removing setState calls)

  /// Creates and sends offers to participants.
  /// [onlyParticipantId] - if set, only send to this participant
  /// [forceRenegotiation] - if true, send offers regardless of polite/impolite rules
  ///                       (used for mid-call renegotiation like adding video tracks)
  Future<void> _createAndSendOffers({
    String? onlyParticipantId,
    bool forceRenegotiation = false,
  }) async {
    for (final id in _participantIds) {
      if (id == _currentUser!.id ||
          (onlyParticipantId != null && id != onlyParticipantId)) {
        continue;
      }

      // Only send offers if we are the impolite peer (higher ID)
      // Exception: forceRenegotiation bypasses this for mid-call track additions
      if (!forceRenegotiation && _isPolite(id)) {
        _logger.i('Skipping offer to $id - we are polite');
        continue;
      }

      var pc = _peerConnections[id];
      if (pc == null) {
        await _createPeerConnection(id);
        pc = _peerConnections[id];
      }

      final state = await pc!.getSignalingState();
      if (state == RTCSignalingStateDto.stable) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        _signalingService?.sendOffer(id, offer.sdp ?? '', roomId: _currentRoomId);
        _logger.i(
          'Offer sent to $id${forceRenegotiation ? " (renegotiation)" : ""}',
        );
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
      _signalingService = SignalingService();
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

      if (state == RTCSignalingStateDto.haveLocalOffer) {
        if (!polite) {
          _logger.w(
            "Collision detected. Impolite peer ignoring offer from ${event.fromUserId}",
          );
          return;
        } else {
          _logger.i(
            "Collision detected. Polite peer rolling back for ${event.fromUserId}",
          );
          await pc.setLocalDescription(RTCSessionDescriptionDto(null, 'rollback'));
        }
      }

      final offer = RTCSessionDescriptionDto(event.sdp, 'offer');
      await pc.setRemoteDescription(offer);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      await _signalingService!.sendAnswer(
        event.fromUserId,
        answer.sdp ?? '',
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

    final state = await pc.getSignalingState();
    if (state == RTCSignalingStateDto.stable) {
      _logger.w(
        "Ignored answer from ${event.fromUserId} because connection is already stable.",
      );
      return;
    }

    try {
      final currentState = await pc.getSignalingState();
      if (currentState != RTCSignalingStateDto.haveRemoteOffer &&
          currentState != RTCSignalingStateDto.stable) {
        final answer = RTCSessionDescriptionDto(event.sdp, 'answer');
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

      var remoteDesc = await pc.getRemoteDescription();
      if (remoteDesc == null) {
        int retries = 0;
        while (retries < 3 && remoteDesc == null) {
          retries++;
          await Future.delayed(Duration(seconds: 1 * retries));
          remoteDesc = await pc.getRemoteDescription();
        }
        if (remoteDesc == null) {
          _logger.i(
            '_handleIceCandidate remoteDesc is null: ${event.fromUserId}',
          );
          return;
        }
      }

      final candidate = RTCIceCandidateDto(
        event.candidate,
        event.sdpMid,
        event.sdpMLineIndex,
      );
      await pc.addIceCandidate(candidate);
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
        offer.sdp ?? '',
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

  // =========================================================
  // CALLKIT INTEGRATION
  // =========================================================
  /// CallKit integration: Start outgoing call (iOS/Android only)
  Future<void> _callKitStartCall() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final params = _createCallKitParams();
    if (params == null || params.id == null) {
      _logger.w("Cannot start CallKit call - missing room ID");
      return;
    }

    try {
      await FlutterCallkitIncoming.startCall(params);
      _logger.i("CallKit: Started outgoing call for room: ${params.id}");
    } catch (e) {
      _logger.e("CallKit: Error starting call: $e", error: e);
    }
  }

  /// CallKit integration: Set call as connected (iOS/Android only)
  Future<void> _callKitSetConnected() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    if (_currentRoomId == null) {
      _logger.w("Cannot set CallKit call connected - missing room ID");
      return;
    }

    try {
      await FlutterCallkitIncoming.setCallConnected(_currentRoomId!);
      _logger.i("CallKit: Set call connected for room: $_currentRoomId");
    } catch (e) {
      _logger.e("CallKit: Error setting call connected: $e", error: e);
    }
  }

  /// CallKit integration: Mute/unmute call (iOS/Android only)
  Future<void> _callKitMuteCall() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    if (_currentRoomId == null) {
      _logger.w("Cannot mute CallKit call - missing room ID");
      return;
    }

    try {
      await FlutterCallkitIncoming.muteCall(_currentRoomId!, isMuted: _isMuted);
      _logger.i(
        "CallKit: Mute state updated - room: $_currentRoomId, muted: $_isMuted",
      );
    } catch (e) {
      _logger.e("CallKit: Error muting call: $e", error: e);
    }
  }

  /// CallKit integration: End call (iOS/Android only)
  Future<void> _callKitEndCall() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final roomId = _currentRoomId;
    if (roomId == null) {
      _logger.w("Cannot end CallKit call - missing room ID");
      return;
    }

    try {
      await FlutterCallkitIncoming.endCall(roomId);
      _logger.i("CallKit: Ended call for room: $roomId");
    } catch (e) {
      _logger.e("CallKit: Error ending call: $e", error: e);
    }
  }

  /// Creates CallKitParams from current call state
  CallKitParams? _createCallKitParams() {
    if (_currentRoomId == null) return null;

    // Build participant names for display
    final participantNames = _participantInfo.values
        .map((user) => user.username)
        .where((name) => name.isNotEmpty)
        .take(3)
        .join(', ');

    final callerName = participantNames.isNotEmpty
        ? participantNames
        : 'TalkTime Call';

    return CallKitParams(
      id: _currentRoomId!,
      nameCaller: callerName,
      appName: 'TalkTime',
      type: 0, // Audio call (1 would be video, but we'll keep it as 0 for now)
    );
  }

  final _pip = Pip();
  Future<void> setupPip() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // Check if device supports PiP
      bool isPipSupported = await _pip.isSupported();
      // Check if auto-enter PiP mode is supported
      bool isPipAutoEnterSupported = await _pip.isAutoEnterSupported();
      // Check if currently in PiP mode
      // bool isPipActived = await _pip.isActived();

      if (isPipSupported && isPipAutoEnterSupported) {
        final options = PipOptions(
          autoEnterEnabled: true, // Enable/disable auto-enter PiP mode
          // Android specific options
          aspectRatioX: 1, // Aspect ratio X value
          aspectRatioY: 1, // Aspect ratio Y value
          sourceRectHintLeft: 0, // Source rectangle left position
          sourceRectHintTop: 0, // Source rectangle top position
          sourceRectHintRight: 720, // Source rectangle right position
          sourceRectHintBottom: 720, // Source rectangle bottom position
          // iOS specific options
          sourceContentView: 0, // Source content view
          contentView: 0, // Content view to be displayed in PiP
          preferredContentWidth: 480, // Preferred content width
          preferredContentHeight: 480, // Preferred content height
          controlStyle: 2, // Control style for PiP window
        );

        await _pip.setup(options);
      }
    }
  }

  Future<void> disablePip() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // Check if device supports PiP
      bool isPipSupported = await _pip.isSupported();
      // Check if auto-enter PiP mode is supported
      bool isPipAutoEnterSupported = await _pip.isAutoEnterSupported();
      // Check if currently in PiP mode
      // bool isPipActived = await _pip.isActived();

      if (isPipSupported && isPipAutoEnterSupported) {
        final options = PipOptions(
          autoEnterEnabled: false, // Enable/disable auto-enter PiP mode
          // Android specific options
          // iOS specific options
          sourceContentView: 0, // Source content view
          contentView: 0, // Content view to be displayed in PiP
          controlStyle: 2, // Control style for PiP window
        );

        await _pip.setup(options);
      }
    }
  }
}
