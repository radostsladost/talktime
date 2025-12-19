// Example integration file showing how to use the calling features in TalkTime
// This file demonstrates best practices for integrating calls into your app

import 'package:flutter/material.dart';
import 'package:talktime/features/call/data/call_manager.dart';
import 'package:talktime/features/call/presentation/pages/call_page.dart';

/// Example: Initialize CallManager after user login
class LoginSuccessExample {
  Future<void> handleLoginSuccess(BuildContext context) async {
    // After successful login, initialize the call manager
    // This enables receiving incoming calls
    try {
      await CallManager().initialize(context);
      print('CallManager initialized successfully');
    } catch (e) {
      print('Failed to initialize CallManager: $e');
      // Continue anyway - calling features will be disabled
    }
  }
}

/// Example: Make an outgoing call from a chat/conversation screen
class ChatScreenExample extends StatelessWidget {
  final String userId;
  final String username;

  const ChatScreenExample({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(username),
        actions: [
          // Audio call button
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _makeAudioCall(context),
          ),
          // Video call button
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _makeVideoCall(context),
          ),
        ],
      ),
      body: const Center(child: Text('Chat messages go here')),
    );
  }

  Future<void> _makeAudioCall(BuildContext context) async {
    try {
      await CallManager().initiateCall(
        context: context,
        peerId: userId,
        peerName: username,
        callType: CallType.audio,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start call: $e')));
      }
    }
  }

  Future<void> _makeVideoCall(BuildContext context) async {
    try {
      await CallManager().initiateCall(
        context: context,
        peerId: userId,
        peerName: username,
        callType: CallType.video,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start call: $e')));
      }
    }
  }
}

/// Example: Direct navigation to call page (alternative method)
class DirectCallExample {
  void makeDirectVideoCall(
    BuildContext context,
    String userId,
    String userName,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallPage(
          isOutgoing: true,
          peerName: userName,
          peerId: userId,
          callType: CallType.video,
        ),
      ),
    );
  }

  void makeDirectAudioCall(
    BuildContext context,
    String userId,
    String userName,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallPage(
          isOutgoing: true,
          peerName: userName,
          peerId: userId,
          callType: CallType.audio,
        ),
      ),
    );
  }
}

/// Example: Handle logout - clean up CallManager
class LogoutExample {
  Future<void> handleLogout() async {
    // Dispose CallManager to disconnect SignalR and clean up resources
    await CallManager().dispose();
    print('CallManager disposed');
  }
}

/// Example: Update context when navigating between screens
class NavigationExample extends StatefulWidget {
  const NavigationExample({super.key});

  @override
  State<NavigationExample> createState() => _NavigationExampleState();
}

class _NavigationExampleState extends State<NavigationExample> {
  @override
  void initState() {
    super.initState();
    // Update CallManager context so incoming calls show on current screen
    if (CallManager().isInitialized) {
      CallManager().updateContext(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navigation Example')),
      body: const Center(child: Text('Screen content')),
    );
  }
}

/// Example: Main app with app lifecycle handling
class MainAppExample extends StatefulWidget {
  const MainAppExample({super.key});

  @override
  State<MainAppExample> createState() => _MainAppExampleState();
}

class _MainAppExampleState extends State<MainAppExample>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground - reconnect if needed
      if (CallManager().isInitialized && !CallManager().isConnected) {
        CallManager().reconnect().catchError((error) {
          print('Failed to reconnect CallManager: $error');
        });
      }
    } else if (state == AppLifecycleState.paused) {
      // App went to background
      // CallManager will maintain connection
      // For battery optimization, you might disconnect here
      // but you won't receive incoming calls
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'TalkTime', home: const HomeScreen());
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TalkTime')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Show connection status
            FutureBuilder<bool>(
              future: Future.value(CallManager().isConnected),
              builder: (context, snapshot) {
                final isConnected = snapshot.data ?? false;
                return Chip(
                  avatar: Icon(
                    Icons.circle,
                    color: isConnected ? Colors.green : Colors.red,
                    size: 12,
                  ),
                  label: Text(isConnected ? 'Connected' : 'Disconnected'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Example: Contact list with call buttons
class ContactListExample extends StatelessWidget {
  final List<Contact> contacts = [
    Contact(id: '1', name: 'Alice Johnson', avatarUrl: null),
    Contact(id: '2', name: 'Bob Smith', avatarUrl: null),
    Contact(id: '3', name: 'Charlie Brown', avatarUrl: null),
  ];

  ContactListExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: ListView.builder(
        itemCount: contacts.length,
        itemBuilder: (context, index) {
          final contact = contacts[index];
          return ListTile(
            leading: CircleAvatar(child: Text(contact.name[0])),
            title: Text(contact.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: () =>
                      _callContact(context, contact, CallType.audio),
                  tooltip: 'Audio call',
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: Colors.blue),
                  onPressed: () =>
                      _callContact(context, contact, CallType.video),
                  tooltip: 'Video call',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _callContact(
    BuildContext context,
    Contact contact,
    CallType callType,
  ) async {
    try {
      await CallManager().initiateCall(
        context: context,
        peerId: contact.id,
        peerName: contact.name,
        callType: callType,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class Contact {
  final String id;
  final String name;
  final String? avatarUrl;

  Contact({required this.id, required this.name, this.avatarUrl});
}

/// Example: Show incoming call as a dialog (alternative to full screen)
/// Note: The CallManager automatically shows full screen, but you could
/// customize this behavior
class IncomingCallDialogExample {
  void showIncomingCallDialog(
    BuildContext context,
    String callerId,
    String callerName,
    String callId,
    CallType callType,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Incoming Call'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 40, child: Text(callerName[0].toUpperCase())),
            const SizedBox(height: 16),
            Text(
              callerName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              callType == CallType.video ? 'Video Call' : 'Voice Call',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Reject call logic here
            },
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to call page
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CallPage(
                    isOutgoing: false,
                    peerName: callerName,
                    peerId: callerId,
                    callId: callId,
                    callType: callType,
                  ),
                ),
              );
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }
}
