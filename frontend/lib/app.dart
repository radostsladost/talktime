// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:talktime/core/global_key.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/auth/presentation/pages/login_page.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/call/presentation/pages/guest_name_page.dart';
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
          WebSocketManager().ensureConnected();
        });
      },
      onResume: () {
        AuthService().isAuthenticated().then((value) {
          if (!value) return;
          WebSocketManager().ensureConnected();
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

  /// Extract the invite key from the current URL (web only).
  /// Format: ?key=INVITE_KEY (64-char hex string)
  String? _getDeepLinkInviteKey() {
    if (!kIsWeb) return null;

    try {
      final uri = Uri.base;
      final key = uri.queryParameters['key'];
      if (key != null && key.length >= 64) {
        return key;
      }
    } catch (e) {
      Logger().e('Error parsing deep link: $e');
    }

    return null;
  }

  Future<void> _checkAuthentication() async {
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    final inviteKey = _getDeepLinkInviteKey();

    try {
      final isAuthenticated = await _authService.isAuthenticated();

      if (!mounted) return;

      if (isAuthenticated) {
        // Authenticated user flow
        try {
          if (!kIsWeb) {
            final notificationsEnabled = await _settingsService.getNotificationsEnabled();
            if (notificationsEnabled) {
              final messagePreview = await _settingsService.getMessagePreview();
              await _authService.registerFirebaseToken(messagePreview: messagePreview);
            }
          }

          await WebSocketManager().initialize();
          DeviceSyncService().initialize();
        } catch (e) {
          Logger().e('Failed to register Firebase token: $e');
        }

        // Authenticated users always go to the main chat view.
        // If they have an invite key they can use the share link themselves,
        // but they join calls through the normal conversation UI.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatSplitView()),
        );
      } else {
        // Not authenticated
        if (inviteKey != null) {
          // Guest flow: show name prompt, then join call directly via invite key
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GuestNamePage(inviteKey: inviteKey),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
        }
      }
    } catch (e, stackTrace) {
      Logger().e('Failed to _checkAuthentication: $e', stackTrace: stackTrace);
      if (!mounted) return;

      if (inviteKey != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GuestNamePage(inviteKey: inviteKey),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
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
