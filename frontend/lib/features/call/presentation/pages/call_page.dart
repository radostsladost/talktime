import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

enum CallType { audio, video }

class CallPage extends StatefulWidget {
  final bool isOutgoing;
  final String peerName;
  final CallType callType;

  const CallPage({
    super.key,
    required this.isOutgoing,
    required this.peerName,
    this.callType = CallType.video,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late RTCPeerConnection? _peerConnection = null;
  late RTCVideoRenderer? _localStream = null;
  late RTCVideoRenderer? _remoteStream = null;

  final WebRTC webRTC = WebRTC();

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    // Request permissions
    await [
      Permission.microphone,
      if (widget.callType == CallType.video) Permission.camera,
    ].request();

    // Get local stream
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
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

    final localStream = await navigator.mediaDevices.getUserMedia(
      mediaConstraints,
    );
    if (localStream != null && localStream.active!) {
      _localStream = RTCVideoRenderer();
      _localStream!.srcObject = localStream;
    }

    // Create peer connection (you'll connect to signaling later)
    final config = {
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'},
        // Add your TURN server in production!
        // {
        //   'url': 'turn:your-turn-server.com:3478',
        //   'username': 'user',
        //   'credential': 'pass',
        // }
      ],
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onTrack = (event) {
      setState(() {
        final remoteStream = event.streams[0];
        if (remoteStream != null && localStream.active!) {
          _remoteStream = RTCVideoRenderer();
          _remoteStream!.srcObject = remoteStream;
        }
      });
    };

    localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, localStream!);
    });

    // TODO: Send offer via signaling (WebSocket to .NET backend)
  }

  @override
  void dispose() {
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.close();
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
            child: _remoteStream != null
                ? RTCVideoView(
                    RTCVideoRenderer(),
                    mirror: false,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Container(color: Colors.grey[900]),
          ),

          // Local preview (small window)
          if (_localStream != null)
            Positioned(
              right: 16,
              top: 80,
              width: 120,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  _localStream!,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

          // Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCircleButton(
                  Icons.call_end,
                  Colors.red,
                  () => Navigator.pop(context),
                ),
                if (widget.callType == CallType.video)
                  _buildCircleButton(
                    Icons.switch_camera,
                    Colors.white,
                    _switchCamera,
                  ),
                _buildCircleButton(Icons.mic, Colors.white, _toggleMic),
              ],
            ),
          ),

          // Caller info
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Text(
              widget.isOutgoing
                  ? 'Calling ${widget.peerName}...'
                  : '${widget.peerName} is calling',
              style: const TextStyle(color: Colors.white, fontSize: 20),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton(
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FloatingActionButton(
        backgroundColor: color,
        child: Icon(icon, color: Colors.black),
        onPressed: onPressed,
        mini: true,
      ),
    );
  }

  void _toggleMic() {
    // TODO: Mute/unmute audio track + apply noise cancellation
  }

  void _switchCamera() {
    // TODO: Switch camera (mobile only)
  }
}
