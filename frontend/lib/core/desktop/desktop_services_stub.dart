// Stub for platforms where desktop services are not used (web).
// The real implementation is in desktop_services_impl.dart (used when dart.library.io exists).

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

Future<void> initDesktopServices() async {}

Future<void> reRegisterHotKeys() async {}

Future<HotKey> getHotkeyMicToggle() async => HotKey(
      key: PhysicalKeyboardKey.keyM,
      modifiers: [HotKeyModifier.meta],
      scope: HotKeyScope.system,
    );

Future<HotKey> getHotkeyPtt() async => HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.meta],
      scope: HotKeyScope.system,
    );

Future<HotKey> getHotkeySpeaker() async => HotKey(
      key: PhysicalKeyboardKey.keyS,
      modifiers: [HotKeyModifier.meta],
      scope: HotKeyScope.system,
    );

Future<void> setHotkeyMicToggle(HotKey hotKey) async {}

Future<void> setHotkeyPtt(HotKey hotKey) async {}

Future<void> setHotkeySpeaker(HotKey hotKey) async {}

Future<void> resetHotKeysToDefault() async {}

bool get isGlobalShortcutsSupported => true;
