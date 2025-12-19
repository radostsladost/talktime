import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/core/network/api_client.dart';

enum CallType { audio, video }

enum CallState { connecting, ringing, inProgress, ended }

class CallPage extends StatefulWidget {
  final bool isOutgoing;
  final String peerName;
  final String peerId;
  final String? callId;
  final CallType callType;

  const CallPage({
    super.key,
    required this.isOutgoing,
    required this.peerName,
    required this.peerId,
    this.callId,
    this.callType = CallType.audio,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  RTCPeerConnection? _peerConnection;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;

  SignalingService? _signalingService;
  final Logger _logger = Logger();

  CallState _callState = CallState.connecting;
  String? _currentCallId;
  bool _isMuted = false;
  bool _isCameraOff = false;
  Timer? _timer;

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _currentCallId = widget.callId;
    _initRenderers();
    _initCall();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _initCall() async {
    try {
      // Request permissions first
      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        _logger.e('Permissions denied, exiting call');
        if (mounted) {
          _showErrorAndExit('Microphone permission is required for calls');
        }
        return;
      }

      // Initialize SignalR service
      await _initSignaling();

      // Get local media stream
      await _getUserMedia();

      // Initialize peer connection
      await _createPeerConnection();

      // Set up call flow based on whether it's incoming or outgoing
      if (widget.isOutgoing) {
        await _handleOutgoingCall();
      } else {
        setState(() {
          _callState = CallState.ringing;
        });
      }
    } catch (e) {
      _logger.e('Error initializing call: $e');
      if (mounted) {
        _showErrorAndExit('Failed to initialize call: $e');
      }
    }
  }

  Future<bool> _requestPermissions() async {
    final permissions = <Permission>[
      Permission.microphone,
      if (widget.callType == CallType.video) Permission.camera,
    ];

    final statuses = await permissions.request();

    // Check if all required permissions are granted
    for (final permission in permissions) {
      if (statuses[permission] != PermissionStatus.granted) {
        _logger.w('Permission denied: $permission');
        return false;
      }
    }

    return true;
  }

  Future<void> _initSignaling() async {
    try {
      // Get access token from storage
      final apiClient = ApiClient();
      final token = await apiClient.getToken();

      if (token == null) {
        throw Exception('No access token found');
      }

      _signalingService = SignalingService(token);
      await _signalingService!.connect();

      // Subscribe to signaling events
      _subscriptions
        ..add(_signalingService!.onIncomingCall.listen(_handleIncomingCall))
        ..add(_signalingService!.onCallAccepted.listen(_handleCallAccepted))
        ..add(_signalingService!.onCallRejected.listen(_handleCallRejected))
        ..add(_signalingService!.onCallEnded.listen(_handleCallEnded))
        ..add(_signalingService!.onOffer.listen(_handleOffer))
        ..add(_signalingService!.onAnswer.listen(_handleAnswer))
        ..add(_signalingService!.onIceCandidate.listen(_handleIceCandidate))
        ..add(_signalingService!.onCallInitiated.listen(_handleCallInitiated));

      _logger.i('SignalR service initialized successfully');
    } catch (e) {
      _logger.e('Failed to initialize signaling: $e');
      rethrow;
    }
  }

  Future<void> _getUserMedia() async {
    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': widget.callType == CallType.video
            ? {
                'mandatory': {
                  'minWidth': '640',
                  'minHeight': '480',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      if (mounted) {
        setState(() {
          _localRenderer.srcObject = _localStream;
        });
      }

      _logger.i('Local media stream obtained');
    } catch (e) {
      _logger.e('Error getting user media: $e');
      rethrow;
    }
  }

  Future<void> _createPeerConnection() async {
    try {
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          // Add TURN servers for production
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(configuration);

      // Add local stream tracks to peer connection
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
      }

      // Handle remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        _logger.i('Received remote track');
        if (event.streams.isNotEmpty) {
          if (mounted) {
            setState(() {
              _remoteRenderer.srcObject = event.streams[0];
              _callState = CallState.inProgress;
            });
          }
        }
      };

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _logger.d('New ICE candidate: ${candidate.candidate}');
        if (_signalingService != null && candidate.candidate != null) {
          _signalingService!.sendIceCandidate(
            widget.peerId,
            candidate.candidate!,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
          );
        }
      };

      // Handle ICE connection state
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        _logger.i('ICE connection state: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _handleConnectionLost();
        }
      };

