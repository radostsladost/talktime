import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
              ],
            ),
          );
        },
      ),
    );
  }
}
