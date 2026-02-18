// Desktop-only: capture mic via record, denoise with nnnoiseless, push to native (stub).
// Used when noise cancellation is enabled on Windows/macOS/Linux.

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_nnnoiseless/flutter_nnnoiseless.dart';
import 'package:logger/logger.dart';
import 'package:record/record.dart';
import 'package:talktime/features/call/webrtc/types.dart';

const _methodChannelName = 'org.radostsladost.talktime/noise_cancellation';
const _methodPushPcm = 'pushPcm';

/// RNNoise/nnnoiseless expects fixed-size frames: 480 samples = 10 ms at 48 kHz = 960 bytes.
const int _denoiseFrameBytes = 480 * 2; // 480 samples, 16-bit

/// Use NN denoising on Windows only; on Linux denoiseChunk causes stack overflow (package bug).
bool get _useNnDenoise => Platform.isWindows;

class DesktopNoiseCancellationPipeline {
  DesktopNoiseCancellationPipeline() : _channel = MethodChannel(_methodChannelName);

  final MethodChannel _channel;
  final Logger _logger = Logger(output: ConsoleOutput());

  final AudioRecorder _recorder = AudioRecorder();
  final Noiseless _noiseless = Noiseless.instance;

  StreamSubscription<Uint8List>? _subscription;
  bool _running = false;
  IMediaStreamTrack? _track; // Set when native bridge provides one (not yet).
  final List<int> _inputBuffer = []; // Accumulate bytes until we have full frames.
  Future<void>? _processingFuture;
  Uint8List? _pendingFrame; // At most one; drop older when we can't keep up to bound latency.

  bool get isRunning => _running;

  IMediaStreamTrack? getTrack() => _track;

  /// Starts capturing from mic, denoising each chunk, and pushing to native (stub).
  /// [deviceId] optional; if record supports device selection, use it.
  Future<void> start({String? deviceId}) async {
    if (_running) return;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _logger.w('Desktop NC pipeline: microphone permission not granted');
        return;
      }
      const sampleRate = 48000;
      const numChannels = 1;
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
      );
      final stream = await _recorder.startStream(config);
      _running = true;
      _inputBuffer.clear();
      _subscription = stream.listen(
        (Uint8List chunk) {
          try {
            _inputBuffer.addAll(chunk);
            while (_inputBuffer.length >= _denoiseFrameBytes) {
              final frame = Uint8List.fromList(
                _inputBuffer.take(_denoiseFrameBytes).toList(),
              );
              _inputBuffer.removeRange(0, _denoiseFrameBytes);
              _scheduleFrame(frame);
            }
          } catch (e) {
            _logger.d('Desktop NC buffer error: $e');
          }
        },
        onError: (e) => _logger.e('Desktop NC stream error: $e'),
        onDone: () => _running = false,
        cancelOnError: false,
      );
      _logger.i('Desktop noise cancellation pipeline started');
    } catch (e) {
      _running = false;
      _logger.e('Desktop NC pipeline start failed: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder.stop();
    } catch (e) {
      _logger.d('Desktop NC recorder stop: $e');
    }
    _running = false;
    _logger.i('Desktop noise cancellation pipeline stopped');
  }

  /// Schedules one frame for denoise+push. Keeps at most one pending frame so latency stays bounded.
  void _scheduleFrame(Uint8List frame) {
    if (_processingFuture != null) {
      _pendingFrame = frame;
      return;
    }
    _processingFuture = _processOneFrame(frame);
    _processingFuture!.whenComplete(() {
      _processingFuture = null;
      final next = _pendingFrame;
      _pendingFrame = null;
      if (next != null && _running) _scheduleFrame(next);
    });
  }

  Future<void> _processOneFrame(Uint8List frame) async {
    try {
      final Uint8List toPush = _useNnDenoise
          ? await _noiseless.denoiseChunk(input: frame)
          : frame;
      await _pushPcmToNative(toPush);
    } catch (e) {
      _logger.d('Desktop NC denoise/push error: $e');
    }
  }

  Future<void> _pushPcmToNative(Uint8List pcm) async {
    try {
      await _channel.invokeMethod(_methodPushPcm, {'bytes': pcm});
    } on MissingPluginException {
      // Native bridge not implemented yet; no-op.
    } on PlatformException catch (e) {
      _logger.d('Desktop NC pushPcm: ${e.message}');
    }
  }
}
