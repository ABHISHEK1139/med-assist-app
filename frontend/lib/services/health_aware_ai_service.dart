import 'dart:convert';
import 'health_archive/health_context_builder.dart';
import 'health_archive/symptom_extractor.dart';
import 'health_archive/health_archive_service.dart';
import 'health_archive/models.dart';
import 'on_device_llm_service.dart';

// Re-export for convenience
export 'health_archive/health_context_builder.dart' 
    show ActiveSymptom, HealthReport, HealthSummary, 
         ChatContextPacket, ImageContextPacket, ReportContextPacket;
export 'health_archive/models.dart' show Severity;

/// Health-Aware AI Service
/// 
/// Integrates the Health Context Builder with AI requests.
/// Automatically:
/// - Builds minimal but complete context for each request
/// - Extracts and tracks symptoms from responses
/// - Updates the health memory after each interaction
/// 
/// 🔑 Key Principle: Send relevant context, not raw history
class HealthAwareAIService {
  final OnDeviceLLMService _llmService;
  final HealthArchiveService _archiveService;
  late final HealthContextBuilder _contextBuilder;
  late final SymptomExtractor _symptomExtractor;
  
  bool _isInitialized = false;
  
  HealthAwareAIService(this._llmService, this._archiveService);
  
  /// Initialize all components
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _archiveService.initialize();
    
    _contextBuilder = HealthContextBuilder(_archiveService);
    await _contextBuilder.initialize();
    
    _symptomExtractor = SymptomExtractor(_contextBuilder);
    
