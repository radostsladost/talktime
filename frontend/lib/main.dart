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
import 'package:talktime/core/global_key.dart';
import 'package:talktime/features/call/data/incoming_call_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebaseServices();

  await dotenv.load(fileName: ".env");
  IncomingCallManager().initialize(navigatorKey);
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

  if (!kIsWeb && !(Platform.isAndroid || Platform.isIOS)) {
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
        case Event.actionCallConnected:
        case Event.actionCallStart:
          break;
        case Event.actionCallAccept:
          // TODO: accepted an incoming call
          // TODO: show screen calling in Flutter
          var data = CallKitParams.fromJson(
            jsonDecode(jsonEncode(event.body as Map<dynamic, dynamic>)),
          );

          Navigator.push(
            navigatorKey.currentContext!,
            MaterialPageRoute(
              builder: (context) =>
                  ConferencePage(roomId: data.id!, initialParticipants: []),
            ),
          );

          if (!kIsWeb && Platform.isIOS) {
            FlutterCallkitIncoming.setCallConnected(data.id!).catchError((
              error,
            ) {
              Logger().e('Error setting call connected: $error');
            });
          }
          break;
        case Event.actionCallDecline:
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
        case Event.actionCallCallback:
        case Event.actionCallToggleHold:ve
        case Event.actionCallToggleMute:
        case Event.actionCallToggleDmtf:
        case Event.actionCallToggleGroup:
        case Event.actionCallToggleAudioSession:
        case Event.actionDidUpdateDevicePushTokenVoip:
        case Event.actionCallCustom:
          // TODO: for custom action
          break;
      }
    });

    Logger().i("CallKit is initialized");

    if (!await FlutterCallkitIncoming.canUseFullScreenIntent()) {
      await FlutterCallkitIncoming.requestFullIntentPermission();
      Logger().i("CallKit, canUseFullScreenIntent = true");
    } else {
      Logger().i("CallKit, canUseFullScreenIntent = false");
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
        appName: 'TalkTime',
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
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          // logoUrl: 'https://i.pravatar.cc/100',
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          // backgroundUrl: 'https://i.pravatar.cc/500',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: "Incoming Call",
          missedCallNotificationChannelName: "Missed Call",
          isShowCallID: false,
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
