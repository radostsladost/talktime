import 'package:audioplayers/audioplayers.dart';

class UiSoundPlayer {
  UiSoundPlayer() {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final AudioPlayer _player = AudioPlayer();

  Future<void> play(String assetName) async {
    await _player.stop();
    await _player.play(AssetSource(assetName));
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

UiSoundPlayer createUiSoundPlayer() => UiSoundPlayer();

