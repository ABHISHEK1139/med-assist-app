import 'package:flutter/material.dart';
import '../services/health_archive/ai_memory_commands.dart';

/// Widget to display pending AI storage commands
/// 
/// When AI requests to store data, this widget shows the pending
/// requests and lets user approve/reject them.
/// 
/// GDPR Compliant: User has full control over what gets stored.
class AIMemoryCommandsWidget extends StatelessWidget {
  final List<AIStorageCommand> pendingCommands;
  final Function(AIStorageCommand) onApprove;
  final Function(AIStorageCommand) onReject;
  
  const AIMemoryCommandsWidget({
    super.key,
    required this.pendingCommands,
    required this.onApprove,
    required this.onReject,
  });
  
  @override
  Widget build(BuildContext context) {
    if (pendingCommands.isEmpty) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.psychology,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI Wants to Remember',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  '${pendingCommands.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          
          // Commands list
          ...pendingCommands.map((cmd) => _buildCommandCard(context, cmd)),
          
          // Approve/Reject all
          if (pendingCommands.length > 1)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      for (final cmd in pendingCommands) {
                        onReject(cmd);
                      }
                    },
                    child: const Text('Reject All'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      for (final cmd in pendingCommands) {
                        onApprove(cmd);
                      }
                    },
                    child: const Text('Approve All'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildCommandCard(BuildContext context, AIStorageCommand command) {
    final icon = _getCommandIcon(command.type);
    final color = _getCommandColor(context, command.type);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                _getCommandTypeName(command.type),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (command.priority >= 4)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Important',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Data to store
          Text(
            command.data,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          // Reason
          if (command.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              command.reason,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          
          const SizedBox(height: 8),
          
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => onReject(command),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Reject'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => onApprove(command),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  IconData _getCommandIcon(AICommandType type) {
    switch (type) {
      case AICommandType.storeSymptom:
        return Icons.healing;
      case AICommandType.storeCondition:
        return Icons.medical_information;
      case AICommandType.storeInsight:
        return Icons.lightbulb;
      case AICommandType.storeWarning:
        return Icons.warning_amber;
      case AICommandType.storeRelatedCondition:
        return Icons.link;
      case AICommandType.storeReminder:
        return Icons.alarm;
      case AICommandType.requestFollowUp:
        return Icons.event_note;
    }
  }
  
  Color _getCommandColor(BuildContext context, AICommandType type) {
    switch (type) {
      case AICommandType.storeSymptom:
        return Colors.blue;
      case AICommandType.storeCondition:
        return Colors.purple;
      case AICommandType.storeInsight:
        return Colors.amber.shade700;
      case AICommandType.storeWarning:
        return Colors.red;
      case AICommandType.storeRelatedCondition:
        return Colors.teal;
      case AICommandType.storeReminder:
        return Colors.green;
      case AICommandType.requestFollowUp:
        return Colors.indigo;
    }
  }
  
  String _getCommandTypeName(AICommandType type) {
    switch (type) {
      case AICommandType.storeSymptom:
        return 'Symptom';
      case AICommandType.storeCondition:
        return 'Condition';
      case AICommandType.storeInsight:
        return 'Insight';
      case AICommandType.storeWarning:
        return 'Warning';
      case AICommandType.storeRelatedCondition:
        return 'Related Condition';
      case AICommandType.storeReminder:
        return 'Reminder';
      case AICommandType.requestFollowUp:
        return 'Follow-up';
    }
  }
}

/// Compact badge to show AI learned something
class AIMemoryBadge extends StatelessWidget {
  final int commandsExecuted;
  final VoidCallback? onTap;
  
  const AIMemoryBadge({
    super.key,
    required this.commandsExecuted,
    this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    if (commandsExecuted == 0) return const SizedBox.shrink();
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              'Learned $commandsExecuted',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
