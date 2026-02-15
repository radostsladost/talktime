import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:talktime/features/call/webrtc/webrtc_platform.dart';

bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

class AudioDevicePopupChooser {
  /// Shows a popup dialog to select an audio input (microphone) device.
  /// Returns the selected [MediaDeviceInfoDto], or null if canceled.
  static Future<MediaDeviceInfoDto?> show({
    required BuildContext context,
    String title = 'Select Microphone',
  }) async {
    return await showDialog<MediaDeviceInfoDto>(
      context: context,
      builder: (context) {
        return _AudioDeviceListDialog(
          title: title,
          kind: 'audioinput',
          icon: Icons.mic,
        );
      },
    );
  }

  /// Shows a popup dialog to select an audio output (speaker) device.
  /// On mobile shows only a speaker on/off toggle.
  /// Returns the selected [MediaDeviceInfoDto], or null if canceled (on mobile, always null).
  static Future<MediaDeviceInfoDto?> showSpeaker({
    required BuildContext context,
    String title = 'Select Speaker',
    bool initialSpeakerOn = true,
    ValueChanged<bool>? onSpeakerToggle,
  }) async {
    if (_isMobile && onSpeakerToggle != null) {
      await showSpeakerToggle(
        context: context,
        title: title,
        initialSpeakerOn: initialSpeakerOn,
        onChanged: onSpeakerToggle,
      );
      return null;
    }
    return await showDialog<MediaDeviceInfoDto>(
      context: context,
      builder: (context) {
        return _AudioDeviceListDialog(
          title: title,
          kind: 'audiooutput',
          icon: Icons.volume_up,
        );
      },
    );
  }

  /// Shows a dialog with only a speaker-phone on/off toggle (for mobile).
  /// [onChanged] is called when the user toggles the switch.
  static Future<void> showSpeakerToggle({
    required BuildContext context,
    String title = 'Speaker',
    required bool initialSpeakerOn,
    required ValueChanged<bool> onChanged,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (context) => _SpeakerToggleDialog(
        title: title,
        initialSpeakerOn: initialSpeakerOn,
        onChanged: onChanged,
      ),
    );
  }
}

// Dialog that shows only speaker on/off toggle (mobile)
class _SpeakerToggleDialog extends StatefulWidget {
  final String title;
  final bool initialSpeakerOn;
  final ValueChanged<bool> onChanged;

  const _SpeakerToggleDialog({
    required this.title,
    required this.initialSpeakerOn,
    required this.onChanged,
  });

  @override
  State<_SpeakerToggleDialog> createState() => _SpeakerToggleDialogState();
}

class _SpeakerToggleDialogState extends State<_SpeakerToggleDialog> {
  late bool _speakerOn;

  @override
  void initState() {
    super.initState();
    _speakerOn = widget.initialSpeakerOn;
  }

  void _onToggle(bool value) {
    setState(() => _speakerOn = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SwitchListTile(
        value: _speakerOn,
        onChanged: _onToggle,
        title: const Text('Speaker phone'),
        subtitle: Text(_speakerOn ? 'Loudspeaker' : 'Earpiece'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// Internal dialog widget
class _AudioDeviceListDialog extends StatefulWidget {
  final String title;
  final String kind; // 'audioinput' or 'audiooutput'
  final IconData icon;

  const _AudioDeviceListDialog({
    required this.title,
    required this.kind,
    required this.icon,
  });

  @override
  State<_AudioDeviceListDialog> createState() => _AudioDeviceListDialogState();
}

class _AudioDeviceListDialogState extends State<_AudioDeviceListDialog> {
  List<MediaDeviceInfoDto> _devices = [];
  MediaDeviceInfoDto? _selectedDevice;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await getWebRTCPlatform().enumerateDevices(widget.kind);
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoading = false;
          if (_selectedDevice == null && devices.isNotEmpty) {
            _selectedDevice = devices.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load audio devices: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _confirmSelection() {
    if (_selectedDevice != null) {
      Navigator.of(context).pop(_selectedDevice);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: min(MediaQuery.sizeOf(context).width * 0.9, 500),
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _devices.isEmpty
            ? Center(
                child: Text(
                  widget.kind == 'audiooutput'
                      ? 'No speakers found.'
                      : 'No microphones found.',
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  final isSelected =
                      _selectedDevice?.deviceId == device.deviceId;

                  return Card(
                    shape: isSelected
                        ? RoundedRectangleBorder(
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    child: ListTile(
                      title: Text(
                        device.label.isEmpty
                            ? '${widget.kind == "audiooutput" ? "Speaker" : "Microphone"} ${index + 1}'
                            : device.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: Icon(
                        widget.icon,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      tileColor: isSelected
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.1)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedDevice = device;
                        });
                      },
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedDevice == null ? null : _confirmSelection,
          child: const Text('Select'),
        ),
      ],
    );
  }
}
