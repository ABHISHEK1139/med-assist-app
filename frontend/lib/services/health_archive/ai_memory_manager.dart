import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'database.dart';
import 'models.dart';
import 'health_context_builder.dart';
import 'ai_memory_commands.dart';

/// AI Memory Manager
/// 
/// Manages bidirectional data flow between AI (PC) and Health Memory (Phone).
/// 
/// GDPR-Compliant Design:
/// - Phone is the DATA CONTROLLER (decides what to store)
/// - PC/AI is the DATA PROCESSOR (processes but doesn't store)
/// - All storage happens on phone only
/// - User has full visibility and control
/// 
/// Capabilities:
/// 1. AI can READ health data (via context packets)
/// 2. AI can REQUEST storage (phone decides to accept)
/// 3. AI can suggest related conditions to watch
/// 4. AI can flag important insights for future reference
class AIMemoryManager {
  final HealthContextBuilder _contextBuilder;
  Database? _db;
  
  AIMemorySettings _settings = const AIMemorySettings();
  
  // Stream for notifying UI of pending approvals
  final _pendingApprovalsController = StreamController<List<AIStorageCommand>>.broadcast();
  Stream<List<AIStorageCommand>> get pendingApprovals => _pendingApprovalsController.stream;
  
  final List<AIStorageCommand> _pendingCommands = [];
  
  AIMemoryManager(this._contextBuilder);
  
  Future<void> initialize() async {
    _db = await HealthArchiveDatabase.database;
    await _createTables();
  }
  
