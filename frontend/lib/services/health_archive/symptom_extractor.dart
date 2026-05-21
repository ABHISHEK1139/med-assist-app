import 'dart:convert';
import 'health_context_builder.dart';
import 'models.dart';

/// Symptom Extractor
/// 
/// Automatically extracts and tracks symptoms from user messages.
/// Uses pattern matching + LLM for accurate symptom identification.
/// 
/// Key Features:
/// - Recognizes common symptom patterns
/// - Extracts duration from natural language
/// - Identifies severity indicators
/// - Updates symptom database automatically
class SymptomExtractor {
  final HealthContextBuilder _contextBuilder;
  
  SymptomExtractor(this._contextBuilder);
  
  // Common symptom patterns (expandable)
  static const List<String> _commonSymptoms = [
    'fever', 'cough', 'cold', 'headache', 'pain', 'ache',
    'fatigue', 'tiredness', 'weakness', 'dizziness',
    'nausea', 'vomiting', 'diarrhea', 'constipation',
    'rash', 'itching', 'swelling', 'inflammation',
    'shortness of breath', 'breathing difficulty', 'breathlessness',
    'chest pain', 'palpitations', 'heart racing',
    'stomach pain', 'abdominal pain', 'bloating',
    'back pain', 'neck pain', 'joint pain', 'muscle pain',
    'sore throat', 'runny nose', 'congestion', 'sneezing',
    'insomnia', 'sleep problems', 'anxiety', 'stress',
    'loss of appetite', 'weight loss', 'weight gain',
    'blurred vision', 'eye pain', 'ear pain',
    'numbness', 'tingling', 'burning sensation',
  ];
  
  // Duration patterns
  static final Map<RegExp, int Function(Match)> _durationPatterns = {
    RegExp(r'(\d+)\s*days?'): (m) => int.parse(m.group(1)!),
    RegExp(r'(\d+)\s*weeks?'): (m) => int.parse(m.group(1)!) * 7,
    RegExp(r'(\d+)\s*months?'): (m) => int.parse(m.group(1)!) * 30,
    RegExp(r'since\s+yesterday'): (_) => 1,
    RegExp(r'since\s+last\s+week'): (_) => 7,
    RegExp(r'for\s+a\s+while'): (_) => 7,
    RegExp(r'past\s+few\s+days'): (_) => 3,
    RegExp(r'couple\s+of\s+days'): (_) => 2,
    RegExp(r'today|just\s+started'): (_) => 0,
    RegExp(r'this\s+morning|tonight'): (_) => 0,
  };
  
  // Severity indicators
  static final Map<String, Severity> _severityIndicators = {
    'mild': Severity.mild,
    'slight': Severity.mild,
    'little': Severity.mild,
    'minor': Severity.mild,
    'moderate': Severity.moderate,
    'some': Severity.moderate,
    'severe': Severity.severe,
    'bad': Severity.severe,
    'terrible': Severity.severe,
    'horrible': Severity.severe,
    'extreme': Severity.critical,
    'unbearable': Severity.critical,
    'worst': Severity.critical,
    'excruciating': Severity.critical,
    'intense': Severity.severe,
    'constant': Severity.severe,
    'persistent': Severity.moderate,
  };
  
  /// Extract symptoms from a user message (quick pattern-based)
  List<ExtractedSymptom> extractFromMessage(String message) {
    final lowerMessage = message.toLowerCase();
    final extracted = <ExtractedSymptom>[];
    
    for (final symptom in _commonSymptoms) {
      if (lowerMessage.contains(symptom)) {
        // Extract duration
        int? durationDays;
        for (final entry in _durationPatterns.entries) {
          final match = entry.key.firstMatch(lowerMessage);
          if (match != null) {
            durationDays = entry.value(match);
            break;
          }
        }
        
        // Extract severity
        var severity = Severity.moderate;
        for (final entry in _severityIndicators.entries) {
          if (lowerMessage.contains(entry.key)) {
            severity = entry.value;
            break;
          }
        }
        
        // Check for negation (e.g., "no fever", "fever is gone")
        if (_isNegated(lowerMessage, symptom)) {
          continue; // Skip negated symptoms
        }
        
        extracted.add(ExtractedSymptom(
          name: _normalizeSymptomName(symptom),
          severity: severity,
          durationDays: durationDays,
          rawText: _extractContext(message, symptom),
        ));
      }
    }
    
    return extracted;
  }
  
  /// Check if symptom is negated in the message
  bool _isNegated(String message, String symptom) {
    final negationPatterns = [
      'no $symptom',
      "don't have $symptom",
      "don't have any $symptom",
      '$symptom is gone',
      '$symptom went away',
      '$symptom resolved',
      'without $symptom',
      'no more $symptom',
    ];
    
    return negationPatterns.any((p) => message.contains(p));
  }
  
  /// Normalize symptom name
  String _normalizeSymptomName(String symptom) {
    // Capitalize first letter
    return symptom[0].toUpperCase() + symptom.substring(1);
  }
  