      _logger.i('Peer connection created');
    } catch (e) {
      _logger.e('Error creating peer connection: $e');
      rethrow;
    }
  }

  Future<void> _handleOutgoingCall() async {
    try {
      setState(() {
        _callState = CallState.connecting;
      });

      // Initiate call through SignalR
      final callType = widget.callType == CallType.video ? 'video' : 'audio';
      await _signalingService!.initiateCall(widget.peerId, callType);

      if (_timer != null) {
        _timer!.cancel();
      }
      _timer = Timer.periodic(
        Duration(seconds: 3),
        (Timer t) => _signalingService!.initiateCall(widget.peerId, callType),
      );
      _logger.i('Outgoing call initiated to ${widget.peerId}');
    } catch (e) {
      _logger.e('Error initiating outgoing call: $e');
      _showErrorAndExit('Failed to initiate call');
    }
  }

  void _handleCallInitiated(String callId) {
    _logger.i('Call initiated with ID: $callId');
    setState(() {
      _currentCallId = callId;
      _callState = CallState.ringing;
    });
  }

  void _handleIncomingCall(IncomingCallEvent event) {
    _logger.i('Received incoming call: ${event.callId}');
    // This should not happen on this page as it's already shown
    // but we update the state just in case
    setState(() {
      _currentCallId = event.callId;
    });

    _signalingService?.acceptCall(event.callId);
  }

  Future<void> _handleCallAccepted(CallAcceptedEvent event) async {
    _logger.i('Call accepted: ${event.callId}');

    if (event.callId != _currentCallId) {
      _logger.w('Received acceptance for different call ID');
      return;
    }

    setState(() {
      _callState = CallState.connecting;
    });

    // Create and send offer
    await _createAndSendOffer();
  }

  void _handleCallRejected(CallRejectedEvent event) {
    _logger.i('Call rejected: ${event.callId}, reason: ${event.reason}');

    if (event.callId != _currentCallId) {
      return;
    }

    _showErrorAndExit('Call was rejected');
  }

  void _handleCallEnded(CallEndedEvent event) {
    _logger.i('Call ended: ${event.callId}, reason: ${event.reason}');

    if (event.callId != _currentCallId) {
      return;
    }

    _endCall(showMessage: false);
  }

  Future<void> _handleOffer(SignalingOfferEvent event) async {
    _logger.i('Received offer from ${event.fromUserId}');

    try {
      final offer = RTCSessionDescription(event.sdp, 'offer');
      await _peerConnection!.setRemoteDescription(offer);

      // Create and send answer
      await _createAndSendAnswer();
    } catch (e) {
      _logger.e('Error handling offer: $e');
    }
  }

  Future<void> _handleAnswer(SignalingAnswerEvent event) async {
    _logger.i('Received answer from ${event.fromUserId}');

    try {
      final answer = RTCSessionDescription(event.sdp, 'answer');
      await _peerConnection!.setRemoteDescription(answer);

      setState(() {
        _callState = CallState.inProgress;
      });
    } catch (e) {
      _logger.e('Error handling answer: $e');
    }
  }

  Future<void> _handleIceCandidate(SignalingIceCandidateEvent event) async {
    _logger.d('Received ICE candidate from ${event.fromUserId}');

    try {
      final candidate = RTCIceCandidate(
        event.candidate,
        event.sdpMid ?? '',
        event.sdpMLineIndex ?? 0,
      );
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      _logger.e('Error adding ICE candidate: $e');
    }
  }

  Future<void> _createAndSendOffer() async {
    try {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      await _signalingService!.sendOffer(widget.peerId, offer.sdp!);

      _logger.i('Offer sent to ${widget.peerId}');
    } catch (e) {
      _logger.e('Error creating/sending offer: $e');
    }
  }

  Future<void> _createAndSendAnswer() async {
    try {
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await _signalingService!.sendAnswer(widget.peerId, answer.sdp!);

      setState(() {
        _callState = CallState.inProgress;
      });

      _logger.i('Answer sent to ${widget.peerId}');
    } catch (e) {
      _logger.e('Error creating/sending answer: $e');
    }
  }

  Future<void> _acceptCall() async {
    if (_currentCallId == null) {
      _logger.e('Cannot accept call: no call ID');
      return;
    }

    try {
      setState(() {
        _callState = CallState.connecting;
      });

      await _signalingService!.acceptCall(_currentCallId!);
      _logger.i('Call accepted');
    } catch (e) {
      _logger.e('Error accepting call: $e');
      _showErrorAndExit('Failed to accept call');
    }
  }

  Future<void> _rejectCall() async {
    if (_currentCallId == null) {
      _logger.e('Cannot reject call: no call ID');
      return;
    }

    try {
      await _signalingService!.rejectCall(_currentCallId!, 'User declined');
      _logger.i('Call rejected');
    } catch (e) {
      _logger.e('Error rejecting call: $e');
    } finally {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _toggleMic() {
    if (_localStream == null) return;

    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      final enabled = !audioTracks[0].enabled;
      audioTracks[0].enabled = enabled;

      setState(() {
        _isMuted = !enabled;
      });

      _logger.i('Microphone ${enabled ? 'unmuted' : 'muted'}');
    }
  }

  Future<void> _switchCamera() async {
    if (_localStream == null || widget.callType != CallType.video) return;

    try {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks[0]);
        _logger.i('Camera switched');
      }
    } catch (e) {
      _logger.e('Error switching camera: $e');
    }
  }

  void _toggleCamera() {
    if (_localStream == null || widget.callType != CallType.video) return;

    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      final enabled = !videoTracks[0].enabled;
      videoTracks[0].enabled = enabled;

      setState(() {
        _isCameraOff = !enabled;
      });

      _logger.i('Camera ${enabled ? 'on' : 'off'}');
    }
  }

  void _handleConnectionLost() {
    _logger.w('Connection lost');
    if (mounted) {
      _showErrorAndExit('Connection lost');
    }
  }

  Future<void> _endCall({bool showMessage = true}) async {
    try {
      if (_currentCallId != null && _signalingService != null) {
        await _signalingService!.endCall(_currentCallId!, 'User ended call');
      }
    } catch (e) {
      _logger.e('Error ending call: $e');
    } finally {
      setState(() {
        _callState = CallState.ended;
      });

      if (mounted) {
        if (showMessage) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Call ended')));
        }
        Navigator.pop(context);
      }
    }
  }

  void _showErrorAndExit(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _logger.i('Disposing call page');

    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }

    // Clean up media streams
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    _localStream?.dispose();

    // Clean up renderers
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    // Close peer connection
    _peerConnection?.close();

    // Disconnect signaling
    _signalingService?.dispose();

    _timer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video (full screen)
          Positioned.fill(
            child: _callState == CallState.inProgress
                ? RTCVideoView(
                    _remoteRenderer,
                    mirror: false,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Container(
                    color: Colors.grey[900],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey[700],
                            child: Text(
                              widget.peerName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            widget.peerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _getStatusText(),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                          if (_callState == CallState.connecting ||
                              _callState == CallState.ringing)
                            const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Local video preview (for video calls)
          if (widget.callType == CallType.video &&
              _callState == CallState.inProgress &&
              !_isCameraOff)
            Positioned(
              right: 16,
              top: 60,
              width: 120,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

          // Call controls
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: _buildCallControls(),
          ),

          // Status bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.callType == CallType.video
                          ? 'Video Call'
                          : 'Voice Call',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    if (_callState == CallState.inProgress)
                      const Icon(Icons.circle, color: Colors.green, size: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText() {
    switch (_callState) {
      case CallState.connecting:
        return 'Connecting...';
      case CallState.ringing:
        return widget.isOutgoing ? 'Ringing...' : 'Incoming call';
      case CallState.inProgress:
        return 'Connected';
      case CallState.ended:
        return 'Call ended';
    }
  }

  Widget _buildCallControls() {
    // For incoming calls in ringing state, show accept/reject buttons
    if (!widget.isOutgoing && _callState == CallState.ringing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: Icons.call_end,
            color: Colors.red,
            label: 'Decline',
            onPressed: _rejectCall,
          ),
          _buildControlButton(
            icon: Icons.call,
            color: Colors.green,
            label: 'Accept',
            onPressed: _acceptCall,
          ),
        ],
      );
    }

    // For active calls, show regular controls
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Mute button
        _buildControlButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          color: _isMuted ? Colors.red : Colors.white,
          onPressed: _toggleMic,
        ),
        const SizedBox(width: 20),

        // End call button
        _buildControlButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: () => _endCall(),
          size: 70,
        ),
        const SizedBox(width: 20),

        // Video controls (only for video calls)
        if (widget.callType == CallType.video) ...[
          _buildControlButton(
            icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
            color: _isCameraOff ? Colors.red : Colors.white,
            onPressed: _toggleCamera,
          ),
          const SizedBox(width: 20),
          _buildControlButton(
            icon: Icons.switch_camera,
            color: Colors.white,
            onPressed: _switchCamera,
          ),
        ],
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? label,
    double size = 56,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withOpacity(0.9),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: color == Colors.white ? Colors.black : Colors.white,
                size: size * 0.5,
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ],
    );
  }
}
