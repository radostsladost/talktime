// Desktop-only services (global hotkeys, system tray).
// On web, the stub is used; on VM (mobile + desktop) the impl is used.
// The impl only runs hotkey/tray code when Platform.isWindows/Linux/MacOS.

import 'desktop_services_stub.dart'
    if (dart.library.io) 'desktop_services_impl.dart'
    as _desktop;
import 'package:hotkey_manager/hotkey_manager.dart' show HotKey;

export 'package:hotkey_manager/hotkey_manager.dart' show HotKey;

Future<void> initDesktopServices() async {
  await _desktop.initDesktopServices();
}

Future<void> reRegisterHotKeys() async => _desktop.reRegisterHotKeys();

Future<HotKey?> getHotkeyMicToggle() => _desktop.getHotkeyMicToggle();
Future<HotKey?> getHotkeyPtt() => _desktop.getHotkeyPtt();
Future<HotKey?> getHotkeySpeaker() => _desktop.getHotkeySpeaker();

Future<void> setHotkeyMicToggle(HotKey hotKey) =>
    _desktop.setHotkeyMicToggle(hotKey);
Future<void> setHotkeyPtt(HotKey hotKey) => _desktop.setHotkeyPtt(hotKey);
Future<void> setHotkeySpeaker(HotKey hotKey) =>
    _desktop.setHotkeySpeaker(hotKey);

Future<void> resetHotKeysToDefault() => _desktop.resetHotKeysToDefault();

/// False on Linux under Wayland (global shortcuts need X11).
bool get isGlobalShortcutsSupported => _desktop.isGlobalShortcutsSupported;
