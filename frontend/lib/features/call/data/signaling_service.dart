import 'dart:async';
import 'package:logger/logger.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:signalr_netcore/http_connection_options.dart';

/// SignalR-based signaling service for WebRTC call signaling.
/// For authenticated users it reuses WebSocketManager's existing connection.
/// For guests it creates its own dedicated connection.
class SignalingService {
  HubConnection? _hubConnection;
  bool _ownsConnection = false;
  final Logger _logger = Logger(output: ConsoleOutput());
  void Function()? _connectionRestoredCb;

  // Stream controllers for different signaling events
  final StreamController<IncomingCallEvent> _incomingCallController =
      StreamController<IncomingCallEvent>.broadcast(); // OBSOLETE
  final StreamController<CallAcceptedEvent> _callAcceptedController =
      StreamController<CallAcceptedEvent>.broadcast(); // OBSOLETE
  final StreamController<CallRejectedEvent> _callRejectedController =
      StreamController<CallRejectedEvent>.broadcast(); // OBSOLETE
  final StreamController<CallEndedEvent> _callEndedController =
      StreamController<CallEndedEvent>.broadcast(); // OBSOLETE

  final StreamController<RoomCreatedEvent> _roomCreatedController =
      StreamController<RoomCreatedEvent>.broadcast();
  final StreamController<RoomJoinedEvent> _roomJoinedController =
      StreamController<RoomJoinedEvent>.broadcast();
  final StreamController<RoomParticipantUpdate> _participantJoinedController =
      StreamController<RoomParticipantUpdate>.broadcast();
  final StreamController<RoomParticipantUpdate> _participantLeftController =
      StreamController<RoomParticipantUpdate>.broadcast();

  final StreamController<SignalingOfferEvent> _offerController =
      StreamController<SignalingOfferEvent>.broadcast();
  final StreamController<SignalingAnswerEvent> _answerController =
      StreamController<SignalingAnswerEvent>.broadcast();
  final StreamController<SignalingIceCandidateEvent> _iceCandidateController =
      StreamController<SignalingIceCandidateEvent>.broadcast();
  final StreamController<String> _callInitiatedController =
      StreamController<String>.broadcast();

  SignalingService();

  // Public streams
  Stream<IncomingCallEvent> get onIncomingCall =>
      _incomingCallController.stream; // OBSOLETE
  Stream<CallAcceptedEvent> get onCallAccepted =>
      _callAcceptedController.stream; // OBSOLETE
  Stream<CallRejectedEvent> get onCallRejected =>
      _callRejectedController.stream; // OBSOLETE
  Stream<CallEndedEvent> get onCallEnded =>
      _callEndedController.stream; // OBSOLETE

  Stream<RoomCreatedEvent> get onRoomCreated => _roomCreatedController.stream;
  Stream<RoomJoinedEvent> get onRoomJoined => _roomJoinedController.stream;
  Stream<RoomParticipantUpdate> get onParticipantJoined =>
      _participantJoinedController.stream;
  Stream<RoomParticipantUpdate> get onParticipantLeft =>
      _participantLeftController.stream;
  Stream<SignalingOfferEvent> get onOffer => _offerController.stream;
  Stream<SignalingAnswerEvent> get onAnswer => _answerController.stream;
  Stream<SignalingIceCandidateEvent> get onIceCandidate =>
      _iceCandidateController.stream;
  Stream<String> get onCallInitiated => _callInitiatedController.stream;

  bool get isConnected =>
      _hubConnection?.state == HubConnectionState.Connected;

  /// Attach to WebSocketManager's existing hub connection for signaling.
  /// No new WebSocket is opened — all signaling goes through the shared connection.
  Future<void> connect() async {
    if (isConnected) {
      _logger.w('Already connected to SignalR hub');
      return;
    }

    final shared = WebSocketManager().hubConnection;
    if (shared == null || shared.state != HubConnectionState.Connected) {
      _logger.e('WebSocketManager hub connection not available');
      throw Exception('WebSocketManager is not connected');
    }

    _hubConnection = shared;
    _ownsConnection = false;
    _registerHandlers();

    _connectionRestoredCb = _onSharedConnectionRestored;
    WebSocketManager().onConnectionRestored(_connectionRestoredCb!);

    _logger.i('Signaling service attached to shared hub connection');
  }

