import 'package:flutter/material.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';

/// Full-screen wrapper for a guest joining a call via deep link.
/// Initializes CallService in guest mode and shows the conference page.
/// When the call ends, shows a "call ended" screen instead of navigating
/// back to any authenticated UI.
class GuestCallPage extends StatefulWidget {
  final String inviteKey;
  final String displayName;
  final String deviceId;

  const GuestCallPage({
    super.key,
    required this.inviteKey,
    required this.displayName,
    required this.deviceId,
  });

  @override
  State<GuestCallPage> createState() => _GuestCallPageState();
}

class _GuestCallPageState extends State<GuestCallPage> {
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await CallService().initService(
        isGuest: true,
        guestDeviceId: widget.deviceId,
        guestDisplayName: widget.displayName,
      );

      if (!mounted) return;

      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Joining call...',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Failed to join call',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ConferencePage(
      roomId: widget.inviteKey,
      inviteKey: widget.inviteKey,
      initialParticipants: const [],
      conversation: null,
    );
  }
}
