import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:logger/logger.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/features/call/presentation/pages/incoming_call_page.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';

/// Manages incoming calls and displays the incoming call UI from anywhere in the app.
///
/// Usage:
/// 1. Initialize with a navigator key in your main.dart:
///    ```dart
///    final navigatorKey = GlobalKey<NavigatorState>();
///    IncomingCallManager().initialize(navigatorKey);
///    ```
///
/// 2. Set up the MaterialApp with the navigator key:
///    ```dart
///    MaterialApp(
///      navigatorKey: navigatorKey,
///      ...
///    )
///    ```
///
/// 3. Listen for incoming calls (typically after SignalR connection):
///    ```dart
///    signalingService.onIncomingCall.listen((event) {
///      IncomingCallManager().showIncomingCall(
///        callId: event.callId,
///        callerName: event.caller.username,
///        callerAvatarUrl: event.caller.avatarUrl,
///        callType: event.callType,
///        roomId: event.roomId,
///      );
///    });
///    ```
class IncomingCallManager {
  static final IncomingCallManager _instance = IncomingCallManager._internal();
  factory IncomingCallManager() => _instance;
  IncomingCallManager._internal();

  final Logger _logger = Logger(output: ConsoleOutput());

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _isShowingIncomingCall = false;
  String? _currentCallId;
  Timer? _autoDeclineTimer;

  // Callbacks for external handling.
  // If onCallAccepted returns true, the manager will NOT push ConferencePage (caller handles navigation).
  bool Function(String callId, String? roomId)? _onCallAccepted;
  Function(String callId)? _onCallDeclined;

  /// Initialize the manager with a navigator key
  /// Call this in your main.dart before runApp
  void initialize(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _logger.i('IncomingCallManager initialized');
  }

  /// Set callback for when a call is accepted.
  /// Return true to handle navigation yourself (e.g. open chat+call panel on wide screen); false to use default full-screen conference.
  void setOnCallAccepted(bool Function(String callId, String? roomId) callback) {
    _onCallAccepted = callback;
  }

  /// Set callback for when a call is declined
  void setOnCallDeclined(Function(String callId) callback) {
    _onCallDeclined = callback;
  }

  /// Check if an incoming call is currently being shown
  bool get isShowingIncomingCall => _isShowingIncomingCall;

  /// Get the current call ID being shown
  String? get currentCallId => _currentCallId;

  /// Show the incoming call screen
  ///
  /// [callId] - Unique identifier for the call
  /// [callerName] - Display name of the caller
  /// [callerAvatarUrl] - Optional avatar URL of the caller
  /// [callType] - Type of call ('video' or 'audio')
  /// [roomId] - Optional room ID for the call
  /// [autoDeclineSeconds] - Automatically decline after this many seconds (default: 60)
  void showIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatarUrl,
    required String callType,
    String? roomId,
    int autoDeclineSeconds = 60,
  }) {
    if (_navigatorKey?.currentState == null) {
      _logger.e('Navigator key not initialized. Call initialize() first.');
      return;
    }

    if (_isShowingIncomingCall) {
      _logger.w(
        'Already showing an incoming call. Ignoring new call from $callerName',
      );
      return;
    }

    _isShowingIncomingCall = true;
    _currentCallId = callId;

    _logger.i(
      'Showing incoming call from $callerName (type: $callType, roomId: $roomId)',
    );

    // Set auto-decline timer
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = Timer(Duration(seconds: autoDeclineSeconds), () {
      _logger.i('Auto-declining call after $autoDeclineSeconds seconds');
      _handleDecline(callId);
    });

    // Push the incoming call page
    _navigatorKey!.currentState!.push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return IncomingCallPage(
            callId: callId,
            callerName: callerName,
            callerAvatarUrl: callerAvatarUrl,
            callType: callType,
            roomId: roomId,
            onAccept: () => _handleAccept(callId, roomId),
            onDecline: () => _handleDecline(callId),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// Handle accepting the call
  void _handleAccept(String callId, String? roomId) async {
    _logger.i('Call accepted: $callId');
    _cleanup();

    // Tell backend we accepted
    try {
      await SignalingService().acceptCall(callId);
    } catch (e) {
      _logger.e('Failed to accept call via signaling: $e');
    }

    // Pop the incoming call screen
    if (_navigatorKey?.currentState?.canPop() ?? false) {
      _navigatorKey!.currentState!.pop();
    }

    // Let app handle navigation (e.g. open chat+call panel on wide screen); if not handled, push full-screen conference.
    final handled = _onCallAccepted?.call(callId, roomId) ?? false;
    if (!handled && roomId != null && _navigatorKey?.currentState != null) {
      _navigatorKey!.currentState!.push(
        MaterialPageRoute(
          builder: (context) =>
              ConferencePage(roomId: roomId, initialParticipants: []),
        ),
      );
    }
  }

  /// Handle declining the call
  void _handleDecline(String callId) async {
    _logger.i('Call declined: $callId');
    _cleanup();

    // Reject via signaling so the caller is notified
    try {
      await SignalingService().rejectCall(callId, 'declined');
    } catch (e) {
      _logger.e('Failed to reject call via signaling: $e');
    }

    // End native call UI on phone so the system dismisses the call
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await FlutterCallkitIncoming.endCall(callId);
      } catch (e) {
        _logger.e('Failed to end CallKit call: $e');
      }
    }

    // Pop the incoming call screen
    if (_navigatorKey?.currentState?.canPop() ?? false) {
      _navigatorKey!.currentState!.pop();
    }

    // Notify external listeners
    _onCallDeclined?.call(callId);
  }

  /// Dismiss the incoming call (e.g., when the caller cancels)
  void dismissIncomingCall(String callId) {
    if (_currentCallId != callId) {
      _logger.w(
        'Attempted to dismiss wrong call. Current: $_currentCallId, Requested: $callId',
      );
      return;
    }

    _logger.i('Dismissing incoming call: $callId');
    _cleanup();

    // Pop the incoming call screen
    if (_navigatorKey?.currentState?.canPop() ?? false) {
      _navigatorKey!.currentState!.pop();
    }
  }

  /// Clean up internal state
  void _cleanup() {
    _currentCallId = null;
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = null;
    _isShowingIncomingCall = false;
  }

  /// Dispose of resources
  void dispose() {
    _cleanup();
    _onCallAccepted = null;
    _onCallDeclined = null;
    _navigatorKey = null;
  }
}

/// Extension method to easily show incoming calls from BuildContext
extension IncomingCallExtension on BuildContext {
  /// Show incoming call screen using the IncomingCallManager
  void showIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatarUrl,
    required String callType,
    String? roomId,
  }) {
    IncomingCallManager().showIncomingCall(
      callId: callId,
      callerName: callerName,
      callerAvatarUrl: callerAvatarUrl,
      callType: callType,
      roomId: roomId,
    );
  }
}