  /// Called when WebSocketManager restores its connection (force reconnect
  /// or full reinitialize). Re-grab the hub reference and re-register handlers
  /// so signaling keeps working after a stale-connection recovery.
  void _onSharedConnectionRestored() {
    final shared = WebSocketManager().hubConnection;
    if (shared == null) return;

    if (shared != _hubConnection) {
      _logger.i('Shared connection instance changed — re-attaching signaling handlers');
      _hubConnection = shared;
      _registerHandlers();
    } else {
      _logger.i('Shared connection restored (same instance)');
    }
  }

  /// Connect as a guest (no JWT, uses deviceId + guestName query params).
  /// Guests don't have a WebSocketManager connection, so this creates its own.
  Future<void> connectAsGuest(String deviceId, String displayName) async {
    if (isConnected) {
      // _logger.w('Already connected to SignalR hub');
      return;
    }

    try {
      final encodedName = Uri.encodeComponent(displayName);
      final connectionUrl =
          '${ApiConstants.getSignalingUrlWithNoToken()}?deviceId=$deviceId&guestName=$encodedName';
      _logger.i('Connecting to SignalR hub as guest: $connectionUrl');

      _hubConnection = HubConnectionBuilder()
          .withUrl(
            connectionUrl,
            options: HttpConnectionOptions(),
          )
          .withAutomaticReconnect()
          .build();

      _ownsConnection = true;
      _registerHandlers();
      await _hubConnection!.start();
      // _logger.i('Successfully connected to SignalR hub as guest');
    } catch (e) {
      _logger.e('Failed to connect to SignalR hub as guest: $e');
      rethrow;
    }
  }

