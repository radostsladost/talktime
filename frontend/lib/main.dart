// lib/main.dart
import 'package:flutter/material.dart';
import 'package:talktime/features/chat/presentation/pages/chat_list_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TalkTime',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const ChatListPage(), // Main screen: list of DMs/groups
    );
  }
}