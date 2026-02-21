// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:talktime/app.dart';
import 'package:talktime/core/config/environment.dart';
import 'package:talktime/core/global_key.dart';
import 'package:talktime/core/navigation_manager.dart';
import 'package:talktime/features/call/data/incoming_call_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'package:talktime/core/desktop/desktop_services.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:window_manager/window_manager.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  // Desktop: init window_manager so tray can show/focus the window; close button hides to tray
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
      // Where we have a tray (Windows/macOS), closing the window hides it instead of exiting
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        await windowManager.setPreventClose(true);
        windowManager.addListener(_CloseToTrayListener());
      }
    } catch (e) {
      Logger().e('window_manager init failed: $e');
    }
  }

  initFirebaseServices().catchError((error) {
    Logger().e("Firebase exception: $error", error: error);
  });
  IncomingCallManager().initialize(navigatorKey);

  // Desktop: global hotkeys + system tray (no-op on web/mobile)
  await initDesktopServices();

  runApp(const MyApp());
}

Future<void> initFirebaseServices() async {
  try {
    final app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await app.setAutomaticDataCollectionEnabled(false);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    Logger().e("Firebase exception: $e", error: e);

    Future.delayed(const Duration(seconds: 5), () {
      ScaffoldMessenger.of(
        navigatorKey.currentContext!,
      ).showSnackBar(SnackBar(content: Text('Failed to get fcm $e')));
    });
  }

  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
    Logger().i("CallKit is not supported on this platform");
    return;
  }

  try {
    Logger().i("CallKit, initializing");
    await FlutterCallkitIncoming.requestNotificationPermission({
      "title": "Notification permission",
      "rationaleMessagePermission":
          "Notification permission is required, to show notification.",
      "postNotificationMessageRequired":
          "Notification permission is required, Please allow notification permission from setting.",
    });

    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      Logger().i("CallKit, event ${event?.event}");
      if (event == null) {
        return;
      }

      switch (event.event) {
        case Event.actionCallIncoming:
          // Incoming call notification shown
          Logger().i('Incoming call notification displayed');
          break;
        case Event.actionCallConnected:
          // Call connected event (after accept)
          Logger().i('Call connected event received');
          break;
        case Event.actionCallStart:
          // Outgoing call started
          Logger().i('Outgoing call started');
          var data = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          try {
            IncomingCallManager().dismissIncomingCall(data.id!);
          } catch (_) {}
          break;
        case Event.actionCallAccept:
          // Accepted an incoming call
          var data = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );

          try {
            IncomingCallManager().dismissIncomingCall(data.id!);
          } catch (_) {}

          // Navigate to conference page
          NavigationManager().openConference(data.id!, []);

          // Mark call as connected on iOS
          if (!kIsWeb && Platform.isIOS) {
            FlutterCallkitIncoming.setCallConnected(data.id!).catchError((
              error,
            ) {
              Logger().e('Error setting call connected: $error');
            });
          }
          break;
        case Event.actionCallDecline:
          // User declined the incoming call (e.g. from native lock-screen UI)
          var declineData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('Call declined: ${declineData.id}');

          try {
            IncomingCallManager().dismissIncomingCall(declineData.id!);
          } catch (_) {}
          // End the native call so the system UI is dismissed
          if (declineData.id != null) {
            FlutterCallkitIncoming.endCall(declineData.id!).catchError((e) {
              Logger().e('Error ending CallKit call on decline: $e');
            });
          }
          break;
        case Event.actionCallEnded:
          // Call ended
          var endData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('Call ended: ${endData.id}');

          // End the call in CallService
          CallService().endCall().catchError((error) {
            Logger().e('Error ending call: $error');
          });

          // Navigate back if we're on the conference page
          final navigator = Navigator.of(navigatorKey.currentContext!);
          if (navigator.canPop()) {
            navigator.pop();
          }

          // End the call in CallKit
          if (endData.id != null) {
            FlutterCallkitIncoming.endCall(endData.id!).catchError((error) {
              Logger().e('Error ending CallKit call: $error');
            });
          }

          try {
            IncomingCallManager().dismissIncomingCall(endData.id!);
          } catch (_) {}
          break;
        case Event.actionCallTimeout:
          // Incoming call timed out (missed call)
          var timeoutData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('Call timed out (missed): ${timeoutData.id}');
          // The missed call notification will be shown automatically
          break;
        case Event.actionCallCallback:
          // User tapped "Call Back" from missed call notification (Android)
          var callbackData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('Call back requested: ${callbackData.id}');
          // TODO: Implement callback functionality - initiate outgoing call
          // This would typically start an outgoing call to the caller
          break;
        case Event.actionCallToggleHold:
          // Toggle hold state (iOS only)
          var holdData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('Toggle hold: ${holdData.id}');
          // Note: CallService doesn't have hold functionality yet
          // For now, just sync with CallKit
          if (holdData.id != null && !kIsWeb && Platform.isIOS) {
            // Extract hold state from event if available, or toggle
            // FlutterCallkitIncoming.holdCall(holdData.id!, isOnHold: !isCurrentlyHeld);
            Logger().w('Hold toggle not fully implemented in CallService');
            CallService().toggleMic(forceValue: false);
            CallService().toggleCamera(forceValue: false);
          }
          break;
        case Event.actionCallToggleMute:
          // Toggle mute/unmute
          var muteData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('Toggle mute: ${muteData.id}');

          // Use CallService to toggle mute
          CallService().toggleMic(forceValue: event.body['isMuted'] == false);

          // Sync with CallKit on iOS
          if (muteData.id != null && !kIsWeb && Platform.isIOS) {
            // CallKit mute state is handled automatically by the framework
            // But we can explicitly sync if needed
            // FlutterCallkitIncoming.muteCall(muteData.id!, isMuted: isMuted);
          }
          break;
        case Event.actionCallToggleDmtf:
          // DTMF (dialpad) tone sent (iOS)
          var dtmfData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('DTMF tone: ${dtmfData.id}');
          // DTMF tones are typically handled by the WebRTC layer
          // This event just notifies that a DTMF action occurred
          break;
        case Event.actionCallToggleGroup:
          // Group call toggle (iOS only)
          var groupData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('Toggle group: ${groupData.id}');
          // Group call management would need to be implemented in CallService
          Logger().w('Group call toggle not fully implemented');
          break;
        case Event.actionCallToggleAudioSession:
          // Audio session change (e.g., speaker/bluetooth) (iOS)
          var audioData = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );
          Logger().i('Audio session changed: ${audioData.id}');
          // Audio session routing is typically handled by the OS/CallKit
          // This event just notifies that the routing changed
          break;
        case Event.actionDidUpdateDevicePushTokenVoip:
          // VoIP push token updated (iOS)
          Logger().i('VoIP push token updated');
          // Get the new token and update it on the server
          if (!kIsWeb && Platform.isIOS) {
            FlutterCallkitIncoming.getDevicePushTokenVoIP()
                .then((token) {
                  Logger().i('New VoIP push token: $token');
                  // TODO: Send token to backend server
                  // This would typically involve calling your backend API
                  // to update the user's VoIP push token
                })
                .catchError((error) {
                  Logger().e('Error getting VoIP push token: $error');
                });
          }
          break;
        case Event.actionCallCustom:
          break;
      }
    });

    Logger().i("CallKit is initialized");

    // Request full-screen intent permission on Android so incoming call can show when app is in background.
    if (!kIsWeb && Platform.isAndroid) {
      final canUse = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (!canUse) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
        Logger().i("CallKit, requested full-screen intent permission");
      } else {
        Logger().i("CallKit, full-screen intent permission already granted");
      }
    }
  } catch (e) {
    Logger().e("CallKit: $e", error: e);

    Future.delayed(const Duration(seconds: 5), () {
      ScaffoldMessenger.of(
        navigatorKey.currentContext!,
      ).showSnackBar(SnackBar(content: Text('Failed to init callkit $e')));
    });
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    await handleCall(message.data);
  } catch (e, stackTrace) {
    Logger().e('Error handling call: $e', error: e, stackTrace: stackTrace);
  }
}

