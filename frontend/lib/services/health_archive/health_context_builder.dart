import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'database.dart';
import 'models.dart';
import 'health_archive_service.dart';
import '../wearable_sync_service.dart';

/// Health Context Builder
/// 
/// Builds smart, minimal context packets for AI requests.
/// Only sends relevant data - not the entire health history.
/// 
/// 🔑 Core Principle: "Accuracy comes from relevance, not volume"
/// 
/// This class handles:
/// - Active symptom tracking with duration
/// - Context packet assembly for different request types
/// - Smart filtering of what to send vs what to keep local
class HealthContextBuilder {
  final HealthArchiveService _archiveService;
  final WearableSyncService _wearableSync = WearableSyncService();
  Database? _db;
  
  HealthContextBuilder(this._archiveService);
  
  Future<void> initialize() async {
    _db = await HealthArchiveDatabase.database;
    await _createSymptomTable();
  }
  
  /// Create symptoms tracking table if not exists
  Future<void> _createSymptomTable() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS active_symptoms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        severity TEXT DEFAULT 'moderate',
        onset_date TEXT NOT NULL,
        last_mentioned TEXT NOT NULL,
        mention_count INTEGER DEFAULT 1,
        associated_conditions TEXT,
        notes TEXT,
        status TEXT DEFAULT 'active',
        resolved_date TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // Recent reports tracking
    await db.execute('''
      CREATE TABLE IF NOT EXISTS health_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        report_type TEXT NOT NULL,
        report_name TEXT NOT NULL,
        summary TEXT,
        key_findings TEXT,
        report_date TEXT,
        file_path TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // Session context (for current conversation)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_context (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        context_type TEXT NOT NULL,
        context_data TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }
  
  // ==================== SYMPTOM TRACKING ====================
  
  /// Add or update an active symptom
  Future<void> trackSymptom(ActiveSymptom symptom) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    
    // Check if symptom already exists
    final existing = await db.query(
      'active_symptoms',
      where: 'LOWER(name) = LOWER(?) AND status = ?',
      whereArgs: [symptom.name, 'active'],
    );
    
    if (existing.isNotEmpty) {
      // Update existing symptom
      final id = existing.first['id'] as int;
      final count = (existing.first['mention_count'] as int?) ?? 1;
      
      await db.update(
        'active_symptoms',
        {
          'last_mentioned': DateTime.now().toIso8601String(),
          'mention_count': count + 1,
          'severity': symptom.severity.name,
          'notes': symptom.notes,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      // Insert new symptom
      await db.insert('active_symptoms', symptom.toMap());
    }
  }
  
  /// Mark symptom as resolved
  Future<void> resolveSymptom(String symptomName) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    await db.update(
      'active_symptoms',
      {
        'status': 'resolved',
        'resolved_date': DateTime.now().toIso8601String(),
      },
      where: 'LOWER(name) = LOWER(?) AND status = ?',
      whereArgs: [symptomName, 'active'],
    );
  }
  
  /// Get all active symptoms with duration
  Future<List<ActiveSymptom>> getActiveSymptoms() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final maps = await db.query(
      'active_symptoms',
      where: 'status = ?',
      whereArgs: ['active'],
      orderBy: 'onset_date DESC',
    );
    return maps.map((m) => ActiveSymptom.fromMap(m)).toList();
  }
  
  // ==================== REPORT TRACKING ====================
  
  /// Add a health report reference
  Future<void> addReport(HealthReport report) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    await db.insert('health_reports', report.toMap());
  }
  
  /// Get recent reports (last 30 days)
  Future<List<HealthReport>> getRecentReports({int days = 30}) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    
    final maps = await db.query(
      'health_reports',
      where: 'created_at > ?',
      whereArgs: [cutoff.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => HealthReport.fromMap(m)).toList();
  }
  
  // ==================== CONTEXT PACKET BUILDERS ====================
  
  /// Build context packet for a CHAT request
  Future<ChatContextPacket> buildChatContext(String currentMessage) async {
    final symptoms = await getActiveSymptoms();
    final reports = await getRecentReports(days: 14);
    final profile = await _archiveService.getFullProfile();
    final wearableData = await _wearableSync.fetchTodayMetrics();
    
    return ChatContextPacket(
      currentMessage: currentMessage,
      activeSymptoms: symptoms.map((s) => SymptomSummary(
        name: s.name,
        durationDays: s.durationDays,
        severity: s.severity.name,
      )).toList(),
      chronicConditions: profile.conditions
          .where((c) => c.status == ConditionStatus.active || c.status == ConditionStatus.managed)
          .map((c) => c.name)
          .toList(),
      currentMedications: profile.medications
          .where((m) => m.status == MedicationStatus.current)
          .map((m) => '${m.name}${m.dosage != null ? ' ${m.dosage}${m.dosageUnit ?? ''}' : ''}')
          .toList(),
      allergies: profile.allergies.map((a) => a.allergen).toList(),
      recentReports: reports.map((r) => ReportReference(
        type: r.reportType,
        name: r.reportName,
        keyFindings: r.keyFindings,
      )).toList(),
      wearableData: wearableData.isNotEmpty ? wearableData : null,
    );
  }
  
  /// Build context packet for an IMAGE analysis request
  Future<ImageContextPacket> buildImageContext({
    required String imageType,
    String? additionalContext,
  }) async {
    final symptoms = await getActiveSymptoms();
    final profile = await _archiveService.getFullProfile();
    
    return ImageContextPacket(
      imageType: imageType,
      knownSymptoms: symptoms.map((s) => s.name).toList(),
      relevantConditions: profile.conditions
          .where((c) => c.status == ConditionStatus.active)
          .map((c) => c.name)
          .toList(),
      allergies: profile.allergies.map((a) => a.allergen).toList(),
      additionalContext: additionalContext,
    );
  }
  
  /// Build context packet for a REPORT/PDF analysis request
  Future<ReportContextPacket> buildReportContext({
    required String reportType,
    required String extractedText,
  }) async {
    final symptoms = await getActiveSymptoms();
    final profile = await _archiveService.getFullProfile();
    
    return ReportContextPacket(
      reportType: reportType,
      extractedText: extractedText,
      existingConditions: profile.conditions.map((c) => c.name).toList(),
      currentMedications: profile.medications
          .where((m) => m.status == MedicationStatus.current)
          .map((m) => m.name)
          .toList(),
      relevantSymptoms: symptoms.map((s) => s.name).toList(),
    );
  }
  
  /// Build a MINIMAL health summary for quick requests
  Future<HealthSummary> buildMinimalSummary() async {
    final symptoms = await getActiveSymptoms();
    final profile = await _archiveService.getFullProfile();
    
    return HealthSummary(
      activeSymptomCount: symptoms.length,
      topSymptoms: symptoms.take(3).map((s) => s.name).toList(),
      hasChronicConditions: profile.conditions.any(
        (c) => c.status == ConditionStatus.active || c.status == ConditionStatus.managed
      ),
      hasMedications: profile.medications.any((m) => m.status == MedicationStatus.current),
      hasAllergies: profile.allergies.isNotEmpty,
      lastUpdated: DateTime.now(),
    );
  }
  
  /// Get the full context as JSON string for API calls
  Future<String> getContextJson(ContextType type, {
    String? message,
    String? imageType,
    String? reportType,
    String? extractedText,
  }) async {
    switch (type) {
      case ContextType.chat:
        final packet = await buildChatContext(message ?? '');
        return jsonEncode(packet.toJson());
        
      case ContextType.image:
        final packet = await buildImageContext(
          imageType: imageType ?? 'unknown',
          additionalContext: message,
        );
        return jsonEncode(packet.toJson());
        
      case ContextType.report:
        final packet = await buildReportContext(
          reportType: reportType ?? 'medical_report',
          extractedText: extractedText ?? '',
        );
        return jsonEncode(packet.toJson());
        
      case ContextType.minimal:
        final summary = await buildMinimalSummary();
        return jsonEncode(summary.toJson());
    }
  }
}

/// Types of context requests
enum ContextType { chat, image, report, minimal }

// ==================== DATA MODELS ====================

/// Active symptom being tracked
class ActiveSymptom {
  final int? id;
  final String name;
  final Severity severity;
  final DateTime onsetDate;
  final DateTime lastMentioned;
  final int mentionCount;
  final List<String>? associatedConditions;
  final String? notes;
  final String status;
  final DateTime? resolvedDate;
  
  ActiveSymptom({
    this.id,
    required this.name,
    this.severity = Severity.moderate,
    required this.onsetDate,
    DateTime? lastMentioned,
    this.mentionCount = 1,
    this.associatedConditions,
    this.notes,
    this.status = 'active',
    this.resolvedDate,
  }) : lastMentioned = lastMentioned ?? DateTime.now();
  
  /// Calculate duration in days
  int get durationDays => DateTime.now().difference(onsetDate).inDays;
  
  /// Human-readable duration
  String get durationText {
    final days = durationDays;
    if (days == 0) return 'today';
    if (days == 1) return '1 day';
    if (days < 7) return '$days days';
    if (days < 14) return '1 week';
    if (days < 30) return '${(days / 7).round()} weeks';
    if (days < 60) return '1 month';
    return '${(days / 30).round()} months';
  }
  
  Map<String, dynamic> toMap() => {
    'name': name,
    'severity': severity.name,
    'onset_date': onsetDate.toIso8601String(),
    'last_mentioned': lastMentioned.toIso8601String(),
    'mention_count': mentionCount,
    'associated_conditions': associatedConditions?.join(','),
    'notes': notes,
    'status': status,
    'resolved_date': resolvedDate?.toIso8601String(),
  };
  
  factory ActiveSymptom.fromMap(Map<String, dynamic> map) => ActiveSymptom(
    id: map['id'] as int?,
    name: map['name'] as String,
    severity: Severity.values.firstWhere(
      (e) => e.name == map['severity'],
      orElse: () => Severity.moderate,
    ),
    onsetDate: DateTime.parse(map['onset_date'] as String),
    lastMentioned: DateTime.parse(map['last_mentioned'] as String),
    mentionCount: map['mention_count'] as int? ?? 1,
    associatedConditions: (map['associated_conditions'] as String?)?.split(','),
    notes: map['notes'] as String?,
    status: map['status'] as String? ?? 'active',
    resolvedDate: map['resolved_date'] != null 
        ? DateTime.tryParse(map['resolved_date']) 
        : null,
  );
}

/// Health report reference
class HealthReport {
  final int? id;
  final String reportType;
  final String reportName;
  final String? summary;
  final String? keyFindings;
  final DateTime? reportDate;
  final String? filePath;
  final DateTime createdAt;
  
  HealthReport({
    this.id,
    required this.reportType,
    required this.reportName,
    this.summary,
    this.keyFindings,
    this.reportDate,
    this.filePath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  Map<String, dynamic> toMap() => {
    'report_type': reportType,
    'report_name': reportName,
    'summary': summary,
    'key_findings': keyFindings,
    'report_date': reportDate?.toIso8601String(),
    'file_path': filePath,
    'created_at': createdAt.toIso8601String(),
  };
  
  factory HealthReport.fromMap(Map<String, dynamic> map) => HealthReport(
    id: map['id'] as int?,
    reportType: map['report_type'] as String,
    reportName: map['report_name'] as String,
    summary: map['summary'] as String?,
    keyFindings: map['key_findings'] as String?,
    reportDate: map['report_date'] != null 
        ? DateTime.tryParse(map['report_date']) 
        : null,
    filePath: map['file_path'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
  );
}

// ==================== CONTEXT PACKETS ====================

/// Symptom summary for context packets
class SymptomSummary {
  final String name;
  final int durationDays;
  final String severity;
  
  SymptomSummary({
    required this.name,
    required this.durationDays,
    required this.severity,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'duration_days': durationDays,
    'severity': severity,
  };
}

/// Report reference for context packets
class ReportReference {
  final String type;
  final String name;
  final String? keyFindings;
  
  ReportReference({
    required this.type,
    required this.name,
    this.keyFindings,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    if (keyFindings != null) 'key_findings': keyFindings,
  };
}

/// Context packet for CHAT requests
class ChatContextPacket {
  final String currentMessage;
  final List<SymptomSummary> activeSymptoms;
  final List<String> chronicConditions;
  final List<String> currentMedications;
  final List<String> allergies;
  final List<ReportReference> recentReports;
  final Map<String, dynamic>? wearableData;
  
  ChatContextPacket({
    required this.currentMessage,
    required this.activeSymptoms,
    required this.chronicConditions,
    required this.currentMedications,
    required this.allergies,
    required this.recentReports,
    this.wearableData,
  });
  
  Map<String, dynamic> toJson() => {
    'current_message': currentMessage,
    'health_context': {
      'active_symptoms': activeSymptoms.map((s) => s.toJson()).toList(),
      'chronic_conditions': chronicConditions,
      'current_medications': currentMedications,
      'allergies': allergies,
      'recent_reports': recentReports.map((r) => r.toJson()).toList(),
      if (wearableData != null) 'wearables': wearableData,
    },
  };
  
  /// Convert to prompt string for LLM
  String toPromptString() {
    final buffer = StringBuffer();
    
    if (activeSymptoms.isNotEmpty) {
      buffer.writeln('Current Symptoms:');
      for (final s in activeSymptoms) {
        buffer.writeln('- ${s.name} (${s.durationDays} days, ${s.severity})');
      }
    }
    
    if (chronicConditions.isNotEmpty) {
      buffer.writeln('\nKnown Conditions: ${chronicConditions.join(', ')}');
    }
    
    if (currentMedications.isNotEmpty) {
      buffer.writeln('Current Medications: ${currentMedications.join(', ')}');
    }
    
    if (allergies.isNotEmpty) {
      buffer.writeln('⚠️ Allergies: ${allergies.join(', ')}');
    }
    
    if (recentReports.isNotEmpty) {
      buffer.writeln('\nRecent Reports:');
      for (final r in recentReports) {
        buffer.write('- ${r.name}');
        if (r.keyFindings != null) buffer.write(': ${r.keyFindings}');
        buffer.writeln();
      }
    }
    
    if (wearableData != null) {
      buffer.writeln('\nToday\'s Vitals & Activity:');
      if (wearableData!.containsKey('steps_today')) {
        buffer.writeln('- Steps: ${wearableData!['steps_today']}');
      }
      if (wearableData!.containsKey('avg_heart_rate')) {
        buffer.writeln('- Avg Heart Rate: ${wearableData!['avg_heart_rate']} bpm');
      }
      if (wearableData!.containsKey('sleep_hours_last_night')) {
        buffer.writeln('- Sleep last night: ${wearableData!['sleep_hours_last_night']} hrs');
      }
    }
    
    return buffer.toString();
  }
}

/// Context packet for IMAGE analysis requests
class ImageContextPacket {
  final String imageType;
  final List<String> knownSymptoms;
  final List<String> relevantConditions;
  final List<String> allergies;
  final String? additionalContext;
  
  ImageContextPacket({
    required this.imageType,
    required this.knownSymptoms,
    required this.relevantConditions,
    required this.allergies,
    this.additionalContext,
  });
  
  Map<String, dynamic> toJson() => {
    'image_type': imageType,
    'known_symptoms': knownSymptoms,
    'relevant_conditions': relevantConditions,
    'allergies': allergies,
    if (additionalContext != null) 'context': additionalContext,
  };
}

/// Context packet for REPORT/PDF analysis requests
class ReportContextPacket {
  final String reportType;
  final String extractedText;
  final List<String> existingConditions;
  final List<String> currentMedications;
  final List<String> relevantSymptoms;
  
  ReportContextPacket({
    required this.reportType,
    required this.extractedText,
    required this.existingConditions,
    required this.currentMedications,
    required this.relevantSymptoms,
  });
  
  Map<String, dynamic> toJson() => {
    'report_type': reportType,
    'extracted_text': extractedText,
    'patient_context': {
      'existing_conditions': existingConditions,
      'current_medications': currentMedications,
      'relevant_symptoms': relevantSymptoms,
    },
  };
}

/// Minimal health summary for quick checks
class HealthSummary {
  final int activeSymptomCount;
  final List<String> topSymptoms;
  final bool hasChronicConditions;
  final bool hasMedications;
  final bool hasAllergies;
  final DateTime lastUpdated;
  
  HealthSummary({
    required this.activeSymptomCount,
    required this.topSymptoms,
    required this.hasChronicConditions,
    required this.hasMedications,
    required this.hasAllergies,
    required this.lastUpdated,
  });
  
  bool get isEmpty => 
      activeSymptomCount == 0 && 
      !hasChronicConditions && 
      !hasMedications && 
      !hasAllergies;
  
  Map<String, dynamic> toJson() => {
    'active_symptoms': activeSymptomCount,
    'top_symptoms': topSymptoms,
    'has_chronic_conditions': hasChronicConditions,
    'has_medications': hasMedications,
    'has_allergies': hasAllergies,
    'last_updated': lastUpdated.toIso8601String(),
  };
}
