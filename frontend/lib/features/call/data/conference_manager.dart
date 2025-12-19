import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/features/call/presentation/pages/call_page.dart';
import 'package:talktime/core/network/api_client.dart';

/// ConferenceManager handles incoming calls globally and manages call state
/// This should be initialized once in the app and kept alive
class ConferenceManager {
  static final ConferenceManager _instance = ConferenceManager._internal();
  factory ConferenceManager() => _instance;
  ConferenceManager._internal();

  SignalingService? _signalingService;
  final Logger _logger = Logger();
  final List<StreamSubscription> _subscriptions = [];

  bool _isInitialized = false;
  BuildContext? _context;

  /// Initialize the call manager with SignalR connection
  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) {
      _logger.w('ConferenceManager already initialized');
      return;
    }

    _context = context;

    try {
      // Get access token
      final apiClient = ApiClient();
      final token = await apiClient.getToken();

      if (token == null) {
        _logger.w('No access token found, skipping SignalR initialization');
        return;
      }

      // Initialize SignalR service
      _signalingService = SignalingService(token);
      await _signalingService!.connect();

      // Listen for incoming calls
      _subscriptions
        ..add(_signalingService!.onRoomCreated.listen(_handleRoomCreated))
        ..add(_signalingService!.onRoomJoined.listen(_handleRoomJoined));
      /* ..add(
          _signalingService!.onParticipantJoined.listen(
            _handleParticipantJoined,
          ),
        )
        ..add(
          _signalingService!.onParticipantLeft.listen(_handleParticipantLeft),
        ) */

      _isInitialized = true;
      _logger.i('ConferenceManager initialized successfully');
    } catch (e) {
      _logger.e('Failed to initialize ConferenceManager: $e');
      rethrow;
    }
  }

  void _handleRoomCreated(RoomCreatedEvent event) {
    // Optionally auto-navigate or just store
    _logger.i('Room created: ${event.roomId}');
    // if (_context?.mounted == true) {
    //   Navigator.of(_context!).push(
    //     MaterialPageRoute(
    //       builder: (context) => ConferencePage(
    //         roomId: event.roomId,
    //         conversationId: event.conversationId,
    //         participants: event.participants,
    //         isCreator: true,
    //       ),
    //     ),
    //   );
    // }
  }

  void _handleRoomJoined(RoomJoinedEvent event) {
    _logger.i('Room joined: ${event.roomId}');
    // if (_context?.mounted == true) {
    //   Navigator.of(_context!).push(
    //     MaterialPageRoute(
    //       builder: (context) => ConferencePage(
    //         roomId: event.roomId,
    //         conversationId: event.conversationId,
    //         participants: event.participants,
    //         isCreator: false,
    //       ),
    //     ),
    //   );
    // }
  }

  // Participant updates can be sent to active ConferencePage via callbacks or state management

  Future<void> createConference(String conversationId) async {
    await _signalingService?.createRoom(conversationId);
  }

  Future<void> joinConference(String roomId) async {
    await _signalingService?.joinRoom(roomId);
  }

  Future<void> leaveConference(String roomId) async {
    await _signalingService?.leaveRoom(roomId);
  }

  // Signaling helpers
  Future<void> sendOffer(String roomId, String sdp) =>
      _signalingService?.sendRoomOffer(roomId, sdp) ?? Future.value();

  Future<void> sendIceCandidate(
    String roomId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) =>
      _signalingService?.sendRoomIceCandidate(
        roomId,
        candidate,
        sdpMid,
        sdpMLineIndex,
      ) ??
      Future.value();

  /// Update context (useful when navigating between screens)
  void updateContext(BuildContext context) {
    _context = context;
  }

  /// Check if manager is initialized
  bool get isInitialized => _isInitialized;

  /// Check if SignalR is connected
  bool get isConnected => _signalingService?.isConnected ?? false;

  /// Dispose and clean up resources
  Future<void> dispose() async {
    _logger.i('Disposing ConferenceManager');

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    await _signalingService?.disconnect();
    _signalingService?.dispose();
    _signalingService = null;

    _isInitialized = false;
    _context = null;
  }

  /// Reconnect SignalR if disconnected
  Future<void> reconnect() async {
    if (!_isInitialized) {
      _logger.w('Cannot reconnect: ConferenceManager not initialized');
      return;
    }

    try {
      _logger.i('Reconnecting SignalR...');
      await _signalingService?.connect();
      _logger.i('Reconnected successfully');
    } catch (e) {
      _logger.e('Failed to reconnect: $e');
      rethrow;
    }
  }
}
