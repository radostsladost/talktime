// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:talktime/core/global_key.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/auth/presentation/pages/login_page.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/chat/presentation/pages/chat_list_page.dart';
import 'package:logger/logger.dart';

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
      onShow: () {
        AuthService().isAuthenticated().then((value) {
          if (!value) return;

          WebSocketManager().checkConnection();
        });
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

          WebSocketManager().initialize();
        } catch (e) {
          // Log error but don't block navigation
          Logger().e('Failed to register Firebase token: $e');
        }

        // User is logged in, go to chat list
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatListPage()),
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
