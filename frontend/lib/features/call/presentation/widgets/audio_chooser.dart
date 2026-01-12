import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class AudioDeviceChooser extends StatefulWidget {
  final ValueChanged<MediaDeviceInfo> onDeviceSelected;

  const AudioDeviceChooser({super.key, required this.onDeviceSelected});

  @override
  State<AudioDeviceChooser> createState() => _AudioDeviceChooserState();
}

class _AudioDeviceChooserState extends State<AudioDeviceChooser> {
  List<MediaDeviceInfo> _devices = [];
  MediaDeviceInfo? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      // Get microphone devices
      final devices = await Helper.enumerateDevices("audioinput");
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
    return DropdownButtonFormField<MediaDeviceInfo>(
      value: _selectedDevice,
      items: _devices.map((device) {
        return DropdownMenuItem<MediaDeviceInfo>(
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
