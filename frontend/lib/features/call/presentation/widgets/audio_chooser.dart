import 'package:flutter/material.dart';
import 'package:talktime/features/call/webrtc/webrtc_platform.dart';

class AudioDeviceChooser extends StatefulWidget {
  final ValueChanged<MediaDeviceInfoDto> onDeviceSelected;

  const AudioDeviceChooser({super.key, required this.onDeviceSelected});

  @override
  State<AudioDeviceChooser> createState() => _AudioDeviceChooserState();
}

class _AudioDeviceChooserState extends State<AudioDeviceChooser> {
  List<MediaDeviceInfoDto> _devices = [];
  MediaDeviceInfoDto? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await getWebRTCPlatform().enumerateDevices('audioinput');
      if (mounted) {
        setState(() {
          _devices = devices;
          if (_selectedDevice == null && devices.isNotEmpty) {
            _selectedDevice = devices.first;
            widget.onDeviceSelected(_selectedDevice!);
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load audio devices: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<MediaDeviceInfoDto>(
      value: _selectedDevice,
      items: _devices.map((device) {
        return DropdownMenuItem<MediaDeviceInfoDto>(
          value: device,
          child: Text(device.label),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _selectedDevice = value;
          });
          widget.onDeviceSelected(value);
        }
      },
      decoration: const InputDecoration(
        labelText: 'Microphone',
        border: OutlineInputBorder(),
      ),
      isExpanded: true,
    );
  }
}
