import 'package:flutter/material.dart';

import '../models/mirror_protocol.dart';
import '../theme/app_theme.dart';
import 'device_a_screen.dart';
import 'device_b_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  TransportMode _selectedMode = TransportMode.webSocket;

  @override
  Widget build(BuildContext context) {
    final isWebSocket = _selectedMode == TransportMode.webSocket;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight-50),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: isWebSocket ? AppColors.cyanGradient : AppColors.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: (isWebSocket ? AppColors.secondary : AppColors.primary).withValues(alpha: 0.5),
                                  blurRadius: 25,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              isWebSocket ? Icons.lan_rounded : Icons.cloud_done_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Live Screen Mirroring\n& Gesture Sync',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isWebSocket
                              ? 'Detect live taps & drags on Device A and mirror in real-time over Local Wi-Fi / IP WebSocket (Mobile, Web Browser, or Desktop).'
                              : 'Detect live taps & drags on Device A and sync over Firebase Cloud Firestore across any internet network.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildModeTab(
                                  mode: TransportMode.webSocket,
                                  label: 'WebSocket (IP)',
                                  icon: Icons.wifi_rounded,
                                  color: AppColors.secondary,
                                ),
                              ),
                              Expanded(
                                child: _buildModeTab(
                                  mode: TransportMode.firebase,
                                  label: 'Firebase (Cloud)',
                                  icon: Icons.cloud_outlined,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildRoleCard(
                          context,
                          title: isWebSocket ? 'Device A: WebSocket Broadcaster' : 'Device A: Firebase Broadcaster',
                          subtitle: isWebSocket
                              ? 'Start local IP WebSocket server (ws://ip:port) and host built-in Web Viewer for web browsers.'
                              : 'Stream screen frames and capture live touch/scroll gestures via Firebase Cloud Firestore.',
                          badgeText: isWebSocket ? 'HOST / SENDER (LOCAL IP)' : 'HOST / SENDER (FIREBASE CLOUD)',
                          badgeColor: isWebSocket ? AppColors.secondary : AppColors.primary,
                          icon: Icons.phonelink_setup_rounded,
                          gradient: isWebSocket ? AppColors.cyanGradient : AppColors.primaryGradient,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DeviceABroadcasterScreen(transportMode: _selectedMode),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildRoleCard(
                          context,
                          title: isWebSocket ? 'Device B: WebSocket Receiver' : 'Device B: Firebase Receiver',
                          subtitle: isWebSocket
                              ? 'Connect directly using Host IP address (e.g. 192.168.1.50:8080) for high-speed local screening.'
                              : 'Connect via Firebase Channel ID to view Device A screen with live tap ripples and scroll indicators.',
                          badgeText: isWebSocket ? 'VIEWER (WEBSOCKET IP)' : 'VIEWER (FIREBASE CLOUD)',
                          badgeColor: isWebSocket ? AppColors.secondary : AppColors.primary,
                          icon: Icons.desktop_windows_rounded,
                          gradient: isWebSocket ? AppColors.cyanGradient : AppColors.primaryGradient,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DeviceBReceiverScreen(transportMode: _selectedMode),
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isWebSocket ? Icons.bolt_rounded : Icons.cloud_done_rounded,
                              size: 16,
                              color: isWebSocket ? AppColors.secondary : AppColors.success,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isWebSocket
                                  ? 'WebSocket IP Direct Mode • Ultra Low Latency'
                                  : 'Powered by Firebase Cloud Firestore Sync',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary.withValues(alpha: 0.8),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required TransportMode mode,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMode = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: color.withValues(alpha: 0.6)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? color : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 30, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