  Future<void> _createTables() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    
    // AI Insights table - stores AI-generated insights
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_insights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        insight_type TEXT NOT NULL,
        content TEXT NOT NULL,
        reason TEXT,
        related_symptoms TEXT,
        related_conditions TEXT,
        priority INTEGER DEFAULT 3,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        reviewed_at TEXT,
        user_feedback TEXT
      )
    ''');
    
    // AI Warnings table - important flags from AI
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_warnings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warning_type TEXT NOT NULL,
        content TEXT NOT NULL,
        severity TEXT DEFAULT 'medium',
        related_to TEXT,
        action_suggested TEXT,
        is_acknowledged INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        acknowledged_at TEXT
      )
    ''');
    
    // Related conditions watch list
    await db.execute('''
      CREATE TABLE IF NOT EXISTS condition_watch_list (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        primary_condition TEXT NOT NULL,
        related_condition TEXT NOT NULL,
        relationship TEXT,
        ai_reasoning TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // AI memory log - audit trail of all AI storage requests
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_memory_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        command_type TEXT NOT NULL,
        data TEXT NOT NULL,
        reason TEXT,
        was_approved INTEGER,
        approved_by TEXT DEFAULT 'auto',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }
  
  /// Process AI response and execute storage commands
  Future<ProcessedAIResponse> processAIResponse(String rawResponse) async {
    // Parse response for embedded commands
    final parsed = AIResponseWithCommands.parse(rawResponse);
    
    final executed = <AIStorageCommand>[];
    final pending = <AIStorageCommand>[];
    
    for (final command in parsed.commands) {
      if (_settings.shouldAutoApprove(command)) {
        await _executeCommand(command);
        executed.add(command);
      } else {
        pending.add(command);
        _pendingCommands.add(command);
      }
    }
    
    // Notify UI of pending approvals
    if (pending.isNotEmpty) {
      _pendingApprovalsController.add(List.from(_pendingCommands));
    }
    
    return ProcessedAIResponse(
      response: parsed.response,
      executedCommands: executed,
      pendingCommands: pending,
    );
  }
  
  /// Execute a storage command
  Future<void> _executeCommand(AIStorageCommand command) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    
    switch (command.type) {
      case AICommandType.storeSymptom:
        await _contextBuilder.trackSymptom(ActiveSymptom(
          name: command.data,
          severity: Severity.moderate,
          onsetDate: DateTime.now(),
          notes: 'AI detected: ${command.reason}',
        ));
        break;
        
      case AICommandType.storeCondition:
        // Store as a potential condition to discuss with doctor
        await db.insert('ai_insights', {
          'insight_type': 'potential_condition',
          'content': command.data,
          'reason': command.reason,
          'priority': command.priority,
        });
        break;
        
      case AICommandType.storeInsight:
        await db.insert('ai_insights', {
          'insight_type': 'general',
          'content': command.data,
          'reason': command.reason,
          'priority': command.priority,
        });
        break;
        
      case AICommandType.storeWarning:
        await db.insert('ai_warnings', {
          'warning_type': 'health_alert',
          'content': command.data,
          'severity': command.priority >= 4 ? 'high' : 'medium',
          'related_to': command.relatedTo,
        });
        break;
        
      case AICommandType.storeRelatedCondition:
        final parts = command.data.split('|');
        if (parts.length >= 2) {
          await db.insert('condition_watch_list', {
            'primary_condition': parts[0].trim(),
            'related_condition': parts[1].trim(),
            'relationship': 'co-occurrence',
            'ai_reasoning': command.reason,
          });
        }
        break;
        
      case AICommandType.storeReminder:
        await db.insert('ai_insights', {
          'insight_type': 'reminder',
          'content': command.data,
          'reason': command.reason,
          'priority': command.priority,
        });
        break;
        
      case AICommandType.requestFollowUp:
        await db.insert('ai_insights', {
          'insight_type': 'follow_up',
          'content': command.data,
          'reason': command.reason,
          'priority': 4, // Follow-ups are important
        });
        break;
    }
    
    // Log the command
    await db.insert('ai_memory_log', {
      'command_type': command.type.name,
      'data': command.data,
      'reason': command.reason,
      'was_approved': 1,
      'approved_by': command.requiresUserApproval ? 'user' : 'auto',
    });
  }
  
  /// User approves a pending command
  Future<void> approveCommand(AIStorageCommand command) async {
    await _executeCommand(command);
    _pendingCommands.remove(command);
    _pendingApprovalsController.add(List.from(_pendingCommands));
  }
  
  /// User rejects a pending command
  Future<void> rejectCommand(AIStorageCommand command) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    
    // Log rejection
    await db.insert('ai_memory_log', {
      'command_type': command.type.name,
      'data': command.data,
      'reason': command.reason,
      'was_approved': 0,
      'approved_by': 'user',
    });
    
    _pendingCommands.remove(command);
    _pendingApprovalsController.add(List.from(_pendingCommands));
  }
  
  /// Get all active AI insights
  Future<List<Map<String, dynamic>>> getActiveInsights() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.query(
      'ai_insights',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'priority DESC, created_at DESC',
    );
  }
  
  /// Get unacknowledged warnings
  Future<List<Map<String, dynamic>>> getActiveWarnings() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.query(
      'ai_warnings',
      where: 'is_acknowledged = ?',
      whereArgs: [0],
      orderBy: 'severity DESC, created_at DESC',
    );
  }
  
  /// Get conditions to watch based on current symptoms
  Future<List<Map<String, dynamic>>> getConditionWatchList() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.query(
      'condition_watch_list',
      where: 'is_active = ?',
      whereArgs: [1],
    );
  }
  
  /// Acknowledge a warning
  Future<void> acknowledgeWarning(int warningId) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    await db.update(
      'ai_warnings',
      {
        'is_acknowledged': 1,
        'acknowledged_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [warningId],
    );
  }
  
  /// Get AI memory audit log
  Future<List<Map<String, dynamic>>> getMemoryLog({int limit = 50}) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.query(
      'ai_memory_log',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
  
  /// Update settings
  void updateSettings(AIMemorySettings settings) {
    _settings = settings;
  }
  
  /// Clear all AI-stored data (GDPR Right to Erasure)
  Future<void> clearAllAIData() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    await db.delete('ai_insights');
    await db.delete('ai_warnings');
    await db.delete('condition_watch_list');
    await db.delete('ai_memory_log');
  }
  
  /// Export all AI-stored data (GDPR Right to Portability)
  Future<Map<String, dynamic>> exportAllAIData() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    
    return {
      'export_date': DateTime.now().toIso8601String(),
      'insights': await db.query('ai_insights'),
      'warnings': await db.query('ai_warnings'),
      'watch_list': await db.query('condition_watch_list'),
      'memory_log': await db.query('ai_memory_log'),
    };
  }
  
  void dispose() {
    _pendingApprovalsController.close();
  }
}

/// Result of processing AI response
class ProcessedAIResponse {
  final String response;
  final List<AIStorageCommand> executedCommands;
  final List<AIStorageCommand> pendingCommands;
  
  ProcessedAIResponse({
    required this.response,
    this.executedCommands = const [],
    this.pendingCommands = const [],
  });
  
  bool get hasPendingApprovals => pendingCommands.isNotEmpty;
  int get totalCommandsProcessed => executedCommands.length + pendingCommands.length;
}