  void _registerHandlers() {
    if (_hubConnection == null) return;

    _hubConnection!.on('RoomCreated', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        _roomCreatedController.add(RoomCreatedEvent.fromJson(data));
      }
    });

    _hubConnection!.on('RoomJoined', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        _roomJoinedController.add(RoomJoinedEvent.fromJson(data));
      }
    });

    _hubConnection!.on('ParticipantJoined', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        _participantJoinedController.add(RoomParticipantUpdate.fromJson(data));
      }
    });

    _hubConnection!.on('ParticipantLeft', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        _participantLeftController.add(RoomParticipantUpdate.fromJson(data));
      }
    });

    _hubConnection!.on('ReceiveOffer', (arguments) {
      // _logger.d('Received ReceiveOffer: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = SignalingOfferEvent.fromJson(data);
        _offerController.add(event);
      }
    });

    _hubConnection!.on('ReceiveAnswer', (arguments) {
      // _logger.d('Received ReceiveAnswer: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = SignalingAnswerEvent.fromJson(data);
        _answerController.add(event);
      }
    });

    _hubConnection!.on('ReceiveIceCandidate', (arguments) {
      _logger.d('Received ReceiveIceCandidate: $arguments');
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final event = SignalingIceCandidateEvent.fromJson(data);
        _iceCandidateController.add(event);
      }
    });

    _hubConnection!.on('CallFailed', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        final data = arguments[0] as Map<String, dynamic>;
        final reason = data['reason'] as String?;
        _logger.e('Call failed (but pending) reason: $reason');
      } else {
        _logger.e('Call failed (but pending): $arguments');
      }
    });

    _hubConnection!.on('Error', (arguments) {
      _logger.e('SignalR error: $arguments');
    });
  }

  Future<void> initiateCall(String calleeId, String callType) async {
    if (!isConnected) throw Exception('Not connected to SignalR hub');
    _logger.i('Initiating $callType call to $calleeId');
    await _hubConnection!.invoke('InitiateCall', args: [calleeId, callType]);
  }

  Future<void> acceptCall(String callId) async {
    if (!isConnected) throw Exception('Not connected to SignalR hub');
    _logger.i('Accepting call $callId');
    await _hubConnection!.invoke('AcceptCall', args: [callId]);
  }

  Future<void> rejectCall(String callId, String reason) async {
    if (!isConnected) throw Exception('Not connected to SignalR hub');
    _logger.i('Rejecting call $callId: $reason');
    await _hubConnection!.invoke('RejectCall', args: [callId, reason]);
  }

  Future<void> endCall(String callId, String reason) async {
    if (!isConnected) throw Exception('Not connected to SignalR hub');
    _logger.i('Ending call $callId: $reason');
    await _hubConnection!.invoke('EndCall', args: [callId, reason]);
  }

  /// Send WebRTC offer to a specific device
  Future<void> sendOffer(String toDeviceId, String sdp,
      {String? roomId}) async {
    if (!isConnected) throw Exception('Not connected to SignalR hub');
    _logger.d('Sending offer to $toDeviceId');
    await _hubConnection!.invoke(
      'SendOffer',
      args: [toDeviceId, sdp, roomId as Object],
    );
  }

  /// Send WebRTC answer to a specific device
  Future<void> sendAnswer(String toDeviceId, String sdp,
      {String? roomId}) async {
    if (!isConnected) throw Exception('Not connected to SignalR hub');
    // _logger.d('Sending answer to $toDeviceId');
    await _hubConnection!.invoke(
      'SendAnswer',
      args: [toDeviceId, sdp, roomId as Object],
    );
  }

  Future<void> createRoom(String conversationId) async {
    if (!isConnected) throw Exception('Not connected');
    await _hubConnection!.invoke('CreateRoom', args: [conversationId]);
  }

  Future<void> joinRoom(String roomId) async {
    if (!isConnected) throw Exception('Not connected');
    await _hubConnection!.invoke('JoinRoom', args: [roomId]);
  }

  /// Join a room as guest using the invite key (no auth required, room must already exist)
  Future<void> joinRoomAsGuest(String inviteKey, String displayName) async {
    if (!isConnected) throw Exception('Not connected');
    await _hubConnection!
        .invoke('JoinRoomAsGuest', args: [inviteKey, displayName]);
  }

  Future<void> leaveRoom(String roomId, {String reason = 'user_left'}) async {
    if (!isConnected) throw Exception('Not connected');
    await _hubConnection!.invoke('LeaveRoom', args: [roomId, reason]);
  }

  Future<void> sendRoomOffer(String roomId, String sdp) async {
    if (!isConnected) throw Exception('Not connected');
    await _hubConnection!.invoke('SendRoomOffer', args: [roomId, sdp]);
  }

  Future<void> sendRoomIceCandidate(
    String roomId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    if (!isConnected) throw Exception('Not connected');
    await _hubConnection!.invoke(
      'SendRoomIceCandidate',
      args: [roomId, candidate, sdpMid as Object, sdpMLineIndex as Object],
    );
  }

  /// Send ICE candidate to a specific device
  Future<void> sendIceCandidate(
    String toDeviceId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex, {
    String? roomId,
  }) async {
    if (!isConnected) throw Exception('Not connected to SignalR hub');
    _logger.d('Sending ICE candidate to $toDeviceId');
    await _hubConnection!.invoke(
      'SendIceCandidate',
      args: [
        toDeviceId,
        candidate,
        sdpMid as Object,
        sdpMLineIndex as Object,
        roomId as Object,
      ],
    );
  }

  Future<void> disconnect() async {
    try {
      if (_connectionRestoredCb != null) {
        WebSocketManager().removeConnectionRestoredCallback(_connectionRestoredCb!);
        _connectionRestoredCb = null;
      }

      if (_ownsConnection) {
        _logger.i('Stopping owned SignalR hub connection (guest)');
        await _hubConnection?.stop();
      } else {
        _logger.i('Detaching from shared SignalR hub connection');
      }
      _hubConnection = null;
      _ownsConnection = false;
    } catch (e) {
      _logger.e('Error disconnecting: $e');
    }
  }

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
  final String deviceId;
  final String reason;

  CallEndedEvent({
    required this.callId,
    required this.deviceId,
    required this.reason,
  });

  factory CallEndedEvent.fromJson(Map<String, dynamic> json) {
    return CallEndedEvent(
      callId: json['callId'] as String,
      deviceId: json['deviceId'] as String,
      reason: json['reason'] as String,
    );
  }
}

