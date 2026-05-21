import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/app_theme.dart';
import '../features/chat/bloc/chat_bloc.dart';

/// Privacy Badge
/// 
/// Always-visible trust indicator showing local inference status.
/// - Green shield when local inference active
/// - Tap to show privacy details
/// - Animated pulse on model load
class PrivacyBadge extends StatefulWidget {
  const PrivacyBadge({super.key});

  @override
  State<PrivacyBadge> createState() => _PrivacyBadgeState();
}

class _PrivacyBadgeState extends State<PrivacyBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
  
  void _showPrivacyInfo(BuildContext context, ChatState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _PrivacyInfoSheet(state: state),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        final isSecure = state.isModelReady;
        
        return GestureDetector(
          onTap: () => _showPrivacyInfo(context, state),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = isSecure
                  ? 1.0 + (_pulseController.value * 0.05)
                  : 1.0;
              
              return Transform.scale(
                scale: scale,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSecure
                        ? AppTheme.success.withOpacity(0.15)
                        : AppTheme.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSecure
                          ? AppTheme.success.withOpacity(0.5)
                          : AppTheme.warning.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSecure
                            ? Icons.shield_outlined
                            : Icons.shield_moon_outlined,
                        color: isSecure ? AppTheme.success : AppTheme.warning,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSecure ? 'Local' : 'Loading',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSecure ? AppTheme.success : AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PrivacyInfoSheet extends StatelessWidget {
  final ChatState state;
  
  const _PrivacyInfoSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Shield icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: state.isModelReady
                    ? const LinearGradient(
                        colors: [AppTheme.success, Color(0xFF00C853)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : const LinearGradient(
                        colors: [AppTheme.warning, Colors.orange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (state.isModelReady
                            ? AppTheme.success
                            : AppTheme.warning)
                        .withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield,
                color: Colors.white,
                size: 32,
              ),
            ).animate().scale(
              duration: 300.ms,
              curve: Curves.elasticOut,
            ),
            
            const SizedBox(height: 20),
            
            // Title
            Text(
              state.isModelReady
                  ? 'Local Inference Active'
                  : 'Initializing Local AI',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            
            const SizedBox(height: 8),
            
            Text(
              state.isModelReady
                  ? 'All AI processing happens on your device.\nNo data is sent to external servers.'
                  : 'Please wait while the AI model loads...',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            
            const SizedBox(height: 24),
            
            // Status items
            _buildStatusItem(
              context,
              icon: Icons.memory,
              label: 'AI Model',
              status: state.isModelReady ? 'Ready' : 'Loading',
              isActive: state.isModelReady,
            ),
            const SizedBox(height: 12),
            _buildStatusItem(
              context,
              icon: Icons.storage,
              label: 'Memory Store',
              status: state.isMemoryReady ? 'Ready' : 'Offline',
              isActive: state.isMemoryReady,
            ),
            const SizedBox(height: 12),
            _buildStatusItem(
              context,
              icon: Icons.speed,
              label: 'GPU Acceleration',
              status: state.gpuEnabled ? 'Enabled' : 'Disabled',
              isActive: state.gpuEnabled,
            ),
            
            const SizedBox(height: 24),
            
            // Privacy note
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your health data stays on this device. '
                      'Med Assist App processes everything locally.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String status,
    required bool isActive,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.success.withOpacity(0.1)
                : AppTheme.darkCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isActive ? AppTheme.success : AppTheme.textSecondaryDark,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.success.withOpacity(0.1)
                : AppTheme.darkCard,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? AppTheme.success : AppTheme.textSecondaryDark,
            ),
          ),
        ),
      ],
    );
  }
}
