import 'dart:async';
import 'package:logger/logger.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:talktime/core/constants/api_constants.dart';

/// SignalR-based signaling service for WebRTC call signaling
/// Handles connection to the TalkTime SignalR hub and manages call signaling
class SignalingService {
  HubConnection? _hubConnection;
  final String _accessToken;
  final Logger _logger = Logger();

  // Stream controllers for different signaling events
  final StreamController<IncomingCallEvent> _incomingCallController =
      StreamController<IncomingCallEvent>.broadcast();
  final StreamController<CallAcceptedEvent> _callAcceptedController =
      StreamController<CallAcceptedEvent>.broadcast();
  final StreamController<CallRejectedEvent> _callRejectedController =
      StreamController<CallRejectedEvent>.broadcast();
  final StreamController<CallEndedEvent> _callEndedController =
      StreamController<CallEndedEvent>.broadcast();
  final StreamController<SignalingOfferEvent> _offerController =
      StreamController<SignalingOfferEvent>.broadcast();
  final StreamController<SignalingAnswerEvent> _answerController =
      StreamController<SignalingAnswerEvent>.broadcast();
  final StreamController<SignalingIceCandidateEvent> _iceCandidateController =
      StreamController<SignalingIceCandidateEvent>.broadcast();
  final StreamController<String> _callInitiatedController =
      StreamController<String>.broadcast();

  SignalingService(this._accessToken);

  // Public streams
  Stream<IncomingCallEvent> get onIncomingCall =>
      _incomingCallController.stream;
  Stream<CallAcceptedEvent> get onCallAccepted =>
      _callAcceptedController.stream;
  Stream<CallRejectedEvent> get onCallRejected =>
      _callRejectedController.stream;
  Stream<CallEndedEvent> get onCallEnded => _callEndedController.stream;
  Stream<SignalingOfferEvent> get onOffer => _offerController.stream;
  Stream<SignalingAnswerEvent> get onAnswer => _answerController.stream;
  Stream<SignalingIceCandidateEvent> get onIceCandidate =>
      _iceCandidateController.stream;
  Stream<String> get onCallInitiated => _callInitiatedController.stream;

  /// Check if connected to SignalR hub
  bool get isConnected => _hubConnection?.state == HubConnectionState.Connected;

  /// Connect to the SignalR hub
  Future<void> connect() async {
    if (isConnected) {
      _logger.w('Already connected to SignalR hub');
      return;
    }

    try {
      final url = ApiConstants.getSignalingUrl(_accessToken);
      _logger.i('Connecting to SignalR hub: $url');

      _hubConnection = HubConnectionBuilder()
          .withUrl(url)
          .withAutomaticReconnect()
          .build();

      // Register event handlers
      _registerHandlers();

      // Start connection
      await _hubConnection!.start();
      _logger.i('Successfully connected to SignalR hub');
    } catch (e) {
      _logger.e('Failed to connect to SignalR hub: $e');
      rethrow;
    }
  }

