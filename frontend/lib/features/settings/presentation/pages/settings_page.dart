import 'package:flutter/material.dart';
import 'package:talktime/features/profile/presentation/pages/edit_profile_page.dart';
import 'package:talktime/features/settings/data/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();

  ThemeMode _themeMode = ThemeMode.system;
  Color _colorSeed = Colors.blue;
  bool _notificationsEnabled = true;
  bool _notificationSound = true;
  bool _notificationVibration = true;
  bool _messagePreview = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final themeMode = await _settingsService.getThemeMode();
    final colorSeed = await _settingsService.getColorSeed();
    final notificationsEnabled = await _settingsService
        .getNotificationsEnabled();
    final notificationSound = await _settingsService.getNotificationSound();
    final notificationVibration = await _settingsService
        .getNotificationVibration();
    final messagePreview = await _settingsService.getMessagePreview();

    if (!mounted) return;
    setState(() {
      _themeMode = themeMode;
      _colorSeed = colorSeed;
      _notificationsEnabled = notificationsEnabled;
      _notificationSound = notificationSound;
      _notificationVibration = notificationVibration;
      _messagePreview = messagePreview;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // --- Profile Section ---
                _buildSectionHeader('Profile'),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Edit profile'),
                  subtitle: const Text('Username, avatar, bio'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const EditProfilePage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // --- Appearance Section ---
                _buildSectionHeader('Appearance'),
                _buildThemeModeTile(),
                const Divider(height: 1),
                _buildColorSchemeTile(),
                const SizedBox(height: 8),

                // --- Notifications Section ---
                _buildSectionHeader('Notifications'),
                SwitchListTile(
                  title: const Text('Enable Notifications'),
                  subtitle: const Text('Receive push notifications'),
                  secondary: const Icon(Icons.notifications_outlined),
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() => _notificationsEnabled = value);
                    _settingsService.setNotificationsEnabled(value);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Notification Sound'),
                  subtitle: const Text('Play sound for new messages'),
                  secondary: const Icon(Icons.volume_up_outlined),
                  value: _notificationSound,
                  onChanged: _notificationsEnabled
                      ? (value) {
                          setState(() => _notificationSound = value);
                          _settingsService.setNotificationSound(value);
                        }
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Vibration'),
                  subtitle: const Text('Vibrate for new messages'),
                  secondary: const Icon(Icons.vibration),
                  value: _notificationVibration,
                  onChanged: _notificationsEnabled
                      ? (value) {
                          setState(() => _notificationVibration = value);
                          _settingsService.setNotificationVibration(value);
                        }
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Message Preview'),
                  subtitle: const Text('Show message content in notifications'),
                  secondary: const Icon(Icons.chat_bubble_outline),
                  value: _messagePreview,
                  onChanged: _notificationsEnabled
                      ? (value) {
                          setState(() => _messagePreview = value);
                          _settingsService.setMessagePreview(value);
                        }
                      : null,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildThemeModeTile() {
    return ListTile(
      leading: Icon(
        _themeMode == ThemeMode.dark
            ? Icons.dark_mode
            : _themeMode == ThemeMode.light
            ? Icons.light_mode
            : Icons.brightness_auto,
      ),
      title: const Text('Theme'),
      subtitle: Text(_themeModeLabel(_themeMode)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemePicker(),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'System default';
    }
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Choose Theme',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('System default'),
              subtitle: const Text('Follow device settings'),
              secondary: const Icon(Icons.brightness_auto),
              value: ThemeMode.system,
              groupValue: _themeMode,
              onChanged: (value) => _setThemeMode(value!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              secondary: const Icon(Icons.light_mode),
              value: ThemeMode.light,
              groupValue: _themeMode,
              onChanged: (value) => _setThemeMode(value!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              secondary: const Icon(Icons.dark_mode),
              value: ThemeMode.dark,
              groupValue: _themeMode,
              onChanged: (value) => _setThemeMode(value!),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _setThemeMode(ThemeMode mode) {
    Navigator.pop(context);
    setState(() => _themeMode = mode);
    _settingsService.setThemeMode(mode);
  }

  Widget _buildColorSchemeTile() {
    return ListTile(
      leading: CircleAvatar(backgroundColor: _colorSeed, radius: 16),
      title: const Text('Color Scheme'),
      subtitle: Text(
        SettingsService.colorOptions
                .where((o) => o.color.value == _colorSeed.value)
                .firstOrNull
                ?.name ??
            'Custom',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showColorPicker(),
    );
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Choose Color',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: SettingsService.colorOptions.map((option) {
                  final isSelected = option.color.value == _colorSeed.value;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _colorSeed = option.color);
                      _settingsService.setColorSeed(option.color);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: option.color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    width: 3,
                                  )
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: option.color.withOpacity(0.4),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 24,
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.name,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
