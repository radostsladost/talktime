import 'package:flutter/material.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/call/presentation/pages/guest_call_page.dart';

/// Shown when an unauthenticated user opens a deep link to a call.
/// Lets the user enter a display name, then joins the call directly.
class GuestNamePage extends StatefulWidget {
  final String inviteKey;

  const GuestNamePage({super.key, required this.inviteKey});

  @override
  State<GuestNamePage> createState() => _GuestNamePageState();
}

class _GuestNamePageState extends State<GuestNamePage> {
  final _nameController = TextEditingController();
  bool _isJoining = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _joinCall() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }

    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      final deviceId = await WebSocketManager().getOrCreateDeviceId();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GuestCallPage(
            inviteKey: widget.inviteKey,
            displayName: name,
            deviceId: deviceId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isJoining = false;
        _error = 'Failed to join: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.video_call_outlined,
                    size: 80,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Join Call',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your name to join as a guest',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 48),
                  TextField(
                    controller: _nameController,
                    enabled: !_isJoining,
                    autofocus: true,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _joinCall(),
                    decoration: InputDecoration(
                      labelText: 'Your name',
                      hintText: 'Enter your display name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isJoining ? null : _joinCall,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isJoining
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Join Call',
                            style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
