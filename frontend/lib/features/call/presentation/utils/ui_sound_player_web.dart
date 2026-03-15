import 'dart:js_interop';

import 'package:web/web.dart' as web;

class UiSoundPlayer {
  final web.HTMLAudioElement _audio = web.HTMLAudioElement()..preload = 'auto';

  String _resolveAssetPath(String assetName) {
    final normalized = assetName.startsWith('assets/')
        ? assetName
        : 'assets/$assetName';
    return '/assets/$normalized';
  }

  Future<void> play(String assetName) async {
    _audio.pause();

    _audio
      ..src = _resolveAssetPath(assetName)
      ..currentTime = 0;

    try {
      await _audio.play().toDart;
    } catch (_) {
      // Ignore browser play interruption/autoplay rejections for short UI sounds.
    }
  }

  Future<void> dispose() async {
    _audio.pause();
    _audio.currentTime = 0;
  }
}

UiSoundPlayer createUiSoundPlayer() => UiSoundPlayer();




