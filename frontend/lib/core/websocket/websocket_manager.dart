import 'dart:async';
import 'package:logger/logger.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:signalr_netcore/http_connection_options.dart';

/// WebSocket manager for real-time messaging using SignalR
class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  factory WebSocketManager() => _instance;
  WebSocketManager._internal();

  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  final Logger _logger = Logger(output: ConsoleOutput());
  final ApiClient _apiClient = ApiClient();
  HubConnection? _hubConnection;

  // Callbacks for different events
  final List<Function(Message)> _onMessageReceivedCallbacks = [];
  final List<Function(String)> _onUserOnlineCallbacks = [];
  final List<Function(String)> _onUserOfflineCallbacks = [];
  final List<Function(String, bool)> _onTypingIndicatorCallbacks = [];
  final List<String> _cachedConversations = [];

  /// Initialize WebSocket connection with SignalR
  Future<void> initialize() async {
    _logger.i('Initializing WebSocket manager');

    try {
      final connectionUrl = ApiConstants.getSignalingUrlWithNoToken();

      _logger.i('SignalR connection URL: $connectionUrl');

      if (_hubConnection != null &&
          (_hubConnection!.state == HubConnectionState.Connected ||
              _hubConnection!.state == HubConnectionState.Connecting ||
              _hubConnection!.state == HubConnectionState.Reconnecting)) {
        _hubConnection!.stop();
      }

      _hubConnection = HubConnectionBuilder()
          .withUrl(
            connectionUrl,
            options: HttpConnectionOptions(
              accessTokenFactory: () async =>
                  (await _apiClient.getToken()) ?? "",
            ),
          )
          .build();

      // Setup connection event handlers
      _setupConnectionHandlers();

      // Start connection
      await _connect();

      _logger.i('SignalR connection established');
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;

      // Setup message handlers
      _setupMessageHandlers();
    } catch (e) {
      _logger.e('Failed to initialize WebSocket: $e');
    }
  }

  /// Setup SignalR connection event handlers
  void _setupConnectionHandlers() {
    if (_hubConnection == null) return;

    // Handle connection closed
    _hubConnection!.onclose(({Exception? error}) {
      _logger.i('SignalR connection closed: $error');
      _isConnected = false;
      _isConnecting = false;

      // Attempt to reconnect
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _reconnectAttempts++;
        _logger.i(
          'Reconnection attempt $_reconnectAttempts of $_maxReconnectAttempts',
        );
        Future.delayed(_reconnectDelay, _connect);
      } else {
        _logger.e('Max reconnection attempts reached');
      }
    });

    // Handle connection established
    _hubConnection!.onreconnected(({String? connectionId}) {
      _logger.i('SignalR connection established');
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
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
    } catch (e) {
      _logger.e('Error processing received message: $e');
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

  /// Dispose resources
  void dispose() {
    _logger.i('Disposing WebSocket manager');

    _hubConnection?.stop();
    _hubConnection = null;

    _onMessageReceivedCallbacks.clear();
    _onUserOnlineCallbacks.clear();
    _onUserOfflineCallbacks.clear();
    _onTypingIndicatorCallbacks.clear();
  }
}
