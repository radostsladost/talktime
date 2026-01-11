import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:talktime/features/call/data/signaling_service.dart';

/// Incoming call screen displayed when receiving a call
class IncomingCallPage extends StatefulWidget {
  final String callId;
  final String callerName;
  final String? callerAvatarUrl;
  final String callType; // 'video' or 'audio'
  final String? roomId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallPage({
    super.key,
    required this.callId,
    required this.callerName,
    this.callerAvatarUrl,
    required this.callType,
    this.roomId,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _ringController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _ringAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the avatar
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Ring animation for the ripple effect
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _ringAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ringController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideoCall = widget.callType.toLowerCase() == 'video';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    const Color(0xFF1A1A2E),
                    const Color(0xFF16213E),
                    const Color(0xFF0F3460),
                  ]
                : [
                    const Color(0xFF667eea),
                    const Color(0xFF764ba2),
                    const Color(0xFF6B8DD6),
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 1),

              // Call type indicator
              _buildCallTypeIndicator(isVideoCall),
              const SizedBox(height: 16),

              // "Incoming call" text
              Text(
                'Incoming ${isVideoCall ? 'Video' : 'Voice'} Call',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 40),

              // Animated avatar with ripple effect
              _buildAnimatedAvatar(),
              const SizedBox(height: 24),

              // Caller name
              Text(
                widget.callerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Calling status
              _buildCallingIndicator(),

              const Spacer(flex: 2),

              // Action buttons
              _buildActionButtons(),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallTypeIndicator(bool isVideoCall) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideoCall ? Icons.videocam : Icons.call,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            isVideoCall ? 'Video Call' : 'Voice Call',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedAvatar() {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple rings
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _ringAnimation,
              builder: (context, child) {
                final delay = index * 0.3;
                final animValue = (_ringAnimation.value + delay) % 1.0;
                return Container(
                  width: 140 + (60 * animValue),
                  height: 140 + (60 * animValue),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3 * (1 - animValue)),
                      width: 2,
                    ),
                  ),
                );
              },
            );
          }),

          // Pulsing avatar
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child:
                  widget.callerAvatarUrl != null &&
                      widget.callerAvatarUrl!.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        widget.callerAvatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildAvatarPlaceholder(),
                      ),
                    )
                  : _buildAvatarPlaceholder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    final initial = widget.callerName.isNotEmpty
        ? widget.callerName[0].toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade400, Colors.purple.shade400],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 56,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCallingIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDot(0),
        const SizedBox(width: 4),
        _buildDot(1),
        const SizedBox(width: 4),
        _buildDot(2),
      ],
    );
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _ringController,
      builder: (context, child) {
        final delay = index * 0.2;
        final animValue = ((_ringController.value + delay) % 1.0);
        final opacity = (math.sin(animValue * math.pi) * 0.5 + 0.5);

        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(opacity),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline button
          _buildCallButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            label: 'Decline',
            onPressed: widget.onDecline,
          ),

          // Accept button
          _buildCallButton(
            icon: widget.callType.toLowerCase() == 'video'
                ? Icons.videocam
                : Icons.call,
            backgroundColor: Colors.green,
            label: 'Accept',
            onPressed: widget.onAccept,
          ),
        ],
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color backgroundColor,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          elevation: 8,
          shadowColor: backgroundColor.withOpacity(0.5),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
