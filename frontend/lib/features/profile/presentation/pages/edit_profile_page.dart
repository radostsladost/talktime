import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:talktime/core/navigation_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/auth/presentation/pages/login_page.dart';
import 'package:talktime/features/chat/data/database/database_helper.dart';
import 'package:talktime/features/profile/data/models/profile_privacy.dart';
import 'package:talktime/features/profile/data/profile_service.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:logger/logger.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final ProfileService _userService = ProfileService();
  final Logger _logger = Logger();
  late Future<User> _userFuture;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _allowMessagesFromAnyone = true;
  File? _avatarFile;
  String? _avatarUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _userFuture = _loadUser();
  }

  Future<User> _loadUser() async {
    try {
      final user = await _userService.getCurrentUser();
      _usernameController.text = user.username;
      _bioController.text = user.description ?? '';
      _allowMessagesFromAnyone = true;
      _avatarUrl = user.avatarUrl;
      return user;
    } catch (e) {
      _logger.e('Failed to load user: $e');
      throw e;
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _avatarFile = File(picked.path);
        _avatarUrl = null; // will be replaced after upload
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      User updatedUser = (await _userService.getCurrentUser()).copyWith(
        username: _usernameController.text.trim(),
        description: _bioController.text.trim(),
      );

      // Upload avatar if changed
      if (_avatarFile != null) {
        final newAvatarUrl = await _userService.uploadAvatar(_avatarFile!.path);
        updatedUser = updatedUser.copyWith(avatarUrl: newAvatarUrl);
      }

      await _userService.updateUser(
        username: updatedUser.username,
        description: updatedUser.description,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated!')));
      Navigator.pop(context); // go back
    } catch (e) {
      _logger.e('Save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _saveProfile,
            icon: _isSaving
                ? const CircularProgressIndicator(strokeWidth: 2)
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: FutureBuilder<User>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                // Avatar
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: _avatarFile != null
                            ? FileImage(_avatarFile!)
                            : (_avatarUrl != null
                                      ? NetworkImage(_avatarUrl!)
                                      : null)
                                  as ImageProvider?,
                        backgroundColor: Colors.grey[300],
                        child: (_avatarFile == null && _avatarUrl == null)
                            ? const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: FloatingActionButton.small(
                          heroTag: 'avatar-edit',
                          onPressed: _pickImage,
                          child: const Icon(Icons.edit, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Username
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Bio
                TextField(
                  controller: _bioController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Bio / Description',
                    hintText: 'Tell others about yourself...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Privacy
                ListTile(
                  title: const Text('Privacy'),
                  subtitle: const Text('Who can message you?'),
                  trailing: Switch(
                    value: _allowMessagesFromAnyone,
                    onChanged: (value) {
                      setState(() {
                        _allowMessagesFromAnyone = value;
                      });
                    },
                  ),
                ),
                const Divider(),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '• "Anyone" allows all users to message you.\n'
                    '• "Contacts only" restricts messages to people you’ve chatted with.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),

                // App Settings
                ListTile(
                  leading: Icon(
                    Icons.settings_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('App Settings'),
                  subtitle: const Text('Theme, notifications, and more'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => NavigationManager().openSettings(),
                ),

                // Clear Chats Data Button
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.orange,
                  ),
                  title: const Text('Clear Chats Data'),
                  subtitle: const Text('Delete all local chat history'),
                  onTap: _showClearChatsConfirmation,
                ),

                // Logout Button
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  subtitle: const Text('Sign out from your account'),
                  onTap: _showLogoutConfirmation,
                ),

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showClearChatsConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chats Data'),
        content: const Text(
          'This will delete all local chat history from this device. '
          'Your messages will still be available on the server and other devices.\n\n'
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearChatsData();
    }
  }

  Future<void> _clearChatsData() async {
    try {
      await DatabaseHelper().clearDb();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat data cleared successfully')),
      );
    } catch (e) {
      _logger.e('Failed to clear chats data: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to clear data: $e')));
    }
  }

  Future<void> _showLogoutConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
          'Are you sure you want to logout from your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    try {
      await AuthService().logout();

      if (!mounted) return;

      // Navigate to login screen and clear navigation stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      _logger.e('Logout failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }
}
