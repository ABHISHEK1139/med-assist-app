import 'dart:convert';

/// AI Memory Commands
/// 
/// Protocol for AI (on PC) to request data storage on phone.
/// 
/// How it works:
/// 1. AI generates response + optional storage commands
/// 2. Phone parses commands from AI response
/// 3. Phone decides whether to accept/reject each command
/// 4. User gets notification of what AI wants to store
/// 
/// GDPR Compliant:
/// - AI REQUESTS storage, phone DECIDES
/// - User can see/reject any storage request
/// - All data stays on user's phone
/// - PC never stores anything

/// Types of storage commands AI can request
enum AICommandType {
  storeSymptom,        // AI detected a symptom user mentioned
  storeCondition,      // AI identified a health condition
  storeInsight,        // AI has an insight worth remembering
  storeWarning,        // AI wants to flag a potential risk
  storeRelatedCondition, // AI found related conditions to watch
  storeReminder,       // AI suggests a health reminder
  requestFollowUp,     // AI wants to check on something later
}

/// Command from AI to store data on phone
class AIStorageCommand {
  final AICommandType type;
  final String data;
  final String reason;
  final String? relatedTo;
  final int priority; // 1-5, 5 being most important
  final bool requiresUserApproval;
  
  AIStorageCommand({
    required this.type,
    required this.data,
    required this.reason,
    this.relatedTo,
    this.priority = 3,
    this.requiresUserApproval = false,
  });
  
  factory AIStorageCommand.fromJson(Map<String, dynamic> json) {
    return AIStorageCommand(
      type: AICommandType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AICommandType.storeInsight,
      ),
      data: json['data'] ?? '',
      reason: json['reason'] ?? '',
      relatedTo: json['related_to'],
      priority: json['priority'] ?? 3,
      requiresUserApproval: json['requires_approval'] ?? false,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'data': data,
    'reason': reason,
    'related_to': relatedTo,
    'priority': priority,
    'requires_approval': requiresUserApproval,
  };
}

/// Response from AI with both text response and storage commands
class AIResponseWithCommands {
  final String response;
  final List<AIStorageCommand> commands;
  final List<String> dataRequests; // Data AI wants from phone
  
  AIResponseWithCommands({
    required this.response,
    this.commands = const [],
    this.dataRequests = const [],
  });
  
  bool get hasCommands => commands.isNotEmpty;
  bool get hasDataRequests => dataRequests.isNotEmpty;
  
  /// Parse AI response that contains embedded commands
  /// 
  /// AI can embed commands in response like:
  /// ```
  /// [STORE_SYMPTOM:headache:User mentioned recurring headaches]
  /// [STORE_WARNING:dehydration:Symptoms suggest possible dehydration]
  /// [STORE_RELATED:migraine|tension headache:These conditions often co-occur]
  /// ```
  factory AIResponseWithCommands.parse(String rawResponse) {
    final commands = <AIStorageCommand>[];
    String cleanResponse = rawResponse;
    
    // Parse embedded commands
    final commandRegex = RegExp(r'\[(\w+):([^:]+):([^\]]+)\]');
    final matches = commandRegex.allMatches(rawResponse);
    
    for (final match in matches) {
      final typeStr = match.group(1)!;
      final data = match.group(2)!;
      final reason = match.group(3)!;
      
      AICommandType? type;
      switch (typeStr.toUpperCase()) {
        case 'STORE_SYMPTOM':
          type = AICommandType.storeSymptom;
          break;
        case 'STORE_CONDITION':
          type = AICommandType.storeCondition;
          break;
        case 'STORE_INSIGHT':
          type = AICommandType.storeInsight;
          break;
        case 'STORE_WARNING':
          type = AICommandType.storeWarning;
          break;
        case 'STORE_RELATED':
          type = AICommandType.storeRelatedCondition;
          break;
        case 'STORE_REMINDER':
          type = AICommandType.storeReminder;
          break;
        case 'REQUEST_FOLLOWUP':
          type = AICommandType.requestFollowUp;
          break;
      }
      
      if (type != null) {
        commands.add(AIStorageCommand(
          type: type,
          data: data.trim(),
          reason: reason.trim(),
          requiresUserApproval: type == AICommandType.storeWarning,
        ));
      }
      
      // Remove command from visible response
      cleanResponse = cleanResponse.replaceAll(match.group(0)!, '');
    }
    
    return AIResponseWithCommands(
      response: cleanResponse.trim(),
      commands: commands,
    );
  }
}

/// Settings for AI memory behavior
class AIMemorySettings {
  final bool autoStoreSymptoms;
  final bool autoStoreInsights;
  final bool requireApprovalForWarnings;
  final bool requireApprovalForConditions;
  final bool notifyOnStore;
  
  const AIMemorySettings({
    this.autoStoreSymptoms = true,
    this.autoStoreInsights = true,
    this.requireApprovalForWarnings = true,
    this.requireApprovalForConditions = true,
    this.notifyOnStore = true,
  });
  
  /// Check if a command should be auto-approved
  bool shouldAutoApprove(AIStorageCommand command) {
    switch (command.type) {
      case AICommandType.storeSymptom:
        return autoStoreSymptoms;
      case AICommandType.storeInsight:
        return autoStoreInsights;
      case AICommandType.storeWarning:
        return !requireApprovalForWarnings;
      case AICommandType.storeCondition:
        return !requireApprovalForConditions;
      default:
        return false;
    }
  }
}
