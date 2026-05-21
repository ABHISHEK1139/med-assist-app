import 'dart:async';
import '../on_device_llm_service.dart';
import 'medical_extractor.dart';
import 'health_archive_service.dart';
import 'models.dart';

/// Integrates Health Archive with Chat
/// 
/// Passively extracts medical information from conversations
/// and injects health context into AI responses.
class HealthAwareChat {
  final OnDeviceLLMService _llmService;
  final HealthArchiveService _archiveService;
  late final MedicalExtractor _extractor;
  
  bool _isInitialized = false;
  bool _extractionEnabled = true;
  
  // Cache for current session
  HealthProfile? _cachedProfile;
  DateTime? _profileCacheTime;
  static const _cacheTimeout = Duration(minutes: 5);
  
  HealthAwareChat(this._llmService, this._archiveService) {
    _extractor = MedicalExtractor(_archiveService);
  }
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _archiveService.initialize();
    _isInitialized = true;
  }
  
  /// Get the user's health context for AI prompts
  Future<String> getHealthContext() async {
    // Use cached profile if fresh
    if (_cachedProfile != null && 
        _profileCacheTime != null &&
        DateTime.now().difference(_profileCacheTime!) < _cacheTimeout) {
      return _buildContextString(_cachedProfile!);
    }
    
    // Fetch fresh profile
    _cachedProfile = await _archiveService.getFullProfile();
    _profileCacheTime = DateTime.now();
    
    return _buildContextString(_cachedProfile!);
  }
  
  String _buildContextString(HealthProfile profile) {
    if (profile.isEmpty) {
      return '';
    }
    
    final buffer = StringBuffer();
    buffer.writeln('=== USER HEALTH PROFILE ===');
    
    // Active conditions
    final activeConditions = profile.conditions
        .where((c) => c.status == ConditionStatus.active || c.status == ConditionStatus.managed)
        .toList();
    
    if (activeConditions.isNotEmpty) {
      buffer.writeln('\nActive Conditions:');
      for (final c in activeConditions) {
        buffer.write('- ${c.name}');
        if (c.onsetYear != null) buffer.write(' (since ${c.onsetYear})');
        if (c.severity != null && c.severity != Severity.unknown) {
          buffer.write(' [${c.severity!.name}]');
        }
        buffer.writeln();
      }
    }
    
    // Current medications
    final currentMeds = profile.medications
        .where((m) => m.status == MedicationStatus.current || m.status == MedicationStatus.asNeeded)
        .toList();
    
    if (currentMeds.isNotEmpty) {
      buffer.writeln('\nCurrent Medications:');
      for (final m in currentMeds) {
        buffer.write('- ${m.name}');
        if (m.dosage != null) buffer.write(' ${m.dosage}${m.dosageUnit ?? ''}');
        if (m.frequency != null) buffer.write(' ${m.frequency}');
        if (m.prescribedFor != null) buffer.write(' for ${m.prescribedFor}');
        buffer.writeln();
      }
    }
    
    // Allergies (always important!)
    if (profile.allergies.isNotEmpty) {
      buffer.writeln('\n⚠️ ALLERGIES:');
      for (final a in profile.allergies) {
        buffer.write('- ${a.allergen}');
        if (a.reaction != null) buffer.write(' → ${a.reaction}');
        if (a.severity != null && a.severity != Severity.unknown) {
          buffer.write(' [${a.severity!.name}]');
        }
        buffer.writeln();
      }
    }
    
    // Surgeries
    if (profile.surgeries.isNotEmpty) {
      buffer.writeln('\nSurgical History:');
      for (final s in profile.surgeries) {
        buffer.write('- ${s.procedureName}');
        if (s.year != null) buffer.write(' (${s.year})');
        buffer.writeln();
      }
    }
    
    // Family history
    if (profile.familyHistory.isNotEmpty) {
      buffer.writeln('\nFamily History:');
      for (final f in profile.familyHistory) {
        buffer.writeln('- ${f.relation.name}: ${f.condition}');
      }
    }
    
    // Recent vitals
    final recentVitals = _getRecentVitals(profile.vitals);
    if (recentVitals.isNotEmpty) {
      buffer.writeln('\nRecent Vitals:');
      for (final v in recentVitals) {
        buffer.writeln('- ${v.type.name}: ${v.value}${v.unit ?? ''}');
      }
    }
    
    // Lifestyle factors
    final currentLifestyle = profile.lifestyle
        .where((l) => l.status == LifestyleStatus.current || l.status == LifestyleStatus.former)
        .toList();
    
    if (currentLifestyle.isNotEmpty) {
      buffer.writeln('\nLifestyle:');
      for (final l in currentLifestyle) {
        buffer.writeln('- ${l.factor}: ${l.value ?? l.status.name}');
      }
    }
    
    buffer.writeln('=== END PROFILE ===');
    return buffer.toString();
  }
  
  List<VitalSign> _getRecentVitals(List<VitalSign> vitals) {
    // Get only most recent of each type
    final recentByType = <VitalType, VitalSign>{};
    
    // Sort by date descending
    final sorted = List<VitalSign>.from(vitals)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    
    for (final v in sorted) {
      if (!recentByType.containsKey(v.type)) {
        // Only include if within last 30 days
        if (DateTime.now().difference(v.recordedAt).inDays <= 30) {
          recentByType[v.type] = v;
        }
      }
    }
    
    return recentByType.values.toList();
  }
  
  /// Enhanced chat message with health context
  /// 
  /// 1. Injects health profile into system prompt
  /// 2. Generates AI response
  /// 3. Background extracts medical info from user message
  Future<String> chat(String userMessage) async {
    // Start background extraction (fire and forget)
    if (_extractionEnabled) {
      _extractInBackground(userMessage);
    }
    
    // Get health context
    final healthContext = await getHealthContext();
    
    // Build enhanced prompt
    final systemPrompt = '''You are Med Assist App, a compassionate medical AI assistant.

$healthContext

Important:
1. Consider the user's health profile when providing advice
2. ⚠️ Check allergies before suggesting any medications
3. Consider drug interactions with current medications
4. Personalize advice based on existing conditions
5. Always recommend consulting healthcare providers for serious concerns''';
    
    // Generate response
    return await _llmService.generateResponse(
      userMessage,
      systemPrompt: systemPrompt,
    );
  }
  
  /// Stream chat response with health context
  Stream<String> chatStream(String userMessage) async* {
    // Start background extraction
    if (_extractionEnabled) {
      _extractInBackground(userMessage);
    }
    
    // Get health context
    final healthContext = await getHealthContext();
    
    final systemPrompt = '''You are Med Assist App, a compassionate medical AI assistant.

$healthContext

Consider the user's complete medical history when responding.
⚠️ Always check for allergies before suggesting medications.''';
    
    // Use non-streaming generate since streaming was removed
    final response = await _llmService.generateResponse(
      userMessage,
      systemPrompt: systemPrompt,
    );
    yield response;
  }
  
  /// Background extraction - doesn't block the conversation
  void _extractInBackground(String userMessage) {
    // Skip very short messages
    if (userMessage.trim().length < 10) return;
    
    // Run extraction asynchronously
    Future(() async {
      try {
        // Build extraction prompt
        final extractionPrompt = _extractor.buildExtractionPrompt(userMessage);
        
        // Get LLM to extract entities
        final llmResponse = await _llmService.generateResponse(
          extractionPrompt,
          systemPrompt: 'You are a medical entity extractor. Output ONLY valid JSON.',
          maxTokens: 500,
        );
        
        // Process and save
        final result = await _extractor.processLLMResponse(llmResponse, userMessage);
        
        if (result.count > 0) {
          print('📋 Extracted ${result.count} medical facts: ${result.entities.join(", ")}');
          // Invalidate cache so next response uses updated profile
          _cachedProfile = null;
        }
      } catch (e) {
        print('Background extraction failed: $e');
        // Silent failure - don't interrupt user experience
      }
    });
  }
  
  /// Enable/disable automatic extraction
  void setExtractionEnabled(bool enabled) {
    _extractionEnabled = enabled;
  }
  
  /// Get current profile summary
  Future<HealthProfile> getProfile() async {
    return await _archiveService.getFullProfile();
  }
  
  /// Search through health archive
  Future<List<dynamic>> searchHealth(String query) async {
    return await _archiveService.searchArchive(query);
  }
  
  /// Get archive statistics
  Future<Map<String, int>> getStats() async {
    return await _archiveService.getArchiveStats();
  }
  
  /// Clear the profile cache
  void clearCache() {
    _cachedProfile = null;
    _profileCacheTime = null;
  }
}
