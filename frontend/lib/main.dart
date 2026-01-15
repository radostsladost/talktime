// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:talktime/app.dart';
import 'package:talktime/core/global_key.dart';
import 'package:talktime/features/call/data/incoming_call_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundService(); // see below

  // Initialize the incoming call manager with the global navigator key
  IncomingCallManager().initialize(navigatorKey);
  await initFirebaseServices();

  runApp(const MyApp());
}

Future<void> initFirebaseServices() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    Logger().e("Firebase exception: $e", error: e);
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

  print("Handling a background message: $message");
}