    _isInitialized = true;
  }
  
  /// Send a chat message with smart health context
  /// 
  /// This method:
  /// 1. Builds a context packet with only relevant health info
  /// 2. Sends to LLM with proper context
  /// 3. Extracts symptoms from user message
  /// 4. Updates health memory
  Future<HealthAwareResponse> chat(String message) async {
    await initialize();
    
    // Step 1: Quick symptom extraction (pattern-based)
    final extractedCount = await _symptomExtractor.quickExtractAndSave(message);
    
    // Step 2: Build context packet
    final contextPacket = await _contextBuilder.buildChatContext(message);
    
    // Step 3: Build the prompt with context
    final prompt = _buildPromptWithContext(message, contextPacket);
    
    // Step 4: Get response from LLM
    final response = await _llmService.generateResponse(prompt);
    
    return HealthAwareResponse(
      response: response,
      contextUsed: contextPacket,
      symptomsExtracted: extractedCount,
    );
  }
  
  /// Analyze an image with health context
  Future<HealthAwareResponse> analyzeImage({
    required String imagePath,
    required String imageType,
    String? userDescription,
  }) async {
    await initialize();
    
    // Build image context packet
    final contextPacket = await _contextBuilder.buildImageContext(
      imageType: imageType,
      additionalContext: userDescription,
    );
    
    // Build the prompt
    final prompt = '''
Analyze this medical image.

Image Type: ${contextPacket.imageType}

Patient Context:
- Known Symptoms: ${contextPacket.knownSymptoms.join(', ')}
- Relevant Conditions: ${contextPacket.relevantConditions.join(', ')}
- Allergies: ${contextPacket.allergies.join(', ')}
${contextPacket.additionalContext != null ? '- Additional Info: ${contextPacket.additionalContext}' : ''}

Provide:
1. What you observe in the image
2. Possible interpretations
3. Recommended next steps
4. When to seek immediate care (if applicable)

Note: This is not a diagnosis. Always consult a healthcare professional.
''';
    
    // Use multimodal inference if available
    String response;
    try {
      response = await _llmService.generateWithImage(prompt, imagePath);
    } catch (e) {
      // Fallback to text-only
      response = await _llmService.generateResponse(
        '$prompt\n\n[Image analysis not available - please describe what you see]'
      );
    }
    
    return HealthAwareResponse(
      response: response,
      imageContextUsed: contextPacket,
    );
  }
  
  /// Analyze a medical report/PDF with context
  Future<HealthAwareResponse> analyzeReport({
    required String reportType,
    required String extractedText,
  }) async {
    await initialize();
    
    // Build report context packet
    final contextPacket = await _contextBuilder.buildReportContext(
      reportType: reportType,
      extractedText: extractedText,
    );
    
    // Build the prompt
    final prompt = '''
Analyze this medical report in the context of the patient's health profile.

Report Type: ${contextPacket.reportType}

Report Content:
${contextPacket.extractedText}

Patient Context:
- Existing Conditions: ${contextPacket.existingConditions.join(', ')}
- Current Medications: ${contextPacket.currentMedications.join(', ')}
- Current Symptoms: ${contextPacket.relevantSymptoms.join(', ')}

Provide:
1. Key findings from this report
2. How these relate to existing conditions
3. Any concerning values and their implications
4. Questions to discuss with your doctor

Note: This is educational information, not medical advice.
''';
    
    final response = await _llmService.generateResponse(prompt);
    
    // Store report reference
    await _contextBuilder.addReport(HealthReport(
      reportType: reportType,
      reportName: '${reportType}_${DateTime.now().millisecondsSinceEpoch}',
      summary: _extractSummary(response),
      keyFindings: _extractKeyFindings(response),
    ));
    
    return HealthAwareResponse(
      response: response,
      reportContextUsed: contextPacket,
    );
  }
  
  /// Get the current health summary (for UI display)
  Future<HealthSummary> getHealthSummary() async {
    await initialize();
    return _contextBuilder.buildMinimalSummary();
  }
  
  /// Get active symptoms (for UI display)
  Future<List<ActiveSymptom>> getActiveSymptoms() async {
    await initialize();
    return _contextBuilder.getActiveSymptoms();
  }
  
  /// Manually track a symptom
  Future<void> trackSymptom({
    required String name,
    String severity = 'moderate',
    int? durationDays,
    String? notes,
  }) async {
    await initialize();
    
    await _contextBuilder.trackSymptom(ActiveSymptom(
      name: name,
      severity: _parseSeverity(severity),
      onsetDate: durationDays != null
          ? DateTime.now().subtract(Duration(days: durationDays))
          : DateTime.now(),
      notes: notes,
    ));
  }
  
  /// Mark a symptom as resolved
  Future<void> resolveSymptom(String symptomName) async {
    await initialize();
    await _contextBuilder.resolveSymptom(symptomName);
  }
  
  // ==================== PRIVATE HELPERS ====================
  
  String _buildPromptWithContext(String message, ChatContextPacket context) {
    final buffer = StringBuffer();
    
    // Add health context if available
    final contextStr = context.toPromptString();
    if (contextStr.isNotEmpty) {
      buffer.writeln('=== PATIENT HEALTH CONTEXT ===');
      buffer.writeln(contextStr);
      buffer.writeln('==============================\n');
    }
    
    buffer.writeln('User: $message');
    buffer.writeln('\nProvide a helpful, accurate response. Consider the health context above when relevant.');
    buffer.writeln('If this is a new symptom, acknowledge it. If it relates to known conditions, explain the connection.');
    buffer.writeln('Always recommend consulting a healthcare professional for medical decisions.');
    
    return buffer.toString();
  }
  
  String _extractSummary(String response) {
    // Extract first 200 chars as summary
    if (response.length <= 200) return response;
    return '${response.substring(0, 197)}...';
  }
  
  String _extractKeyFindings(String response) {
    // Look for key findings section
    final lower = response.toLowerCase();
    
    // Try to find a findings section
    final markers = ['key findings:', 'findings:', 'summary:', 'results:'];
    for (final marker in markers) {
      final index = lower.indexOf(marker);
      if (index != -1) {
        final endIndex = response.indexOf('\n\n', index + marker.length);
        if (endIndex != -1) {
          return response.substring(index, endIndex).trim();
        }
        return response.substring(index).trim();
      }
    }
    
    // Fallback: first 300 chars
    if (response.length <= 300) return response;
    return '${response.substring(0, 297)}...';
  }
  
  Severity _parseSeverity(String severity) {
    return Severity.values.firstWhere(
      (e) => e.name == severity.toLowerCase(),
      orElse: () => Severity.moderate,
    );
  }
}

/// Response with context information
class HealthAwareResponse {
  final String response;
  final ChatContextPacket? contextUsed;
  final ImageContextPacket? imageContextUsed;
  final ReportContextPacket? reportContextUsed;
  final int symptomsExtracted;
  
  HealthAwareResponse({
    required this.response,
    this.contextUsed,
    this.imageContextUsed,
    this.reportContextUsed,
    this.symptomsExtracted = 0,
  });
  
  /// Get the context as JSON (for debugging/logging)
  Map<String, dynamic> toJson() => {
    'response': response,
    'symptoms_extracted': symptomsExtracted,
    if (contextUsed != null) 'chat_context': contextUsed!.toJson(),
    if (imageContextUsed != null) 'image_context': imageContextUsed!.toJson(),
    if (reportContextUsed != null) 'report_context': reportContextUsed!.toJson(),
  };
}

