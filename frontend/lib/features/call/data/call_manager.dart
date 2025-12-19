import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/features/call/presentation/pages/call_page.dart';
import 'package:talktime/core/network/api_client.dart';

/// CallManager handles incoming calls globally and manages call state
/// This should be initialized once in the app and kept alive
class CallManager {
  static final CallManager _instance = CallManager._internal();
  factory CallManager() => _instance;
  CallManager._internal();

  SignalingService? _signalingService;
  final Logger _logger = Logger();
  final List<StreamSubscription> _subscriptions = [];

  bool _isInitialized = false;
  BuildContext? _context;

  /// Initialize the call manager with SignalR connection
  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) {
      _logger.w('CallManager already initialized');
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
      _subscriptions.add(
        _signalingService!.onIncomingCall.listen(_handleIncomingCall),
      );

      _isInitialized = true;
      _logger.i('CallManager initialized successfully');
    } catch (e) {
      _logger.e('Failed to initialize CallManager: $e');
      rethrow;
    }
  }

  /// Handle incoming call event
  void _handleIncomingCall(IncomingCallEvent event) {
    _logger.i('Incoming call from ${event.caller.username}');

    if (_context == null || !_context!.mounted) {
      _logger.w('No context available to show incoming call');
      return;
    }

    // Show incoming call screen
    Navigator.of(_context!).push(
      MaterialPageRoute(
        builder: (context) => CallPage(
          isOutgoing: false,
          peerName: event.caller.username,
          peerId: event.caller.id,
          callId: event.callId,
          callType: event.callType == 'video' ? CallType.video : CallType.audio,
        ),
      ),
    );
  }

  /// Initiate an outgoing call
  Future<void> initiateCall({
    required BuildContext context,
    required String peerId,
    required String peerName,
    required CallType callType,
  }) async {
    if (_signalingService == null || !_signalingService!.isConnected) {
      throw Exception('SignalR service not connected');
    }

    _logger.i('Initiating ${callType.name} call to $peerId');

    // Navigate to call page
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CallPage(
          isOutgoing: true,
          peerName: peerName,
          peerId: peerId,
          callType: callType,
        ),
      ),
    );
  }

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
    _logger.i('Disposing CallManager');

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
      _logger.w('Cannot reconnect: CallManager not initialized');
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
