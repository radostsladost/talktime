// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:talktime/core/global_key.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/auth/presentation/pages/login_page.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'package:talktime/features/chat/presentation/pages/chat_list_page.dart';
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

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } 
  catch (e) {
    Logger().e("Firebase exception: $e", error: e);
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    var listener = AppLifecycleListener(
      onDetach: () {
        CallService().endCall();
      },
      // onRestart: () => _handleTransition('restart'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TalkTime',
      navigatorKey: navigatorKey, // Use global navigator key for incoming calls
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true), // standard dark theme
      themeMode: ThemeMode.system, // device controls theme
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Add a small delay for better UX
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    try {
      final isAuthenticated = await _authService.isAuthenticated();

      if (!mounted) return;

      if (isAuthenticated) {
        // Register Firebase token for push notifications
        try {
          await _authService.registerFirebaseToken();
        } catch (e) {
          // Log error but don't block navigation
          Logger().e('Failed to register Firebase token: $e');
        }

        // User is logged in, go to chat list
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatListPage()),
        );

        WebSocketManager().initialize();
      } else {
        // User is not logged in, go to login page
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
      }
    } catch (e) {
      // If there's an error, go to login page
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 100,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'TalkTime',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 48),
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
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
