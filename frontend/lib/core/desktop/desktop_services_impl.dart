import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_tray/system_tray.dart';
import 'package:talktime/core/config/environment.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger();

const String _prefsHotkeyMic = 'hotkey_mic_toggle';
const String _prefsHotkeyPtt = 'hotkey_ptt';
const String _prefsHotkeySpeaker = 'hotkey_speaker';

/// Defaults use Super (Windows/Meta key) - most likely to work on Linux (keybinder often rejects Ctrl+Alt).
HotKey? _defaultHotKeyMic() => HotKey(
  key: PhysicalKeyboardKey.keyM,
  modifiers: [HotKeyModifier.alt, HotKeyModifier.control],
  scope: HotKeyScope.system,
);
HotKey? _defaultHotKeyPtt() => null;
HotKey? _defaultHotKeySpeaker() => HotKey(
  key: PhysicalKeyboardKey.keyS,
  modifiers: [HotKeyModifier.alt, HotKeyModifier.control],
  scope: HotKeyScope.system,
);

/// On Linux, keybinder is X11-only. On Wayland every binding fails.
bool get _isLinuxWayland {
  if (!Platform.isLinux) return false;
  final env = Platform.environment;
  return env['GDK_BACKEND'] != "x11" &&
      (env['WAYLAND_DISPLAY'] != null ||
          env['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland');
}

/// True if global shortcuts can work on this session (false on Linux under Wayland).
bool get isGlobalShortcutsSupported {
  if (Platform.isWindows || Platform.isMacOS) return true;
  if (Platform.isLinux) return !_isLinuxWayland;
  return false;
}

Future<void> initDesktopServices() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return;
  }

  if (_isLinuxWayland) {
    _logger.w(
      'Global shortcuts are not available on Wayland (keybinder is X11-only). '
      'Run with GDK_BACKEND=x11 or use an X11 session to use shortcuts.',
    );
    // Still try to init tray on Linux if not Wayland
  } else {
    try {
      await hotKeyManager.unregisterAll();
      await _registerHotKeys();
    } catch (e, st) {
      _logger.e('Desktop services init failed: $e', error: e, stackTrace: st);
    }
  }

  // System tray: Windows and macOS (Linux needs appindicator, may fail to build)
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await _initSystemTray();
    } catch (e, st) {
      _logger.e('System tray init failed: $e', error: e, stackTrace: st);
    }
  }
}

Future<void> _initSystemTray() async {
  final iconPath = Platform.isWindows
      ? 'assets/app_icon.ico'
      : 'assets/app_icon.png';
  final SystemTray systemTray = SystemTray();

  await systemTray.initSystemTray(
    title: Environment.appName,
    iconPath: iconPath,
    toolTip: Environment.appName,
  );

  final Menu menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(
      label: 'Show ${Environment.appName}',
      onClicked: (_) async {
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (e) {
          _logger.w('Failed to show window: $e');
        }
      },
    ),
    MenuItemLabel(label: 'Quit', onClicked: (_) => exit(0)),
  ]);
  await systemTray.setContextMenu(menu);

  systemTray.registerSystemTrayEventHandler((eventName) {
    if (eventName == kSystemTrayEventClick) {
      if (Platform.isWindows) {
        windowManager.show().then((_) => windowManager.focus());
      } else {
        systemTray.popUpContextMenu();
      }
    } else if (eventName == kSystemTrayEventRightClick) {
      if (Platform.isWindows) {
        systemTray.popUpContextMenu();
      } else {
        windowManager.show().then((_) => windowManager.focus());
      }
    }
  });

  _logger.i('System tray initialized');
}

/// Call after user changes hotkeys in settings so new bindings take effect.
Future<void> reRegisterHotKeys() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return;
  }
  if (_isLinuxWayland) return;
  try {
    await hotKeyManager.unregisterAll();
    await _registerHotKeys();
    _logger.i('Hotkeys re-registered from settings');
  } catch (e, st) {
    _logger.e('Re-register hotkeys failed: $e', error: e, stackTrace: st);
  }
}