  /// Extract surrounding context for the symptom
  String _extractContext(String message, String symptom) {
    final index = message.toLowerCase().indexOf(symptom);
    if (index == -1) return symptom;
    
    final start = (index - 30).clamp(0, message.length);
    final end = (index + symptom.length + 30).clamp(0, message.length);
    
    return message.substring(start, end).trim();
  }
  
  /// Build LLM prompt for detailed symptom extraction
  String buildExtractionPrompt(String message) {
    return '''
Extract symptoms from this message with temporal information.

Message: "$message"

Current Date: ${DateTime.now().toIso8601String().split('T')[0]}

Return JSON:
{
  "symptoms": [
    {
      "name": "symptom name",
      "severity": "mild|moderate|severe|critical",
      "duration_days": 5,
      "onset_date": "2026-01-27",
      "associated_symptoms": ["other", "symptoms"],
      "notes": "relevant context"
    }
  ],
  "resolved_symptoms": ["symptom that got better"]
}

Rules:
1. Only extract actual symptoms the person is experiencing
2. Calculate onset_date from duration expressions
3. "10 days ago" → subtract 10 from current date
4. If no symptoms, return: {"symptoms": [], "resolved_symptoms": []}

JSON:''';
  }
  
  /// Process LLM response and update symptom database
  Future<SymptomExtractionResult> processLLMResponse(String response) async {
    try {
      // Clean response
      String jsonStr = response
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      
      final start = jsonStr.indexOf('{');
      final end = jsonStr.lastIndexOf('}');
      
      if (start == -1 || end == -1) {
        return SymptomExtractionResult(success: false, message: 'No JSON found');
      }
      
      jsonStr = jsonStr.substring(start, end + 1);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      final symptoms = (data['symptoms'] as List<dynamic>?) ?? [];
      final resolved = (data['resolved_symptoms'] as List<dynamic>?) ?? [];
      
      int addedCount = 0;
      int resolvedCount = 0;
      
      // Add/update symptoms
      for (final s in symptoms) {
        final symptomData = s as Map<String, dynamic>;
        
        DateTime onsetDate;
        if (symptomData['onset_date'] != null) {
          onsetDate = DateTime.parse(symptomData['onset_date']);
        } else if (symptomData['duration_days'] != null) {
          onsetDate = DateTime.now().subtract(
            Duration(days: symptomData['duration_days'] as int)
          );
        } else {
          onsetDate = DateTime.now();
        }
        
        final symptom = ActiveSymptom(
          name: symptomData['name'] as String,
          severity: _parseSeverity(symptomData['severity'] as String?),
          onsetDate: onsetDate,
          associatedConditions: (symptomData['associated_symptoms'] as List<dynamic>?)
              ?.cast<String>(),
          notes: symptomData['notes'] as String?,
        );
        
        await _contextBuilder.trackSymptom(symptom);
        addedCount++;
      }
      
      // Mark resolved symptoms
      for (final r in resolved) {
        await _contextBuilder.resolveSymptom(r as String);
        resolvedCount++;
      }
      
      return SymptomExtractionResult(
        success: true,
        addedCount: addedCount,
        resolvedCount: resolvedCount,
        message: 'Extracted $addedCount symptoms, resolved $resolvedCount',
      );
      
    } catch (e) {
      return SymptomExtractionResult(
        success: false,
        message: 'Error: $e',
      );
    }
  }
  
  Severity _parseSeverity(String? severity) {
    if (severity == null) return Severity.moderate;
    return Severity.values.firstWhere(
      (e) => e.name == severity.toLowerCase(),
      orElse: () => Severity.moderate,
    );
  }
  
  /// Quick extract and save (pattern-based, no LLM)
  Future<int> quickExtractAndSave(String message) async {
    final symptoms = extractFromMessage(message);
    
    for (final s in symptoms) {
      final symptom = ActiveSymptom(
        name: s.name,
        severity: s.severity,
        onsetDate: s.durationDays != null
            ? DateTime.now().subtract(Duration(days: s.durationDays!))
            : DateTime.now(),
        notes: s.rawText,
      );
      
      await _contextBuilder.trackSymptom(symptom);
    }
    
    return symptoms.length;
  }
}

/// Extracted symptom from pattern matching
class ExtractedSymptom {
  final String name;
  final Severity severity;
  final int? durationDays;
  final String? rawText;
  
  ExtractedSymptom({
    required this.name,
    required this.severity,
    this.durationDays,
    this.rawText,
  });
  
  @override
  String toString() => '$name (${severity.name}, ${durationDays ?? "?"} days)';
}

/// Result of symptom extraction
class SymptomExtractionResult {
  final bool success;
  final int addedCount;
  final int resolvedCount;
  final String? message;
  
  SymptomExtractionResult({
    required this.success,
    this.addedCount = 0,
    this.resolvedCount = 0,
    this.message,
  });
}
