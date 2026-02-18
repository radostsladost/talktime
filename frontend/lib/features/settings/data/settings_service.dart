import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _themeModeKey = 'theme_mode';
  static const String _colorSeedKey = 'color_seed';
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _notificationSoundKey = 'notification_sound';
  static const String _notificationVibrationKey = 'notification_vibration';
  static const String _messagePreviewKey = 'message_preview';
  static const String _callNoiseCancellationKey = 'call_noise_cancellation';

  // Stream controllers for reactive updates
  final _themeModeController = StreamController<ThemeMode>.broadcast();
  final _colorSeedController = StreamController<Color>.broadcast();

  Stream<ThemeMode> get themeModeStream => _themeModeController.stream;
  Stream<Color> get colorSeedStream => _colorSeedController.stream;

  // Available color seeds
  static const List<ColorOption> colorOptions = [
    ColorOption('Blue', Colors.blue),
    ColorOption('Purple', Colors.purple),
    ColorOption('Green', Colors.green),
    ColorOption('Orange', Colors.orange),
    ColorOption('Red', Colors.red),
    ColorOption('Teal', Colors.teal),
    ColorOption('Pink', Colors.pink),
    ColorOption('Indigo', Colors.indigo),
    ColorOption('Cyan', Colors.cyan),
    ColorOption('Amber', Colors.amber),
  ];

  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeModeKey) ?? 'system';
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      default:
        value = 'system';
    }
    await prefs.setString(_themeModeKey, value);
    _themeModeController.add(mode);
  }

  Future<Color> getColorSeed() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_colorSeedKey) ?? Colors.blue.value;
    return Color(value);
  }

  Future<void> setColorSeed(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorSeedKey, color.value);
    _colorSeedController.add(color);
  }

  Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
  }

  Future<bool> getNotificationSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationSoundKey) ?? true;
  }

  Future<void> setNotificationSound(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationSoundKey, enabled);
  }

  Future<bool> getNotificationVibration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationVibrationKey) ?? true;
  }

  Future<void> setNotificationVibration(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationVibrationKey, enabled);
  }

  Future<bool> getMessagePreview() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_messagePreviewKey) ?? true;
  }

  Future<void> setMessagePreview(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_messagePreviewKey, enabled);
  }

  /// Call noise cancellation (PC only). Default true.
  Future<bool> getCallNoiseCancellation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_callNoiseCancellationKey) ?? true;
  }

  Future<void> setCallNoiseCancellation(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_callNoiseCancellationKey, enabled);
  }

  void dispose() {
    _themeModeController.close();
    _colorSeedController.close();
  }
}

class ColorOption {
  final String name;
  final Color color;

  const ColorOption(this.name, this.color);
}
