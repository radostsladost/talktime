import 'package:flutter/material.dart';
import 'package:talktime/core/global_key.dart';
import 'package:talktime/features/call/data/signaling_service.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'package:talktime/features/chat/presentation/pages/create_conversation.dart';
import 'package:talktime/features/chat/presentation/pages/create_group_chat.dart';
import 'package:talktime/features/chat/presentation/pages/message_list_page.dart';
import 'package:talktime/features/profile/presentation/pages/edit_profile_page.dart';
import 'package:talktime/shared/models/conversation.dart';

class NavigationManager {
  // Singleton pattern
  static final NavigationManager _instance = NavigationManager._internal();
  factory NavigationManager() => _instance;
  NavigationManager._internal();

  void openMessagesList(Conversation conversation) {
    Navigator.push(
      navigatorKey.currentContext!,
      MaterialPageRoute(
        builder: (context) => MessageListPage(conversation: conversation),
      ),
    );
  }

  void openCreateConversation() {
    Navigator.push(
      navigatorKey.currentContext!,
      MaterialPageRoute(builder: (context) => CreateConversationPage()),
    );
  }

  void openCreateGroup() {
    Navigator.push(
      navigatorKey.currentContext!,
      MaterialPageRoute(builder: (context) => CreateGroupChatPage()),
    );
  }

  void openEditProfile() {
    Navigator.push(
      navigatorKey.currentContext!,
      MaterialPageRoute(builder: (context) => const EditProfilePage()),
    );
  }

  void openConference(String roomId, List<UserInfo> initialParticipants) {
    Navigator.push(
      navigatorKey.currentContext!,
      MaterialPageRoute(
        builder: (context) => ConferencePage(
          roomId: roomId,
          initialParticipants: initialParticipants,
        ),
      ),
    );
  }
}
