import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_theme.dart';
import '../bloc/chat_bloc.dart';

/// Reasoning Steps Widget
/// 
/// Shows the AI's thinking process like modern AI apps (DeepSeek, o1, etc.)
/// Collapsible with smooth animations.
class ReasoningStepsWidget extends StatelessWidget {
  final List<ReasoningStep> steps;
  final bool isExpanded;
  final bool isLive;  // Still generating
  final VoidCallback? onToggle;
  
  const ReasoningStepsWidget({
    super.key,
    required this.steps,
    this.isExpanded = false,
    this.isLive = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.darkCard.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive ? AppTheme.primary.withOpacity(0.5) : AppTheme.darkBorder,
          width: isLive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - always visible
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Thinking icon with animation
                  if (isLive)
                    _buildThinkingIndicator()
                  else
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.psychology,
                        color: AppTheme.primary,
                        size: 16,
                      ),
                    ),
                  const SizedBox(width: 8),
                  
                  // Title
                  Expanded(
                    child: Text(
                      isLive ? 'Thinking...' : 'Thought for ${_formatDuration()}',
                      style: TextStyle(
                        color: isLive ? AppTheme.primary : AppTheme.textSecondaryDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  
                  // Step count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${steps.length} steps',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 4),
                  
                  // Expand/collapse icon
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppTheme.textSecondaryDark,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded content
          if (isExpanded) ...[
            const Divider(height: 1, color: AppTheme.darkBorder),
            _buildStepsList(),
          ],
        ],
      ),
    );
  }
  
  Widget _buildThinkingIndicator() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.psychology,
        color: AppTheme.primary,
        size: 16,
      ),
    ).animate(onPlay: (c) => c.repeat())
      .shimmer(duration: 1200.ms, color: AppTheme.primary.withOpacity(0.3));
  }
  
  Widget _buildStepsList() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < steps.length; i++)
            _buildStepItem(steps[i], i, i == steps.length - 1),
        ],
      ),
    );
  }
  
  Widget _buildStepItem(ReasoningStep step, int index, bool isLast) {
    final hasAction = step.action != null;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: step.isComplete 
                    ? AppTheme.success.withOpacity(0.2) 
                    : AppTheme.primary.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: step.isComplete ? AppTheme.success : AppTheme.primary,
                  width: 2,
                ),
              ),
              child: Icon(
                step.isComplete 
                    ? Icons.check 
                    : hasAction 
                        ? Icons.search 
                        : Icons.lightbulb_outline,
                color: step.isComplete ? AppTheme.success : AppTheme.primary,
                size: 10,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 30,
                color: AppTheme.darkBorder,
              ),
          ],
        ),
        const SizedBox(width: 12),
        
        // Step content
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thought
                Text(
                  step.thought,
                  style: const TextStyle(
                    color: AppTheme.textPrimaryDark,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                
                // Action badge (if tool was called)
                if (hasAction) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.storage,
                          color: Colors.orange,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatAction(step.action!),
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Observation (result)
                if (step.observation != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    step.observation!,
                    style: TextStyle(
                      color: AppTheme.textSecondaryDark,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: (index * 100).ms, duration: 200.ms);
  }
  
  String _formatDuration() {
    if (steps.isEmpty) return '0s';
    final first = steps.first.timestamp;
    final last = steps.last.timestamp;
    final diff = last.difference(first);
    if (diff.inSeconds < 1) return '<1s';
    return '${diff.inSeconds}s';
  }
  
  String _formatAction(String action) {
    return action.replaceAll('_', ' ').split(' ').map((w) => 
      w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w
    ).join(' ');
  }
}

/// Live reasoning indicator shown at bottom of chat during generation
class LiveReasoningIndicator extends StatelessWidget {
  final List<ReasoningStep> steps;
  final VoidCallback? onStop;
  
  const LiveReasoningIndicator({
    super.key,
    required this.steps,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.1),
            AppTheme.accent.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with stop button
          Row(
            children: [
              // Animated brain icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology,
                  color: Colors.white,
                  size: 20,
                ),
              ).animate(onPlay: (c) => c.repeat())
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.1, 1.1),
                  duration: 600.ms,
                )
                .then()
                .scale(
                  begin: const Offset(1.1, 1.1),
                  end: const Offset(1, 1),
                  duration: 600.ms,
                ),
              const SizedBox(width: 12),
              
              // Status text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI is thinking...',
                      style: TextStyle(
                        color: AppTheme.textPrimaryDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      steps.isNotEmpty ? steps.last.thought : 'Processing...',
                      style: TextStyle(
                        color: AppTheme.textSecondaryDark,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Stop button
              if (onStop != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onStop,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.stop, color: AppTheme.error, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Stop',
                            style: TextStyle(
                              color: AppTheme.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          
          // Progress indicator
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              backgroundColor: AppTheme.darkBorder,
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
          
          // Step count
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.timeline, size: 14, color: AppTheme.textSecondaryDark),
                const SizedBox(width: 4),
                Text(
                  '${steps.length} reasoning steps',
                  style: TextStyle(
                    color: AppTheme.textSecondaryDark,
                    fontSize: 11,
                  ),
                ),
                if (steps.any((s) => s.action != null)) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.storage, size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    '${steps.where((s) => s.action != null).length} DB queries',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.2, end: 0);
  }
}
