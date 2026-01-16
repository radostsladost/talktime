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
  await initializeBackgroundService(); // see below

  // Initialize the incoming call manager with the global navigator key
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

          FlutterCallkitIncoming.setCallConnected(data.id!).catchError((error) {
            Logger().e('Error setting call connected: $error');
          });
          break;
        case Event.actionCallDecline:
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
        case Event.actionCallCallback:
        case Event.actionCallToggleHold:
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

// SEPARATE ISOLATE (or not on IOS)
Future<void> initializeBackgroundService() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
    return;
  }

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBgStart,
      autoStart: false, // Start only when call starts
      isForegroundMode: true,
      notificationChannelId: 'calls',
      initialNotificationTitle: 'Call in progress',
      initialNotificationContent: 'Tap to return to call',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: (service) {},
      onBackground: (service) {
        // Ensure we don't kill the app
        return true;
      },
    ),
  );
}

@pragma('vm:entry-point')
void onBgStart(ServiceInstance service) async {
  // This runs in a separate isolate (on Android) or same isolate (iOS)
  // For WebRTC to work smoothly, prefer keeping logic in main isolate
  // and just use the service to show the notification that keeps app alive.
  //
  // 1. Initialize Dart bindings ensuring plugins can be used
  DartPluginRegistrant.ensureInitialized();

  // 2. Configure for Android specific handling
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // 3. Listen for the "stopService" event from the Main Isolate
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 4. Listen for updates from Main Isolate (e.g. to update name/timer)
  service.on('updateNotification').listen((event) {
    if (event != null && service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: event['title'] ?? 'TalkTime Call',
        content: event['content'] ?? 'Tap to return to call',
      );
    }
  });

  // 5. Set initial notification immediately so the service doesn't crash
  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: "TalkTime Call",
      content: "Connecting...",
    );
  }

  // 6. Keep the isolate alive
  // We don't need a complex loop here. The service stays alive
  // until stopSelf() is called.
  // Optionally, you can run a timer to update the notification
  // if you want to show a counter "00:01", "00:02" directly from here.
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // You could update a timestamp here if you wanted independent timing
        // service.setForegroundNotificationInfo(...)
      }
    }
  });
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if ((message.data['call_type'] as String?) == 'voip_incoming_call') {
    // await service.setForegroundNotificationInfo(
    //   title: "TalkTime Call",
    //   content: "Incoming Call",
    // );

    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      CallKitParams callKitParams = CallKitParams(
        id: message.data['call_id'] as String,
        nameCaller: message.data['caller_name'] as String,
        appName: 'TalkTime',
        // avatar: 'https://i.pravatar.cc/100',
        // handle: '0123456789',
        type: 0,
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call from ${message.data['caller_name'] as String}',
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

  print("Handling a background message: ${jsonEncode(message.data)}");
}
