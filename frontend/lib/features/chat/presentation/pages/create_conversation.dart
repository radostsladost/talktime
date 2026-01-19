import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talktime/core/navigation_manager.dart';
import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/features/chat/presentation/pages/message_list_page.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:logger/logger.dart';

class CreateConversationPage extends StatefulWidget {
  const CreateConversationPage({super.key});

  @override
  State<CreateConversationPage> createState() => _CreateConversationPageState();
}

class _CreateConversationPageState extends State<CreateConversationPage> {
  final Logger _logger = Logger(output: ConsoleOutput());
  final TextEditingController _querySearchController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  String? _errorText;
  bool _isLoading = false;
  User? _foundUser; // Assume UserInfo is defined (id, username, avatarUrl)

  @override
  void dispose() {
    _querySearchController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _lookupUser() async {
    final username = _querySearchController.text.trim();
    if (username.isEmpty) {
      _setError('Please enter an username');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
      _foundUser = null;
    });

    try {
      final apiClient = ConversationService();
      final auth = AuthService();
      final user = (await apiClient.searchUser(username)).firstOrNull;

      if (user == null) {
        _setError('User not found with this email');
        return;
      }

      if (user.id == (await auth.getCurrentUser()).id) {
        _setError('You cannot start a chat with yourself');
        return;
      }

      setState(() {
        _foundUser = user;
      });
    } catch (e) {
      _logger.e('User lookup failed: $e');
      _setError('Failed to find user. Please try again.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setError(String message) {
    setState(() {
      _errorText = message;
      _foundUser = null;
    });
  }

  Future<void> _startChatting() async {
    if (_foundUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final apiClient = ConversationService();
      final conversation = await apiClient.createDirectConversation(
        _foundUser!.id,
      );

      if (conversation == null) {
        _setError('Failed to create conversation');
        return;
      }

      // Navigate to Conference (or Chat) page
      // For now, we go to ConferencePage (you can change to ChatPage if needed)
      NavigationManager().openMessagesList(conversation);


      // Optionally create room via signaling here instead of relying on backend auto-create
      // But your backend already creates room on `CreateRoom(conversationId)`
    } catch (e) {
      _logger.e('Start chatting failed: $e');
      _setError('Could not start chat. Please try again.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<User> _getSelfUserInfo() async {
    final auth = AuthService();
    return await auth.getCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Contact')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the email of the person you’d like to start a conversation with:',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _querySearchController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _lookupUser(),
              decoration: InputDecoration(
                labelText: 'User Name',
                border: const OutlineInputBorder(),
                errorText: _errorText,
                suffixIcon: _foundUser != null
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            if (_foundUser != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (_foundUser!.avatarUrl != null)
                      CircleAvatar(
                        backgroundImage: NetworkImage(_foundUser!.avatarUrl!),
                        radius: 24,
                      )
                    else
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _foundUser!.username,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _querySearchController.text.trim(),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : (_foundUser != null ? _startChatting : _lookupUser),
                icon: Icon(
                  _foundUser != null ? Icons.chat : Icons.search,
                  size: 18,
                ),
                label: Text(
                  _foundUser != null ? 'Start Chatting' : 'Find User',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