  /// Register SignalR event handlers
  void _registerHandlers() {
    if (_hubConnection == null) return;

    // Incoming call
    _hubConnection!.on('IncomingCall', (arguments) {
      _logger.d('Received IncomingCall: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = IncomingCallEvent.fromJson(data);
        _incomingCallController.add(event);
      }
    });

    // Call initiated (for outgoing calls)
    _hubConnection!.on('CallInitiated', (arguments) {
      _logger.d('Received CallInitiated: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final callId = data['callId'] as String;
        _callInitiatedController.add(callId);
      }
    });

    // Call accepted
    _hubConnection!.on('CallAccepted', (arguments) {
      _logger.d('Received CallAccepted: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = CallAcceptedEvent.fromJson(data);
        _callAcceptedController.add(event);
      }
    });

    // Call rejected
    _hubConnection!.on('CallRejected', (arguments) {
      _logger.d('Received CallRejected: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = CallRejectedEvent.fromJson(data);
        _callRejectedController.add(event);
      }
    });

    // Call ended
    _hubConnection!.on('CallEnded', (arguments) {
      _logger.d('Received CallEnded: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = CallEndedEvent.fromJson(data);
        _callEndedController.add(event);
      }
    });

    // WebRTC offer
    _hubConnection!.on('ReceiveOffer', (arguments) {
      _logger.d('Received ReceiveOffer: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = SignalingOfferEvent.fromJson(data);
        _offerController.add(event);
      }
    });

    // WebRTC answer
    _hubConnection!.on('ReceiveAnswer', (arguments) {
      _logger.d('Received ReceiveAnswer: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = SignalingAnswerEvent.fromJson(data);
        _answerController.add(event);
      }
    });

    // ICE candidate
    _hubConnection!.on('ReceiveIceCandidate', (arguments) {
      _logger.d('Received ReceiveIceCandidate: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = SignalingIceCandidateEvent.fromJson(data);
        _iceCandidateController.add(event);
      }
    });

    // Call failed
    _hubConnection!.on('CallFailed', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final reason = data['reason'] as String?;
        _logger.e('Call failed (but pending) reason: $reason');
      } else {
        _logger.e('Call failed (but pending): $arguments');
      }
    });

    // Error
    _hubConnection!.on('Error', (arguments) {
      _logger.e('SignalR error: $arguments');
    });
  }

  /// Initiate a call to another user
  Future<void> initiateCall(String calleeId, String callType) async {
    if (!isConnected) {
      throw Exception('Not connected to SignalR hub');
    }

    _logger.i('Initiating $callType call to $calleeId');
    await _hubConnection!.invoke('InitiateCall', args: [calleeId, callType]);
  }

  /// Accept an incoming call
  Future<void> acceptCall(String callId) async {
    if (!isConnected) {
      throw Exception('Not connected to SignalR hub');
    }

    _logger.i('Accepting call $callId');
    await _hubConnection!.invoke('AcceptCall', args: [callId]);
  }

  /// Reject an incoming call
  Future<void> rejectCall(String callId, String reason) async {
    if (!isConnected) {
      throw Exception('Not connected to SignalR hub');
    }

    _logger.i('Rejecting call $callId: $reason');
    await _hubConnection!.invoke('RejectCall', args: [callId, reason]);
  }

  /// End an active call
  Future<void> endCall(String callId, String reason) async {
    if (!isConnected) {
      throw Exception('Not connected to SignalR hub');
    }

    _logger.i('Ending call $callId: $reason');
    await _hubConnection!.invoke('EndCall', args: [callId, reason]);
  }

  /// Send WebRTC offer
  Future<void> sendOffer(String toUserId, String sdp, {String? roomId}) async {
    if (!isConnected) {
      throw Exception('Not connected to SignalR hub');
    }

    _logger.d('Sending offer to $toUserId');
    await _hubConnection!.invoke(
      'SendOffer',
      args: [toUserId, sdp, roomId as Object],
    );
  }

  /// Send WebRTC answer
  Future<void> sendAnswer(String toUserId, String sdp, {String? roomId}) async {
    if (!isConnected) {
      throw Exception('Not connected to SignalR hub');
    }

    _logger.d('Sending answer to $toUserId');
    await _hubConnection!.invoke(
      'SendAnswer',
      args: [toUserId, sdp, roomId as Object],
    );
  }

  /// Send ICE candidate
  Future<void> sendIceCandidate(
    String toUserId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex, {
    String? roomId,
  }) async {
    if (!isConnected) {
      throw Exception('Not connected to SignalR hub');
    }

    _logger.d('Sending ICE candidate to $toUserId');
    await _hubConnection!.invoke(
      'SendIceCandidate',
      args: [
        toUserId,
        candidate,
        sdpMid as Object,
        sdpMLineIndex as Object,
        roomId as Object,
      ],
    );
  }

  /// Disconnect from SignalR hub
  Future<void> disconnect() async {
    try {
      _logger.i('Disconnecting from SignalR hub');
      await _hubConnection?.stop();
      _hubConnection = null;
    } catch (e) {
      _logger.e('Error disconnecting: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _incomingCallController.close();
    _callAcceptedController.close();
    _callRejectedController.close();
    _callEndedController.close();
    _offerController.close();
    _answerController.close();
    _iceCandidateController.close();
    _callInitiatedController.close();
  }
}

// ==================== Event Models ====================

class IncomingCallEvent {
  final String callId;
  final UserInfo caller;
  final String callType;
  final String? roomId;

  IncomingCallEvent({
    required this.callId,
    required this.caller,
    required this.callType,
    this.roomId,
  });

  factory IncomingCallEvent.fromJson(Map<String, dynamic> json) {
    return IncomingCallEvent(
      callId: json['callId'] as String,
      caller: UserInfo.fromJson(json['caller'] as Map<String, dynamic>),
      callType: json['callType'] as String,
      roomId: json['roomId'] as String?,
    );
  }
}

class CallAcceptedEvent {
  final String callId;
  final String responderId;
  final bool accepted;

  CallAcceptedEvent({
    required this.callId,
    required this.responderId,
    required this.accepted,
  });

  factory CallAcceptedEvent.fromJson(Map<String, dynamic> json) {
    return CallAcceptedEvent(
      callId: json['callId'] as String,
      responderId: json['responderId'] as String,
      accepted: json['accepted'] as bool? ?? true,
    );
  }
}

class CallRejectedEvent {
  final String callId;
  final String responderId;
  final String? reason;

  CallRejectedEvent({
    required this.callId,
    required this.responderId,
    this.reason,
  });

  factory CallRejectedEvent.fromJson(Map<String, dynamic> json) {
    return CallRejectedEvent(
      callId: json['callId'] as String,
      responderId: json['responderId'] as String,
      reason: json['reason'] as String?,
    );
  }
}

class CallEndedEvent {
  final String callId;
  final String userId;
  final String reason;

  CallEndedEvent({
    required this.callId,
    required this.userId,
    required this.reason,
  });

  factory CallEndedEvent.fromJson(Map<String, dynamic> json) {
    return CallEndedEvent(
      callId: json['callId'] as String,
      userId: json['userId'] as String,
      reason: json['reason'] as String,
    );
  }
}

class SignalingOfferEvent {
  final String fromUserId;
  final String toUserId;
  final String? roomId;
  final String sdp;

  SignalingOfferEvent({
    required this.fromUserId,
    required this.toUserId,
    this.roomId,
    required this.sdp,
  });

  factory SignalingOfferEvent.fromJson(Map<String, dynamic> json) {
    return SignalingOfferEvent(
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      roomId: json['roomId'] as String?,
      sdp: json['sdp'] as String,
    );
  }
}

class SignalingAnswerEvent {
  final String fromUserId;
  final String toUserId;
  final String? roomId;
  final String sdp;

  SignalingAnswerEvent({
    required this.fromUserId,
    required this.toUserId,
    this.roomId,
    required this.sdp,
  });

  factory SignalingAnswerEvent.fromJson(Map<String, dynamic> json) {
    return SignalingAnswerEvent(
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      roomId: json['roomId'] as String?,
      sdp: json['sdp'] as String,
    );
  }
}

class SignalingIceCandidateEvent {
  final String fromUserId;
  final String toUserId;
  final String? roomId;
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  SignalingIceCandidateEvent({
    required this.fromUserId,
    required this.toUserId,
    this.roomId,
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  factory SignalingIceCandidateEvent.fromJson(Map<String, dynamic> json) {
    return SignalingIceCandidateEvent(
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      roomId: json['roomId'] as String?,
      candidate: json['candidate'] as String,
      sdpMid: json['sdpMid'] as String?,
      sdpMLineIndex: json['sdpMLineIndex'] as int?,
    );
  }
}

class UserInfo {
  final String id;
  final String username;
  final String? avatarUrl;

  UserInfo({required this.id, required this.username, this.avatarUrl});

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}