Future<HotKey?> _loadHotKey(String prefsKey, HotKey? defaultKey) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(prefsKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return HotKey.fromJson(map);
    }
  } catch (e) {
    _logger.w('Load hotkey $prefsKey failed: $e');
  }
  return defaultKey;
}

Future<void> _registerHotKeys() async {
  final callService = CallService();

  final hotKeyMic = await _loadHotKey(_prefsHotkeyMic, _defaultHotKeyMic());
  final hotKeyPtt = await _loadHotKey(_prefsHotkeyPtt, _defaultHotKeyPtt());
  final hotKeySpeaker = await _loadHotKey(
    _prefsHotkeySpeaker,
    _defaultHotKeySpeaker(),
  );
  var lastPress = DateTime.now();

  if (hotKeyMic != null) {
    await hotKeyManager.register(
      hotKeyMic,
      keyDownHandler: (_) {
        if (DateTime.now().difference(lastPress).inMilliseconds < 40) {
          return;
        }
        lastPress = DateTime.now();
        _logger.d('Hotkey hotKeyMic pressed');
        if (callService.currentState != CallState.idle) {
          callService.toggleMic();
        }
      },
    );
  }

  if (hotKeyPtt != null) {
    await hotKeyManager.register(
      hotKeyPtt,
      keyDownHandler: (_) {
        _logger.d('Hotkey hotKeyPtt pressed');
        if (callService.currentState != CallState.idle && callService.isMuted) {
          callService.toggleMic(forceValue: true); // unmute
        }
      },
      keyUpHandler: (_) {
        _logger.d('Hotkey keyUpHandler pressed');
        if (callService.currentState != CallState.idle &&
            !callService.isMuted) {
          callService.toggleMic(forceValue: false); // mute
        }
      },
    );
  }

  if (hotKeySpeaker != null) {
    await hotKeyManager.register(
      hotKeySpeaker,
      keyDownHandler: (_) {
        if (DateTime.now().difference(lastPress).inMilliseconds < 40) {
          return;
        }
        lastPress = DateTime.now();
        _logger.d('Hotkey hotKeySpeaker pressed');
        if (callService.currentState != CallState.idle) {
          callService.toggleSpeakerMute();
        }
      },
    );
  }

  _logger.i(
    'Global hotkeys: mic=${hotKeyMic?.debugName}, ptt=${hotKeyPtt?.debugName}, speaker=${hotKeySpeaker?.debugName}',
  );
}

/// Returns the current or default hotkeys for the settings UI.
Future<HotKey?> getHotkeyMicToggle() async =>
    _loadHotKey(_prefsHotkeyMic, _defaultHotKeyMic());
Future<HotKey?> getHotkeyPtt() async =>
    _loadHotKey(_prefsHotkeyPtt, _defaultHotKeyPtt());
Future<HotKey?> getHotkeySpeaker() async =>
    _loadHotKey(_prefsHotkeySpeaker, _defaultHotKeySpeaker());

/// Saves a hotkey and re-registers. Call from settings page.
Future<void> setHotkeyMicToggle(HotKey hotKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsHotkeyMic, jsonEncode(hotKey.toJson()));
  await reRegisterHotKeys();
}

Future<void> setHotkeyPtt(HotKey hotKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsHotkeyPtt, jsonEncode(hotKey.toJson()));
  await reRegisterHotKeys();
}

Future<void> setHotkeySpeaker(HotKey hotKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsHotkeySpeaker, jsonEncode(hotKey.toJson()));
  await reRegisterHotKeys();
}

/// Reset to default bindings (Ctrl+Alt+M, Ctrl+Alt+Space, Ctrl+Alt+S).
Future<void> resetHotKeysToDefault() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_prefsHotkeyMic);
  await prefs.remove(_prefsHotkeyPtt);
  await prefs.remove(_prefsHotkeySpeaker);
  await reRegisterHotKeys();
}