Future<void> handleCall(Map<String, dynamic> data) async {
  var backUrl = Environment.webBaseUrl;
  Logger().i("Handling a background message: ${jsonEncode(data)}");

  if ((data['type'] as String?) == 'call') {
    // await service.setForegroundNotificationInfo(
    //   title: "TalkTime Call",
    //   content: "Incoming Call",
    // );

    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      CallKitParams callKitParams = CallKitParams(
        id: data['call_id'] as String,
        nameCaller: data['caller_name'] as String,
        appName: Environment.appName,
        // avatar: 'https://i.pravatar.cc/100',
        // handle: '0123456789',
        type: 0,
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call from ${data['caller_name'] as String}',
        ),
        callingNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Calling...',
        ),
        duration: 30000,
        extra: <String, dynamic>{'userId': '1a2b3c4d'},
        headers: <String, dynamic>{'apiKey': 'Abc@123!', 'platform': 'flutter'},
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#152545',
          backgroundUrl: '$backUrl/icons/call_bg.jpg',
          actionColor: '#6b80de',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Incoming Call',
          missedCallNotificationChannelName: 'Missed Call',
          isShowCallID: false,
          isShowFullLockedScreen: true,
        ),
        ios: IOSParams(
          // iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );
      await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
    }
  }
}

/// Hides the window when user clicks close (X); app stays running in tray.
class _CloseToTrayListener with WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }
}
