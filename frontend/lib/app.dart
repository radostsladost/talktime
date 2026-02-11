// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:talktime/core/global_key.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/auth/presentation/pages/login_page.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/chat/data/device_sync_service.dart';
import 'package:talktime/features/chat/presentation/pages/chat_split_view.dart';
import 'package:talktime/features/settings/data/settings_service.dart';
import 'package:logger/logger.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final SettingsService _settingsService = SettingsService();
  ThemeMode _themeMode = ThemeMode.system;
  Color _colorSeed = Colors.blue;

  StreamSubscription? _themeSub;
  StreamSubscription? _colorSub;

  @override
  void initState() {
    super.initState();

    var listener = AppLifecycleListener(
      onDetach: () {
        CallService().endCall();
      },
      onShow: () {
        AuthService().isAuthenticated().then((value) {
          if (!value) return;

          WebSocketManager().checkConnection();
        });
      },
    );

    // Load initial settings
    _loadSettings();

    // Listen for settings changes
    _themeSub = _settingsService.themeModeStream.listen((mode) {
      setState(() => _themeMode = mode);
    });
    _colorSub = _settingsService.colorSeedStream.listen((color) {
      setState(() => _colorSeed = color);
    });
  }

  Future<void> _loadSettings() async {
    final themeMode = await _settingsService.getThemeMode();
    final colorSeed = await _settingsService.getColorSeed();
    if (mounted) {
      setState(() {
        _themeMode = themeMode;
        _colorSeed = colorSeed;
      });
    }
  }

  @override
  void dispose() {
    _themeSub?.cancel();
    _colorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TalkTime',
      navigatorKey: navigatorKey, // Use global navigator key for incoming calls
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _colorSeed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _colorSeed,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: _themeMode,
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
  final _settingsService = SettingsService();

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
        // Register Firebase token only if notifications are enabled (respects user choice).
        // On web (e.g. iOS Safari), do NOT request permission on startup: Safari blocks
        // notification permission unless it's triggered by a direct user gesture. Users can
        // enable notifications via Settings → Enable Notifications (that tap counts as gesture).
        try {
          if (!kIsWeb) {
            final notificationsEnabled = await _settingsService.getNotificationsEnabled();
            if (notificationsEnabled) {
              final messagePreview = await _settingsService.getMessagePreview();
              await _authService.registerFirebaseToken(messagePreview: messagePreview);
            }
          }
          // On web, registerFirebaseToken() is called when user taps "Enable Notifications" in Settings.

          await WebSocketManager().initialize();
          
          // Initialize device sync service for cross-device message synchronization
          DeviceSyncService().initialize();
        } catch (e) {
          // Log error but don't block navigation
          Logger().e('Failed to register Firebase token: $e');
        }

        // User is logged in, go to chat split view (responsive)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatSplitView()),
        );
      } else {
        // User is not logged in, go to login page
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
      }
    } catch (e, stackTrace) {
      Logger().e('Failed to _checkAuthentication: $e', stackTrace: stackTrace);
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
