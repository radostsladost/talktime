import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:talktime/core/constants/api_constants.dart';

/// SignalingService handles WebSocket connection to the SignalR hub
/// for real-time signaling (call offers, answers, ICE candidates)
class SignalingService {
  WebSocketChannel? _channel;
  final String _userId;
  final String _accessToken;
  final Logger _logger = Logger();

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  SignalingService(this._userId, this._accessToken);

  /// Stream of incoming messages from the SignalR hub
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  /// Check if connected
  bool get isConnected => _channel != null;

  /// Connect to the SignalR hub
  Future<void> connect() async {
    try {
      // Build WebSocket URL with authentication token
      final url = ApiConstants.getSignalingUrl(_userId, _accessToken);
      final uri = Uri.parse(url);

      _logger.i('Connecting to SignalR hub: $uri');

      // Connect to WebSocket
      _channel = IOWebSocketChannel.connect(uri);

      // Listen to incoming messages
      _channel!.stream.listen(
        (dynamic message) {
          _logger.d('Received message: $message');
          try {
            if (message is String) {
              final data = jsonDecode(message) as Map<String, dynamic>;
              _messageController.add(data);
            } else {
              _logger.w('Received non-string message: $message');
            }
          } catch (e) {
            _logger.e('Error parsing message: $e');
          }
        },
        onError: (error) {
          _logger.e('WebSocket error: $error');
          _messageController.addError(error);
        },
        onDone: () {
          _logger.i('WebSocket connection closed');
          _channel = null;
        },
      );

      _logger.i('Successfully connected to SignalR hub');
    } catch (e) {
      _logger.e('Failed to connect to SignalR hub: $e');
      rethrow;
    }
  }

  /// Send a message through the SignalR hub
  void send(String method, Map<String, dynamic> data) {
    if (_channel == null) {
      _logger.w('Cannot send message: not connected');
      return;
    }

    try {
      final message = jsonEncode({'method': method, 'data': data});

      _logger.d('Sending message: $message');
      _channel!.sink.add(message);
    } catch (e) {
      _logger.e('Error sending message: $e');
    }
  }

  /// Send call offer
  void sendCallOffer({
    required String targetUserId,
    required String callId,
    required Map<String, dynamic> offer,
  }) {
    send('CallOffer', {
      'targetUserId': targetUserId,
      'callId': callId,
      'offer': offer,
    });
  }

  /// Send call answer
  void sendCallAnswer({
    required String targetUserId,
    required String callId,
    required Map<String, dynamic> answer,
  }) {
    send('CallAnswer', {
      'targetUserId': targetUserId,
      'callId': callId,
      'answer': answer,
    });
  }

  /// Send ICE candidate
  void sendIceCandidate({
    required String targetUserId,
    required String callId,
    required Map<String, dynamic> candidate,
  }) {
    send('IceCandidate', {
      'targetUserId': targetUserId,
      'callId': callId,
      'candidate': candidate,
    });
  }

  /// End call
  void endCall({required String targetUserId, required String callId}) {
    send('EndCall', {'targetUserId': targetUserId, 'callId': callId});
  }

  /// Disconnect from the SignalR hub
  Future<void> disconnect() async {
    try {
      _logger.i('Disconnecting from SignalR hub');
      await _channel?.sink.close();
      _channel = null;
    } catch (e) {
      _logger.e('Error disconnecting: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