class SignalingOfferEvent {
  final String fromDeviceId;
  final String toDeviceId;
  final String? roomId;
  final String sdp;

  SignalingOfferEvent({
    required this.fromDeviceId,
    required this.toDeviceId,
    this.roomId,
    required this.sdp,
  });

  factory SignalingOfferEvent.fromJson(Map<String, dynamic> json) {
    return SignalingOfferEvent(
      fromDeviceId: json['fromDeviceId'] as String,
      toDeviceId: json['toDeviceId'] as String,
      roomId: json['roomId'] as String?,
      sdp: json['sdp'] as String,
    );
  }
}

class SignalingAnswerEvent {
  final String fromDeviceId;
  final String toDeviceId;
  final String? roomId;
  final String sdp;

  SignalingAnswerEvent({
    required this.fromDeviceId,
    required this.toDeviceId,
    this.roomId,
    required this.sdp,
  });

  factory SignalingAnswerEvent.fromJson(Map<String, dynamic> json) {
    return SignalingAnswerEvent(
      fromDeviceId: json['fromDeviceId'] as String,
      toDeviceId: json['toDeviceId'] as String,
      roomId: json['roomId'] as String?,
      sdp: json['sdp'] as String,
    );
  }
}

class SignalingIceCandidateEvent {
  final String fromDeviceId;
  final String toDeviceId;
  final String? roomId;
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  SignalingIceCandidateEvent({
    required this.fromDeviceId,
    required this.toDeviceId,
    this.roomId,
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  factory SignalingIceCandidateEvent.fromJson(Map<String, dynamic> json) {
    return SignalingIceCandidateEvent(
      fromDeviceId: json['fromDeviceId'] as String,
      toDeviceId: json['toDeviceId'] as String,
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

class RoomCreatedEvent {
  final String roomId;
  final String conversationId;
  final List<UserInfo> participants;
  final String createdBy;
  final DateTime createdAt;
  final String? inviteKey;

  RoomCreatedEvent({
    required this.roomId,
    required this.conversationId,
    required this.participants,
    required this.createdBy,
    required this.createdAt,
    this.inviteKey,
  });

  factory RoomCreatedEvent.fromJson(Map<String, dynamic> json) {
    final participantsJson = json['participants'] as List<dynamic>;
    final participants = participantsJson
        .map((p) => UserInfo.fromJson(p as Map<String, dynamic>))
        .toList();

    return RoomCreatedEvent(
      roomId: json['roomId'] as String,
      conversationId: json['name'] as String,
      participants: participants,
      createdBy: json['createdBy'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      inviteKey: json['inviteKey'] as String?,
    );
  }
}

class RoomJoinedEvent {
  final String roomId;
  final String conversationId;
  final List<UserInfo> participants;
  final String createdBy;
  final DateTime createdAt;
  final String? inviteKey;

  RoomJoinedEvent({
    required this.roomId,
    required this.conversationId,
    required this.participants,
    required this.createdBy,
    required this.createdAt,
    this.inviteKey,
  });

  factory RoomJoinedEvent.fromJson(Map<String, dynamic> json) {
    final participantsJson = json['participants'] as List<dynamic>;
    final participants = participantsJson
        .map((p) => UserInfo.fromJson(p as Map<String, dynamic>))
        .toList();

    return RoomJoinedEvent(
      roomId: json['roomId'] as String,
      conversationId: json['name'] as String,
      participants: participants,
      createdBy: json['createdBy'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      inviteKey: json['inviteKey'] as String?,
    );
  }
}

class RoomParticipantUpdate {
  final String roomId;
  final UserInfo user;
  final String action; // 'joined' or 'left'

  RoomParticipantUpdate({
    required this.roomId,
    required this.user,
    required this.action,
  });

  factory RoomParticipantUpdate.fromJson(Map<String, dynamic> json) {
    return RoomParticipantUpdate(
      roomId: json['roomId'] as String,
      user: UserInfo.fromJson(json['user'] as Map<String, dynamic>),
      action: json['action'] as String,
    );
  }
}
