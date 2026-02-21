import 'dart:async';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signalr_netcore/default_reconnect_policy.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/call/data/incoming_call_manager.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:signalr_netcore/http_connection_options.dart';
import 'dart:math';

/// WebSocket manager for real-time messaging using SignalR
class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  factory WebSocketManager() => _instance;
  WebSocketManager._internal();

  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _healthCheckInterval = Duration(seconds: 30);

  /// If the periodic timer hasn't updated _lastActiveAt in this window,
  /// the connection is considered stale after app resume.
  static const Duration _staleThreshold = Duration(seconds: 45);

  /// If we were away longer than this, force-reconnect even if SignalR
  /// still reports Connected (the underlying transport is likely dead).
  static const Duration _forceReconnectThreshold = Duration(minutes: 2);

  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  final Logger _logger = Logger(output: ConsoleOutput());
  final ApiClient _apiClient = ApiClient();
  HubConnection? _hubConnection;
  Timer? _healthCheckTimer;
  DateTime _lastActiveAt = DateTime.now();
  final List<void Function()> _onConnectionRestoredCallbacks = [];

  // Callbacks for different events
  final List<Function(Message)> _onMessageReceivedCallbacks = [];
  final List<Function(String)> _onUserOnlineCallbacks = [];
  final List<Function(String)> _onUserOfflineCallbacks = [];
  final List<Function(String, bool)> _onTypingIndicatorCallbacks = [];
  final List<Function(String, ConferenceParticipant, String)>
  _onConferenceParticipantCallbacks = [];
  final List<Function(String, String, ReactionUpdate)> _onReactionCallbacks =
      [];
  final List<Function(DeviceConnectedEvent)> _onDeviceConnectedCallbacks = [];
  final List<Function(DeviceSyncRequest)> _onDeviceSyncRequestCallbacks = [];
  final List<Function(DeviceSyncChunk)> _onDeviceSyncDataCallbacks = [];
  final List<Function(OtherDevicesAvailableEvent)>
  _onOtherDevicesAvailableCallbacks = [];
  final List<String> _cachedConversations = [];
  final Map<String, bool> _onlineStates = {};
  final Map<String, List<ConferenceParticipant>> _conferenceParticipants = {};
  String? _deviceId;

  Map<String, bool> get onlineStates => _onlineStates;
  Map<String, List<ConferenceParticipant>> get conferenceParticipants =>
      _conferenceParticipants;

  /// Get participants in a specific room/conversation conference
  List<ConferenceParticipant> getConferenceParticipants(String roomId) {
    return _conferenceParticipants[roomId] ?? [];
  }

  static const String _deviceIdKey = 'talktime_device_id';

  /// Get or generate a unique device ID for this device
  /// The device ID is persisted so it remains the same across app restarts
  Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    try {
      // Try to get stored device ID
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString(_deviceIdKey);

      if (storedId != null && storedId.isNotEmpty) {
        _deviceId = storedId;
        _logger.i('Using stored device ID: $_deviceId');
        return _deviceId!;
      }

      // Generate a new unique device ID
      final random = Random.secure();
      final randomPart = List.generate(
        8,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_$randomPart';

      // Persist the device ID
      await prefs.setString(_deviceIdKey, _deviceId!);
      _logger.i('Generated and stored new device ID: $_deviceId');

      return _deviceId!;
    } catch (e) {
      // Fallback if SharedPreferences fails
      _deviceId =
          'device_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
      _logger.w('Failed to persist device ID, using temporary: $_deviceId');
      return _deviceId!;
    }
  }

  /// Get the current device ID
  String? get deviceId => _deviceId;

  /// Expose the underlying hub connection so SignalingService can reuse it
  /// instead of opening a second WebSocket to the same hub.
  HubConnection? get hubConnection => _hubConnection;

  /// Get or create device ID (public for guest flow)
  Future<String> getOrCreateDeviceId() => _getOrCreateDeviceId();

  /// Initialize WebSocket connection with SignalR
  Future<void> initialize() async {
    _logger.i('Initializing WebSocket manager');

    try {
      final deviceId = await _getOrCreateDeviceId();
      final connectionUrl =
          '${ApiConstants.getSignalingUrlWithNoToken()}?deviceId=$deviceId';

      _logger.i('SignalR connection URL: $connectionUrl (deviceId: $deviceId)');

      if (_hubConnection?.state == HubConnectionState.Connected) {
        _logger.i('SignalR already up');
        _startHealthCheckTimer();
        return;
      }

      if (_hubConnection != null &&
          (_hubConnection!.state != HubConnectionState.Connected)) {
        try {
          _hubConnection!.stop();
        } catch (_) {}
      }

      _hubConnection = HubConnectionBuilder()
          .withUrl(
            connectionUrl,
            options: HttpConnectionOptions(
              accessTokenFactory: () async {
                await AuthService().refreshTokenIfNeeded();
                return (await _apiClient.getToken()) ?? "";
              },
            ),
          )
          .withAutomaticReconnect(
            retryDelays: [
              100,
              100,
              100,
              500,
              500,
              500,
              500,
              500,
              500,
              500,
              1500,
              1500,
              2500,
              2500,
              3000,
              5000,
              10000,
              20000,
            ],
          )
          .build();

      _hubConnection?.onclose(({Exception? error}) {
        _logger.e('SignalR connection closed callback: $error');
        _isConnected = false;
        _isConnecting = true;
        _lastActiveAt = DateTime.now();
      });

      _setupConnectionHandlers();
      await _connect();

      _logger.i('SignalR connection established');
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _lastActiveAt = DateTime.now();

      _startHealthCheckTimer();
      _setupMessageHandlers();
      _notifyConnectionRestored();
    } catch (e) {
      _logger.e('Failed to initialize WebSocket: $e');
    }
  }

  void _startHealthCheckTimer() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) async {
      _lastActiveAt = DateTime.now();
      if (await _apiClient.getToken() != null &&
          await _apiClient.isAccessTokenExpired() == false) {
        await _checkConnectionHealth().catchError((error) {
          _logger.e('Health check failed: $error');
        });
      }
    });
  }

  Future<void> _checkConnectionHealth() async {
    if (_hubConnection == null) {
      await initialize();
      return;
    }

    if (_hubConnection!.state == HubConnectionState.Disconnected) {
      _logger.i('Periodic health check: connection disconnected, reconnecting');
      _reconnectAttempts = 0;
      await _connect();
    }
  }

  /// Aggressive connection check intended for app-resume / tab-visible events.
  /// Detects stale connections that still report Connected and force-reconnects.
  Future<void> ensureConnected() async {
    if (_hubConnection == null) {
      _logger.i('ensureConnected: no hub connection, initializing');
      await initialize();
      return;
    }

    final now = DateTime.now();
    final inactiveDuration = now.difference(_lastActiveAt);
    _lastActiveAt = now;

    // Short inactivity — simple state check is enough
    if (inactiveDuration < _staleThreshold) {
      if (_hubConnection!.state == HubConnectionState.Disconnected) {
        _logger.i(
          'ensureConnected: disconnected after short inactivity, reconnecting',
        );
        _reconnectAttempts = 0;
        await _connect();
      }
      return;
    }

    _logger.i(
      'ensureConnected: resuming after ${inactiveDuration.inSeconds}s inactivity',
    );

    // Give SignalR ~1s to detect the dead socket before we check state
    await Future.delayed(const Duration(seconds: 1));

    final state = _hubConnection!.state;

    if (state == HubConnectionState.Connected &&
        inactiveDuration < _forceReconnectThreshold) {
      _logger.i(
        'ensureConnected: still connected after moderate inactivity — OK',
      );
      return;
    }

    // Either disconnected/reconnecting, or connected after very long inactivity
    _logger.i(
      'ensureConnected: state=$state after ${inactiveDuration.inSeconds}s — force reconnecting',
    );
    await _forceReconnect();
  }

  /// Tear down and restart the existing hub connection.
  /// Falls back to a full [initialize] if the restart fails.
  Future<void> _forceReconnect() async {
    _isConnected = false;
    _isConnecting = false;
    _reconnectAttempts = 0;

    try {
      await _hubConnection?.stop();
    } catch (e) {
      _logger.w('Error stopping hub during force reconnect: $e');
    }

    try {
      await _hubConnection!.start();
      _isConnected = true;
      _isConnecting = false;
      _lastActiveAt = DateTime.now();
      _logger.i('Force reconnect successful (same instance)');
      _notifyConnectionRestored();
    } catch (e) {
      _logger.e('Force reconnect failed, doing full reinitialize: $e');
      _hubConnection = null;
      await initialize();
    }
  }

  void _notifyConnectionRestored() {
    for (final cb in List.of(_onConnectionRestoredCallbacks)) {
      try {
        cb();
      } catch (e) {
        _logger.e('Connection-restored callback error: $e');
      }
    }
  }

  /// Setup SignalR connection event handlers
  void _setupConnectionHandlers() {
    if (_hubConnection == null) return;

    _hubConnection!.onclose(({Exception? error}) {
      _logger.i('SignalR connection closed: $error');
      _isConnected = false;
      _isConnecting = false;

      if (_reconnectAttempts < _maxReconnectAttempts) {
        _reconnectAttempts++;
        _logger.i(
          'Reconnection attempt $_reconnectAttempts/$_maxReconnectAttempts',
        );
        Future.delayed(_reconnectDelay, _connect);
      } else {
        _logger.e('Max reconnection attempts reached');
      }
    });

    _hubConnection!.onreconnecting(({Exception? error}) {
      _logger.i('SignalR reconnecting: $error');
      _isConnected = false;
      _isConnecting = true;
    });

    _hubConnection!.onreconnected(({String? connectionId}) {
      _logger.i('SignalR reconnected (connectionId=$connectionId)');
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _lastActiveAt = DateTime.now();
      _notifyConnectionRestored();
    });
  }

  /// Setup SignalR message event handlers
  void _setupMessageHandlers() {
    if (_hubConnection == null) return;

    // Handle incoming messages
    _hubConnection!.on('ReceiveMessage', (data) {
      _logger.d('Received SignalR message: $data');
      try {
        _handleReceiveMessage(data);
      } catch (e) {
        _logger.e('Error processing SignalR message: $e');
      }
    });

    // Handle user online status
    _hubConnection!.on('UserOnline', (args) {
      final data = args?.first as Map<String, dynamic>?;
      // _logger.d('User online event: $data');

      if (data != null && data['userId'] != null) {
        final userId = data['userId'] as String;
        _onlineStates[userId] = true;
        for (var callback in _onUserOnlineCallbacks) {
          callback(userId);
        }
        // _logger.i('User online: $userId');
      }
    });

    // Handle user offline status
    _hubConnection!.on('UserOffline', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.d('User offline event: $data');
      if (data is Map<String, dynamic> && data['userId'] != null) {
        final userId = data['userId'] as String;
        _onlineStates[userId] = false;
        for (var callback in _onUserOfflineCallbacks) {
          callback(userId);
        }
        _logger.i('User offline: $userId');
      }
    });

    // Handle typing indicator
    _hubConnection!.on('TypingIndicator', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.d('Typing indicator event: $data');
      if (data is Map<String, dynamic> &&
          data['conversationId'] != null &&
          data['userId'] != null &&
          data['isTyping'] != null) {
        final conversationId = data['conversationId'] as String;
        final userId = data['userId'] as String;
        final isTyping = data['isTyping'] as bool;
        for (var callback in _onTypingIndicatorCallbacks) {
          callback(conversationId, isTyping);
        }
        _logger.i(
          'Typing indicator: $userId in $conversationId - ${isTyping ? "typing" : "stopped"}',
        );
      }
    });

    // Handle participant joined conference
    _hubConnection!.on('ParticipantJoined', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.d('Participant joined event: $data');
      if (data != null) {
        final roomId = data['roomId'] as String;
        final userData = data['user'] as Map<String, dynamic>;
        final participant = ConferenceParticipant.fromJson(userData);

        _conferenceParticipants.putIfAbsent(roomId, () => []);
        if (!_conferenceParticipants[roomId]!.any(
          (p) => p.id == participant.id,
        )) {
          _conferenceParticipants[roomId]!.add(participant);
        }

        for (var callback in _onConferenceParticipantCallbacks) {
          callback(roomId, participant, 'joined');
        }
        _logger.i(
          'Participant joined conference: ${participant.username} in room $roomId',
        );
      }
    });

    // Handle participant left conference
    _hubConnection!.on('ParticipantLeft', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.d('Participant left event: $data');
      if (data != null) {
        final roomId = data['roomId'] as String;
        final userData = data['user'] as Map<String, dynamic>;
        final participant = ConferenceParticipant.fromJson(userData);

        _conferenceParticipants[roomId]?.removeWhere(
          (p) => p.id == participant.id,
        );
        if (_conferenceParticipants[roomId]?.isEmpty ?? false) {
          _conferenceParticipants.remove(roomId);
        }

        for (var callback in _onConferenceParticipantCallbacks) {
          callback(roomId, participant, 'left');
        }
        _logger.i(
          'Participant left conference: ${participant.username} from room $roomId',
        );
      }
    });

    // Handle participant left conference
    _hubConnection!.on('CallInitiated', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.d('CallInitiated: $data');
      if (data != null) {
        final roomId = data['roomId'] as String;
        final userData = data['user'] as Map<String, dynamic>;
        final participant = ConferenceParticipant.fromJson(userData);

        onCallInitiated(roomId, participant);
      }
    });

    // Handle reaction added
    _hubConnection!.on('ReactionAdded', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.d('Reaction added event: $data');
      if (data != null) {
        final conversationId = data['conversationId'] as String;
        final messageId = data['messageId'] as String;
        final reactionData = data['reaction'] as Map<String, dynamic>;
        final reaction = ReactionUpdate.fromJson(reactionData);

        for (var callback in _onReactionCallbacks) {
          callback(conversationId, messageId, reaction);
        }
        _logger.i('Reaction added: ${reaction.emoji} to message $messageId');
      }
    });

    // Handle reaction removed
    _hubConnection!.on('ReactionRemoved', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.d('Reaction removed event: $data');
      if (data != null) {
        final conversationId = data['conversationId'] as String;
        final messageId = data['messageId'] as String;
        final emoji = data['emoji'] as String;
        final userId = data['userId'] as String;

        final reaction = ReactionUpdate(
          id: '',
          emoji: emoji,
          userId: userId,
          username: '',
          isRemoved: true,
        );

        for (var callback in _onReactionCallbacks) {
          callback(conversationId, messageId, reaction);
        }
        _logger.i('Reaction removed: $emoji from message $messageId');
      }
    });

    // Handle room participants response
    _hubConnection!.on('RoomParticipants', (args) {
      final data = args?.first as Map<String, dynamic>?;
      // _logger.d('Room participants event: $data');
      if (data != null) {
        final roomId = data['roomId'] as String;
        final participantsData = data['participants'] as List?;

        if (participantsData != null) {
          final participants = participantsData
              .map(
                (p) =>
                    ConferenceParticipant.fromJson(p as Map<String, dynamic>),
              )
              .toList();

          _conferenceParticipants[roomId] = participants;

          // Notify callbacks about each participant
          for (var participant in participants) {
            for (var callback in _onConferenceParticipantCallbacks) {
              callback(roomId, participant, 'existing');
            }
          }
          // _logger.i(
          //   'Received ${participants.length} participants for room $roomId',
          // );
        }
      }
    });

    // Handle device connected event (another device of same user connected)
    _hubConnection!.on('DeviceConnected', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.i('Device connected event: $data');
      if (data != null) {
        final event = DeviceConnectedEvent.fromJson(data);
        for (var callback in _onDeviceConnectedCallbacks) {
          callback(event);
        }
        _logger.i(
          'New device connected: ${event.deviceId}, total devices: ${event.totalDevices}',
        );
      }
    });

    // Handle device disconnected event
    _hubConnection!.on('DeviceDisconnected', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.i('Device disconnected event: $data');
    });

    // Handle device sync request (another device is requesting sync)
    _hubConnection!.on('DeviceSyncRequest', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.i('Device sync request: $data');
      if (data != null) {
        final request = DeviceSyncRequest.fromJson(data);
        for (var callback in _onDeviceSyncRequestCallbacks) {
          callback(request);
        }
        _logger.i('Sync request from device: ${request.requestingDeviceId}');
      }
    });

    // Handle device sync data (receiving messages from another device)
    _hubConnection!.on('DeviceSyncData', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.i(
        'Device sync data received: chunk ${data?['chunkIndex']}/${data?['totalChunks']}',
      );
      if (data != null) {
        final chunk = DeviceSyncChunk.fromJson(data);
        for (var callback in _onDeviceSyncDataCallbacks) {
          callback(chunk);
        }
        _logger.i(
          'Received sync chunk ${chunk.chunkIndex}/${chunk.totalChunks} with ${chunk.messages.length} messages',
        );
      }
    });

    // Handle connected devices response
    _hubConnection!.on('ConnectedDevices', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.i('Connected devices: $data');
    });

    // Handle notification that other devices are available for sync
    // This is sent to newly connected devices
    _hubConnection!.on('OtherDevicesAvailable', (args) {
      final data = args?.first as Map<String, dynamic>?;
      _logger.i('Other devices available for sync: $data');
      if (data != null) {
        final event = OtherDevicesAvailableEvent.fromJson(data);
        for (var callback in _onOtherDevicesAvailableCallbacks) {
          callback(event);
        }
        _logger.i(
          '${event.otherDeviceCount} other device(s) available for sync',
        );
      }
    });
  }

  /// Connect to SignalR hub
  Future<void> _connect() async {
    if (_isConnecting || _isConnected || _hubConnection == null) return;

    _isConnecting = true;
    _logger.i('Attempting to connect to SignalR hub');

    try {
      await _hubConnection!.start();
      _logger.i('SignalR connected successfully');

      if (_cachedConversations.isNotEmpty) {
        for (var conversationId in _cachedConversations) {
          await joinConversation(conversationId);
        }
      }
    } catch (e) {
      _isConnecting = false;
      _logger.e('SignalR connection failed: $e');

      // Attempt to reconnect
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _reconnectAttempts++;
        _logger.i(
          'Reconnection attempt $_reconnectAttempts of $_maxReconnectAttempts',
        );
        Future.delayed(_reconnectDelay, _connect);
      }
    }
  }

  /// Handle received message
  void _handleReceiveMessage(dynamic args) {
    try {
      final messageData = args?.first as Map<String, dynamic>?;

      // Parse the message data and notify listeners
      if (messageData is Map<String, dynamic>) {
        _logger.i('Received new message data: $messageData');

        // Create a simple message object for now
        // In a real implementation, you would parse this properly
        final message = Message.fromJson(messageData);

        for (var callback in _onMessageReceivedCallbacks) {
          callback(message);
        }
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error processing received message: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Check if WebSocket is connected
  bool get isConnected => _isConnected;

  /// Join a specific conversation group
  Future<void> joinConversation(String conversationId) async {
    if (!_isConnected || _hubConnection == null) return;

    _logger.i('Joining conversation: $conversationId');
    if (!_cachedConversations.contains(conversationId)) {
      _cachedConversations.add(conversationId);
    }

    try {
      await _hubConnection!.invoke('JoinConversation', args: [conversationId]);
    } catch (e) {
      _logger.e('Failed to join conversation $conversationId: $e');
    }
  }

  /// Leave a specific conversation group
  Future<void> leaveConversation(String conversationId) async {
    if (!_isConnected || _hubConnection == null) return;

    _logger.i('Leaving conversation: $conversationId');
    _cachedConversations.remove(conversationId);

    try {
      await _hubConnection!.invoke('LeaveConversation', args: [conversationId]);
    } catch (e) {
      _logger.e('Failed to leave conversation $conversationId: $e');
    }
  }

  /// Send typing indicator
  Future<void> sendTypingIndicator(String conversationId, bool isTyping) async {
    if (!_isConnected || _hubConnection == null) return;

    _logger.i(
      'Sending typing indicator for conversation $conversationId - $isTyping',
    );

    try {
      await _hubConnection!.invoke(
        'SendTypingIndicator',
        args: [conversationId, isTyping],
      );
    } catch (e) {
      _logger.e('Failed to send typing indicator: $e');
    }
  }

  /// Acknowledge message receipt
  Future<void> acknowledgeMessage(String messageId) async {
    if (!_isConnected || _hubConnection == null) return;

    _logger.i('Acknowledging message: $messageId');

    try {
      await _hubConnection!.invoke('AcknowledgeMessage', args: [messageId]);
    } catch (e) {
      _logger.e('Failed to acknowledge message $messageId: $e');
    }
  }

  /// When a call is initiated
  void onCallInitiated(String roomId, ConferenceParticipant participant) {
    _logger.i('onCallInitiated: $roomId from ${participant?.username}');

    // Don't show incoming call if we're already in this room
    final callService = CallService();
    if (callService.currentRoomId == roomId &&
        callService.currentState != CallState.idle) {
      _logger.i(
        'Suppressing incoming call notification — already in room $roomId',
      );
      return;
    }

    IncomingCallManager().showIncomingCall(
      callId: roomId,
      roomId: roomId,
      callerName: participant?.username ?? 'Unknown',
      callType: 'audio',
      autoDeclineSeconds: 30,
    );
  }

  /// Add callback for receiving new messages
  void onMessageReceived(Function(Message) callback) {
    _onMessageReceivedCallbacks.add(callback);
  }

  /// Remove callback for receiving new messages
  void removeMessageReceivedCallback(Function(Message) callback) {
    _onMessageReceivedCallbacks.remove(callback);
  }

  /// Add callback for user online status
  void onUserOnline(Function(String) callback) {
    _onUserOnlineCallbacks.add(callback);
  }

  /// Remove callback for user online status
  void removeUserOnlineCallback(Function(String) callback) {
    _onUserOnlineCallbacks.remove(callback);
  }

  /// Add callback for user offline status
  void onUserOffline(Function(String) callback) {
    _onUserOfflineCallbacks.add(callback);
  }

  /// Remove callback for user offline status
  void removeUserOfflineCallback(Function(String) callback) {
    _onUserOfflineCallbacks.remove(callback);
  }

  /// Add callback for typing indicator
  void onTypingIndicator(Function(String, bool) callback) {
    _onTypingIndicatorCallbacks.add(callback);
  }

  /// Remove callback for typing indicator
  void removeTypingIndicatorCallback(Function(String, bool) callback) {
    _onTypingIndicatorCallbacks.remove(callback);
  }

  /// Add callback for conference participant updates
  void onConferenceParticipant(
    Function(String, ConferenceParticipant, String) callback,
  ) {
    _onConferenceParticipantCallbacks.add(callback);
  }

  /// Remove callback for conference participant updates
  void removeConferenceParticipantCallback(
    Function(String, ConferenceParticipant, String) callback,
  ) {
    _onConferenceParticipantCallbacks.remove(callback);
  }

  /// Add callback for reaction updates
  void onReaction(Function(String, String, ReactionUpdate) callback) {
    _onReactionCallbacks.add(callback);
  }

  /// Remove callback for reaction updates
  void removeReactionCallback(
    Function(String, String, ReactionUpdate) callback,
  ) {
    _onReactionCallbacks.remove(callback);
  }

  /// Request current participants in a room/conference
  Future<void> requestRoomParticipants(String roomId) async {
    if (!_isConnected || _hubConnection == null) return;

    // _logger.i('Requesting room participants for: $roomId');

    try {
      await _hubConnection!.invoke('GetRoomParticipants', args: [roomId]);
    } catch (e) {
      _logger.e('Failed to request room participants for $roomId: $e');
    }
  }

  // ==================== Device Sync Methods ====================

  /// Request message sync from other devices
  /// [conversationId] - specific conversation to sync, or null for all
  /// [sinceTimestamp] - sync messages since this timestamp (milliseconds), or null for all
  /// [chunkSize] - number of messages per chunk
  Future<void> requestDeviceSync({
    String? conversationId,
    int? sinceTimestamp,
    int chunkSize = 100,
  }) async {
    if (!_isConnected || _hubConnection == null) return;

    // _logger.i(
    //   'Requesting device sync: conversationId=$conversationId, since=$sinceTimestamp',
    // );

    try {
      // SignalR requires non-null args, so we pass empty string/0 for null values
      // Backend will interpret empty string as null for conversationId
      // and 0 as "sync all" for sinceTimestamp
      await _hubConnection!.invoke(
        'RequestDeviceSync',
        args: <Object>[conversationId ?? '', sinceTimestamp ?? 0, chunkSize],
      );
    } catch (e) {
      _logger.e('Failed to request device sync: $e');
    }
  }

  /// Send sync data to another device
  /// Called in response to DeviceSyncRequest
  Future<void> sendDeviceSyncData({
    required String toDeviceId,
    String? conversationId,
    required List<SyncMessageDto> messages,
    required int chunkIndex,
    required int totalChunks,
    required bool isLastChunk,
  }) async {
    if (!_isConnected || _hubConnection == null) return;

    _logger.i(
      'Sending sync data to device $toDeviceId: chunk $chunkIndex/$totalChunks',
    );

    try {
      final messagesList = messages.map((m) => m.toJson()).toList();
      await _hubConnection!.invoke(
        'SendDeviceSyncData',
        args: <Object>[
          toDeviceId,
          conversationId ?? '',
          messagesList,
          chunkIndex,
          totalChunks,
          isLastChunk,
        ],
      );
    } catch (e) {
      _logger.e('Failed to send device sync data: $e');
    }
  }

  /// Get list of connected devices for current user
  Future<void> getConnectedDevices() async {
    if (!_isConnected || _hubConnection == null) return;

    _logger.i('Getting connected devices');

    try {
      await _hubConnection!.invoke('GetConnectedDevices', args: []);
    } catch (e) {
      _logger.e('Failed to get connected devices: $e');
    }
  }

  /// Add callback for device connected event
  void onDeviceConnected(Function(DeviceConnectedEvent) callback) {
    _onDeviceConnectedCallbacks.add(callback);
  }

  /// Remove callback for device connected event
  void removeDeviceConnectedCallback(Function(DeviceConnectedEvent) callback) {
    _onDeviceConnectedCallbacks.remove(callback);
  }

  /// Add callback for device sync request
  void onDeviceSyncRequest(Function(DeviceSyncRequest) callback) {
    _onDeviceSyncRequestCallbacks.add(callback);
  }

  /// Remove callback for device sync request
  void removeDeviceSyncRequestCallback(Function(DeviceSyncRequest) callback) {
    _onDeviceSyncRequestCallbacks.remove(callback);
  }

  /// Add callback for device sync data
  void onDeviceSyncData(Function(DeviceSyncChunk) callback) {
    _onDeviceSyncDataCallbacks.add(callback);
  }

  /// Remove callback for device sync data
  void removeDeviceSyncDataCallback(Function(DeviceSyncChunk) callback) {
    _onDeviceSyncDataCallbacks.remove(callback);
  }

  /// Add callback for other devices available event
  void onOtherDevicesAvailable(Function(OtherDevicesAvailableEvent) callback) {
    _onOtherDevicesAvailableCallbacks.add(callback);
  }

  /// Remove callback for other devices available event
  void removeOtherDevicesAvailableCallback(
    Function(OtherDevicesAvailableEvent) callback,
  ) {
    _onOtherDevicesAvailableCallbacks.remove(callback);
  }

  /// Register a callback that fires after the connection is restored
  /// (automatic reconnect, force reconnect, or full reinitialize).
  void onConnectionRestored(void Function() callback) {
    _onConnectionRestoredCallbacks.add(callback);
  }

  void removeConnectionRestoredCallback(void Function() callback) {
    _onConnectionRestoredCallbacks.remove(callback);
  }

  /// Dispose resources
  void dispose() {
    _logger.i('Disposing WebSocket manager');

    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;

    _hubConnection?.stop();
    _hubConnection = null;

    _onMessageReceivedCallbacks.clear();
    _onUserOnlineCallbacks.clear();
    _onUserOfflineCallbacks.clear();
    _onTypingIndicatorCallbacks.clear();
    _onConferenceParticipantCallbacks.clear();
    _onReactionCallbacks.clear();
    _onDeviceConnectedCallbacks.clear();
    _onDeviceSyncRequestCallbacks.clear();
    _onDeviceSyncDataCallbacks.clear();
    _onOtherDevicesAvailableCallbacks.clear();
    _onConnectionRestoredCallbacks.clear();
    _conferenceParticipants.clear();
  }
}

/// Represents a participant in a conference call
class ConferenceParticipant {
  final String id;
  final String username;
  final String? avatarUrl;

  ConferenceParticipant({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  factory ConferenceParticipant.fromJson(Map<String, dynamic> json) {
    return ConferenceParticipant(
      id: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

/// Represents a reaction update from WebSocket
class ReactionUpdate {
  final String id;
  final String emoji;
  final String userId;
  final String username;
  final bool isRemoved;

  ReactionUpdate({
    required this.id,
    required this.emoji,
    required this.userId,
    required this.username,
    this.isRemoved = false,
  });

  factory ReactionUpdate.fromJson(Map<String, dynamic> json) {
    return ReactionUpdate(
      id: json['id'] as String? ?? '',
      emoji: json['emoji'] as String,
      userId: json['userId'] as String,
      username: json['username'] as String? ?? '',
    );
  }
}

// ==================== Device Sync Classes ====================

/// Event sent when a new device of the same user connects
class DeviceConnectedEvent {
  final String userId;
  final String deviceId;
  final int totalDevices;

  DeviceConnectedEvent({
    required this.userId,
    required this.deviceId,
    required this.totalDevices,
  });

  factory DeviceConnectedEvent.fromJson(Map<String, dynamic> json) {
    return DeviceConnectedEvent(
      userId: json['userId'] as String,
      deviceId: json['deviceId'] as String,
      totalDevices: json['totalDevices'] as int,
    );
  }
}

/// Request to sync messages from other devices
class DeviceSyncRequest {
  final String requestingDeviceId;
  final String? conversationId;
  final int? sinceTimestamp;
  final int chunkSize;

  DeviceSyncRequest({
    required this.requestingDeviceId,
    this.conversationId,
    this.sinceTimestamp,
    this.chunkSize = 100,
  });

  factory DeviceSyncRequest.fromJson(Map<String, dynamic> json) {
    return DeviceSyncRequest(
      requestingDeviceId: json['requestingDeviceId'] as String,
      conversationId: json['conversationId'] as String?,
      sinceTimestamp: json['sinceTimestamp'] as int?,
      chunkSize: json['chunkSize'] as int? ?? 100,
    );
  }
}

/// A chunk of messages for device sync
class DeviceSyncChunk {
  final String fromDeviceId;
  final String toDeviceId;
  final String? conversationId;
  final List<SyncMessageDto> messages;
  final int chunkIndex;
  final int totalChunks;
  final bool isLastChunk;

  DeviceSyncChunk({
    required this.fromDeviceId,
    required this.toDeviceId,
    this.conversationId,
    required this.messages,
    required this.chunkIndex,
    required this.totalChunks,
    required this.isLastChunk,
  });

  factory DeviceSyncChunk.fromJson(Map<String, dynamic> json) {
    final messagesList =
        (json['messages'] as List?)
            ?.map((m) => SyncMessageDto.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [];

    return DeviceSyncChunk(
      fromDeviceId: json['fromDeviceId'] as String,
      toDeviceId: json['toDeviceId'] as String,
      conversationId: json['conversationId'] as String?,
      messages: messagesList,
      chunkIndex: json['chunkIndex'] as int,
      totalChunks: json['totalChunks'] as int,
      isLastChunk: json['isLastChunk'] as bool,
    );
  }
}

/// Simplified message DTO for sync
class SyncMessageDto {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderUsername;
  final String? senderAvatarUrl;
  final String content;
  final String type;
  final int sentAtTimestamp;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final int? readAtTimestamp;

  SyncMessageDto({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    this.senderAvatarUrl,
    required this.content,
    required this.type,
    required this.sentAtTimestamp,
    this.mediaUrl,
    this.thumbnailUrl,
    this.readAtTimestamp,
  });

  factory SyncMessageDto.fromJson(Map<String, dynamic> json) {
    return SyncMessageDto(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      senderUsername: json['senderUsername'] as String,
      senderAvatarUrl: json['senderAvatarUrl'] as String?,
      content: json['content'] as String,
      type: json['type'] as String,
      sentAtTimestamp: json['sentAtTimestamp'] as int,
      mediaUrl: json['mediaUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      readAtTimestamp: json['readAtTimestamp'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'senderUsername': senderUsername,
      'senderAvatarUrl': senderAvatarUrl,
      'content': content,
      'type': type,
      'sentAtTimestamp': sentAtTimestamp,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'readAtTimestamp': readAtTimestamp,
    };
  }
}

/// Event sent to a newly connected device informing about other devices
class OtherDevicesAvailableEvent {
  final int otherDeviceCount;
  final int totalDevices;
  final List<String> otherDeviceIds;

  OtherDevicesAvailableEvent({
    required this.otherDeviceCount,
    required this.totalDevices,
    required this.otherDeviceIds,
  });

  factory OtherDevicesAvailableEvent.fromJson(Map<String, dynamic> json) {
    return OtherDevicesAvailableEvent(
      otherDeviceCount: json['otherDeviceCount'] as int,
      totalDevices: json['totalDevices'] as int,
      otherDeviceIds:
          (json['otherDeviceIds'] as List?)?.map((e) => e as String).toList() ??
          [],
    );
  }
}
