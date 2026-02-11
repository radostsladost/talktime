import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:talktime/core/desktop/desktop_services.dart';
import 'package:talktime/core/platform_utils.dart';

class HotkeysSettingsPage extends StatefulWidget {
  const HotkeysSettingsPage({super.key});

  @override
  State<HotkeysSettingsPage> createState() => _HotkeysSettingsPageState();
}

enum _RecordingSlot { mic, ptt, speaker }

class _HotkeysSettingsPageState extends State<HotkeysSettingsPage> {
  bool _isDesktop = isDesktop;
  bool _shortcutsSupported = true;
  bool _loading = true;
  HotKey? _hotKeyMic;
  HotKey? _hotKeyPtt;
  HotKey? _hotKeySpeaker;
  String? _error;
  _RecordingSlot? _recordingSlot;

  /// Only commit when the main key is not a modifier (avoids saving "Ctrl" alone).
  static bool _isModifierOnly(HotKey key) {
    final p = key.physicalKey;
    return HotKeyModifier.values.any((m) => m.physicalKeys.contains(p));
  }

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      _shortcutsSupported = isGlobalShortcutsSupported;
      _loadHotkeys();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadHotkeys() async {
    try {
      final mic = await getHotkeyMicToggle();
      final ptt = await getHotkeyPtt();
      final speaker = await getHotkeySpeaker();
      if (mounted) {
        setState(() {
          _hotKeyMic = mic;
          _hotKeyPtt = ptt;
          _hotKeySpeaker = speaker;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _resetToDefault() async {
    try {
      await resetHotKeysToDefault();
      await _loadHotkeys();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shortcuts reset to Super+M, Super+Space, Super+S'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to reset: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shortcuts')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Global shortcuts are only available on desktop (Windows, Linux, macOS).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shortcuts'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _resetToDefault,
            child: const Text('Reset to default'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : ListView(
              children: [
                if (!_shortcutsSupported) _buildWaylandBanner(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Click a shortcut to change it, then press the new key combination. These work globally when a call is active.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                _buildRow(
                  slot: _RecordingSlot.mic,
                  icon: Icons.mic,
                  label: 'Toggle microphone',
                  subtitle: 'Mute or unmute your microphone',
                  hotKey: _hotKeyMic,
                  onRecorded: (key) async {
                    if (_isModifierOnly(key)) return;
                    await setHotkeyMicToggle(key);
                    if (mounted)
                      setState(() {
                        _hotKeyMic = key;
                        _recordingSlot = null;
                      });
                  },
                ),
                // const Divider(height: 1),
                // _buildRow(
                //   slot: _RecordingSlot.ptt,
                //   icon: Icons.push_pin,
                //   label: 'Push to talk',
                //   subtitle: 'Hold to unmute, release to mute',
                //   hotKey: _hotKeyPtt,
                //   onRecorded: (key) async {
                //     if (_isModifierOnly(key)) return;
                //     await setHotkeyPtt(key);
                //     if (mounted) setState(() {
                //       _hotKeyPtt = key;
                //       _recordingSlot = null;
                //     });
                //   },
                // ),
                const Divider(height: 1),
                _buildRow(
                  slot: _RecordingSlot.speaker,
                  icon: Icons.volume_up,
                  label: 'Toggle speaker',
                  subtitle: 'Mute or unmute remote audio',
                  hotKey: _hotKeySpeaker,
                  onRecorded: (key) async {
                    if (_isModifierOnly(key)) return;
                    await setHotkeySpeaker(key);
                    if (mounted)
                      setState(() {
                        _hotKeySpeaker = key;
                        _recordingSlot = null;
                      });
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildWaylandBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Global shortcuts not available',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'On Linux, global shortcuts require X11. Under Wayland they do not work.\n\n'
            'To use shortcuts: run the app with X11, for example:\n'
            'GDK_BACKEND=x11 ./your_talktime_app\n\n'
            'Or log in to an X11 session instead of Wayland.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required _RecordingSlot slot,
    required IconData icon,
    required String label,
    required String subtitle,
    required HotKey? hotKey,
    required ValueChanged<HotKey> onRecorded,
  }) {
    final isRecording = _recordingSlot == slot;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!_shortcutsSupported) return;
          setState(() => _recordingSlot = isRecording ? null : slot);
        },
        hoverColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        splashColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 220,
                child: isRecording
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Press key combination…',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                        .withOpacity(0.8),
                                  ),
                            ),
                            const SizedBox(height: 4),
                            HotKeyRecorder(
                              initalHotKey: hotKey,
                              onHotKeyRecorded: onRecorded,
                            ),
                          ],
                        ),
                      )
                    : _HotKeyChip(hotKey: hotKey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the current hotkey label; only one row uses HotKeyRecorder at a time.
class _HotKeyChip extends StatelessWidget {
  const _HotKeyChip({required this.hotKey});

  final HotKey? hotKey;

  @override
  Widget build(BuildContext context) {
    if (hotKey == null) {
      return const SizedBox.shrink();
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                hotKey!.debugName,
                style: Theme.of(context).textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.edit_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
