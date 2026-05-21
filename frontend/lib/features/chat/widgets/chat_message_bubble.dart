import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_theme.dart';
import '../bloc/chat_bloc.dart';
import 'reasoning_steps_widget.dart';

/// Chat Message Bubble
/// 
/// Displays a single message in the chat with:
/// - Reasoning steps (collapsible)
/// - Edit button for user messages
/// - Regenerate button for AI messages
/// - "Why?" explainability button
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onExplainTapped;
  final VoidCallback? onBookmarkToggled;
  final VoidCallback? onReasoningToggled;
  final VoidCallback? onEditTapped;
  final VoidCallback? onRegenerateTapped;
  
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onExplainTapped,
    this.onBookmarkToggled,
    this.onReasoningToggled,
    this.onEditTapped,
    this.onRegenerateTapped,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystemMessage) {
      return _buildSystemMessage(context);
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) _buildAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Reasoning steps for AI messages (before the bubble)
                if (!message.isUser && message.hasReasoning)
                  ReasoningStepsWidget(
                    steps: message.reasoningSteps,
                    isExpanded: message.showReasoning,
                    onToggle: onReasoningToggled,
                  ),
                
                _buildBubble(context),
                
                // Edited indicator
                if (message.isEdited)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '(edited)',
                      style: TextStyle(
                        color: AppTheme.textSecondaryDark.withOpacity(0.5),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                
                // Action row
                _buildActionRow(context),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (message.isUser) _buildUserAvatar(),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(
      begin: 0.1,
      end: 0,
      duration: 200.ms,
      curve: Curves.easeOut,
    );
  }
  
  Widget _buildAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: message.isError
            ? const LinearGradient(colors: [AppTheme.error, Colors.red])
            : message.isExplanation
                ? AppTheme.accentGradient
                : AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        message.isError
            ? Icons.error_outline
            : message.isExplanation
                ? Icons.lightbulb_outline
                : Icons.medical_services_rounded,
        color: Colors.white,
        size: 18,
      ),
    );
  }
  
  Widget _buildUserAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: const Icon(
        Icons.person_outline,
        color: AppTheme.textSecondaryDark,
        size: 18,
      ),
    );
  }
  
  Widget _buildBubble(BuildContext context) {
    final isUser = message.isUser;
    
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isUser
            ? AppTheme.primary.withOpacity(0.15)
            : message.isError
                ? AppTheme.error.withOpacity(0.1)
                : message.isExplanation
                    ? AppTheme.accent.withOpacity(0.1)
                    : AppTheme.darkCard,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        border: Border.all(
          color: isUser
              ? AppTheme.primary.withOpacity(0.3)
              : message.isError
                  ? AppTheme.error.withOpacity(0.3)
                  : message.isExplanation
                      ? AppTheme.accent.withOpacity(0.3)
                      : AppTheme.darkBorder,
          width: 1,
        ),
      ),
      child: SelectableText(
        message.content,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: message.isError
              ? AppTheme.error
              : AppTheme.textPrimaryDark,
          height: 1.5,
        ),
      ),
    );
  }
  
  Widget _buildActionRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          // Timestamp
          Text(
            message.formattedTime,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondaryDark.withOpacity(0.7),
              fontSize: 10,
            ),
          ),
          
          // Inference time for AI messages
          if (!message.isUser && message.inferenceTimeMs != null)
            Text(
              '${message.inferenceTimeMs}ms',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondaryDark,
                fontSize: 10,
              ),
            ),
          
          // Tool calls badge
          if (!message.isUser && message.toolCallsCount != null && message.toolCallsCount! > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${message.toolCallsCount} queries',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 10,
                ),
              ),
            ),
          
          // Edit button for user messages
          if (message.isUser && onEditTapped != null)
            _buildActionButton(
              icon: Icons.edit_outlined,
              label: 'Edit',
              color: AppTheme.textSecondaryDark,
              onTap: onEditTapped!,
            ),
          
          // Regenerate button for AI messages
          if (!message.isUser && !message.isSystemMessage && onRegenerateTapped != null)
            _buildActionButton(
              icon: Icons.refresh,
              label: 'Regenerate',
              color: AppTheme.textSecondaryDark,
              onTap: onRegenerateTapped!,
            ),
          
          // Why button for AI messages
          if (!message.isUser && !message.isSystemMessage && onExplainTapped != null)
            _buildActionButton(
              icon: Icons.help_outline,
              label: 'Why?',
              color: AppTheme.accent,
              onTap: onExplainTapped!,
            ),
          
          // Bookmark button
          if (onBookmarkToggled != null)
            GestureDetector(
              onTap: onBookmarkToggled,
              child: Icon(
                message.isBookmarked 
                    ? Icons.bookmark 
                    : Icons.bookmark_outline,
                size: 14,
                color: message.isBookmarked 
                    ? AppTheme.accent 
                    : AppTheme.textSecondaryDark.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color.withOpacity(0.7)),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSystemMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.success.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppTheme.success,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.content,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn().scale(
      begin: const Offset(0.95, 0.95),
      end: const Offset(1, 1),
    );
  }
}
