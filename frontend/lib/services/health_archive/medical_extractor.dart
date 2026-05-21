import 'dart:convert';
import 'models.dart';
import 'health_archive_service.dart';

/// Medical Information Extractor
/// 
/// Extracts medical entities from conversation text with proper
/// TEMPORAL REASONING - converts "10 years ago" to actual year.
class MedicalExtractor {
  final HealthArchiveService _archiveService;
  
  MedicalExtractor(this._archiveService);
  
  /// Extract medical information from a user message
  /// Returns the extraction prompt for the LLM
  String buildExtractionPrompt(String userMessage) {
    final currentYear = DateTime.now().year;
    final currentDate = DateTime.now().toIso8601String().split('T')[0];
    
    return '''
Analyze this user message for personal medical history facts.

User Message: "$userMessage"

Current Date: $currentDate
Current Year: $currentYear

TEMPORAL REASONING RULES:
- "10 years ago" → ${currentYear - 10}
- "5 years ago" → ${currentYear - 5}  
- "since childhood" → estimate age 10, calculate year
- "last month" → ${_getLastMonth()}
- "last year" → ${currentYear - 1}
- "few years back" → ${currentYear - 3}
- "recently" → $currentYear

Extract ANY medical facts into this EXACT JSON format:

{
  "entities": [
    {
      "type": "condition|medication|allergy|surgery|lifestyle|vital|family_history",
      "data": {
        // For CONDITION:
        "name": "Diabetes Type 2",
        "status": "active|resolved|managed",
        "onset_year": 2016,
        "severity": "mild|moderate|severe",
        "notes": "original text"
        
        // For MEDICATION:
        "name": "Metformin",
        "dosage": "500",
        "dosage_unit": "mg",
        "frequency": "twice daily",
        "timing": "morning and evening",
        "status": "current|stopped",
        "prescribed_for": "diabetes"
        
        // For ALLERGY:
        "allergen": "Penicillin",
        "type": "drug|food|environmental",
        "reaction": "rash",
        "severity": "moderate"
        
        // For SURGERY:
        "procedure_name": "Appendectomy",
        "year": 2015,
        "outcome": "successful"
        
        // For LIFESTYLE:
        "factor": "smoking|alcohol|exercise|diet",
        "value": "quit 5 years ago",
        "status": "former|current|never"
        
        // For VITAL:
        "type": "blood_pressure|heart_rate|weight|blood_sugar",
        "value": 120,
        "unit": "mmHg"
        
        // For FAMILY_HISTORY:
        "condition": "Heart Disease",
        "relation": "father",
        "age_at_diagnosis": 55
      }
    }
  ]
}

IMPORTANT:
1. Calculate actual YEAR from relative time expressions
2. Only extract MEDICAL facts about the USER
3. If NO medical facts found, return: {"entities": []}
4. Return ONLY valid JSON, no explanation

JSON:''';
  }
  
  String _getLastMonth() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, now.day);
    return '${lastMonth.year}-${lastMonth.month.toString().padLeft(2, '0')}';
  }
  
  /// Parse LLM response and save to database
  Future<ExtractionResult> processLLMResponse(
    String llmResponse, 
    String originalMessage,
  ) async {
    try {
      // Clean the response
      String jsonStr = llmResponse
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      
      // Find JSON boundaries
      final start = jsonStr.indexOf('{');
      final end = jsonStr.lastIndexOf('}');
      
      if (start == -1 || end == -1 || end <= start) {
        return ExtractionResult(success: false, message: 'No valid JSON found');
      }
      
      jsonStr = jsonStr.substring(start, end + 1);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final entities = data['entities'] as List<dynamic>? ?? [];
      
      if (entities.isEmpty) {
        return ExtractionResult(success: true, message: 'No medical facts found', count: 0);
      }
      
      int savedCount = 0;
      final savedEntities = <String>[];
      
      for (final entity in entities) {
        final type = entity['type'] as String?;
        final entityData = entity['data'] as Map<String, dynamic>?;
        
        if (type == null || entityData == null) continue;
        
        try {
          switch (type.toLowerCase()) {
            case 'condition':
              await _saveCondition(entityData, originalMessage);
              savedEntities.add('Condition: ${entityData['name']}');
              savedCount++;
              break;
              
            case 'medication':
              await _saveMedication(entityData, originalMessage);
              savedEntities.add('Medication: ${entityData['name']}');
              savedCount++;
              break;
              
            case 'allergy':
              await _saveAllergy(entityData, originalMessage);
              savedEntities.add('Allergy: ${entityData['allergen']}');
              savedCount++;
              break;
              
            case 'surgery':
              await _saveSurgery(entityData, originalMessage);
              savedEntities.add('Surgery: ${entityData['procedure_name']}');
              savedCount++;
              break;
              
            case 'lifestyle':
              await _saveLifestyle(entityData, originalMessage);
              savedEntities.add('Lifestyle: ${entityData['factor']}');
              savedCount++;
              break;
              
            case 'vital':
              await _saveVital(entityData, originalMessage);
              savedEntities.add('Vital: ${entityData['type']}');
              savedCount++;
              break;
              
            case 'family_history':
              await _saveFamilyHistory(entityData, originalMessage);
              savedEntities.add('Family: ${entityData['condition']} (${entityData['relation']})');
              savedCount++;
              break;
          }
        } catch (e) {
          print('Error saving entity: $e');
        }
      }
      
      // Log the extraction
      await _archiveService.logExtraction(originalMessage, data);
      
      return ExtractionResult(
        success: true,
        message: 'Extracted $savedCount medical facts',
        count: savedCount,
        entities: savedEntities,
      );
      
    } catch (e) {
      print('Extraction error: $e');
      return ExtractionResult(success: false, message: 'Parse error: $e');
    }
  }
  
  Future<void> _saveCondition(Map<String, dynamic> data, String source) async {
    final condition = Condition(
      name: data['name'] as String,
      status: _parseConditionStatus(data['status']),
      onsetYear: data['onset_year'] as int?,
      severity: _parseSeverity(data['severity']),
      notes: data['notes'] as String?,
      createdAt: DateTime.now(),
      sourceMessage: source,
    );
    await _archiveService.addCondition(condition);
  }
  
  Future<void> _saveMedication(Map<String, dynamic> data, String source) async {
    final medication = Medication(
      name: data['name'] as String,
      genericName: data['generic_name'] as String?,
      dosage: data['dosage']?.toString(),
      dosageUnit: data['dosage_unit'] as String?,
      frequency: data['frequency'] as String?,
      timing: data['timing'] as String?,
      status: _parseMedicationStatus(data['status']),
      prescribedFor: data['prescribed_for'] as String?,
      createdAt: DateTime.now(),
      sourceMessage: source,
    );
    await _archiveService.addMedication(medication);
  }
  
  Future<void> _saveAllergy(Map<String, dynamic> data, String source) async {
    final allergy = Allergy(
      allergen: data['allergen'] as String,
      type: _parseAllergyType(data['type']),
      reaction: data['reaction'] as String?,
      severity: _parseSeverity(data['severity']),
      createdAt: DateTime.now(),
      sourceMessage: source,
    );
    await _archiveService.addAllergy(allergy);
  }
  
  Future<void> _saveSurgery(Map<String, dynamic> data, String source) async {
    final surgery = Surgery(
      procedureName: data['procedure_name'] as String,
      year: data['year'] as int?,
      outcome: data['outcome'] as String?,
      createdAt: DateTime.now(),
      sourceMessage: source,
    );
    await _archiveService.addSurgery(surgery);
  }
  
  Future<void> _saveLifestyle(Map<String, dynamic> data, String source) async {
    final factor = LifestyleFactor(
      factor: data['factor'] as String,
      value: data['value'] as String?,
      status: _parseLifestyleStatus(data['status']),
      createdAt: DateTime.now(),
      sourceMessage: source,
    );
    await _archiveService.addLifestyleFactor(factor);
  }
  
  Future<void> _saveVital(Map<String, dynamic> data, String source) async {
    final vital = VitalSign(
      type: _parseVitalType(data['type']),
      value: (data['value'] as num).toDouble(),
      unit: data['unit'] as String?,
      recordedAt: DateTime.now(),
      createdAt: DateTime.now(),
      sourceMessage: source,
    );
    await _archiveService.addVitalSign(vital);
  }
  
  Future<void> _saveFamilyHistory(Map<String, dynamic> data, String source) async {
    final history = FamilyHistory(
      condition: data['condition'] as String,
      relation: _parseFamilyRelation(data['relation']),
      ageAtDiagnosis: data['age_at_diagnosis'] as int?,
      createdAt: DateTime.now(),
      sourceMessage: source,
    );
    await _archiveService.addFamilyHistory(history);
  }
  
  // ==================== PARSERS ====================
  
  ConditionStatus _parseConditionStatus(String? value) {
    if (value == null) return ConditionStatus.active;
    switch (value.toLowerCase()) {
      case 'active': return ConditionStatus.active;
      case 'resolved': return ConditionStatus.resolved;
      case 'managed': return ConditionStatus.managed;
      default: return ConditionStatus.unknown;
    }
  }
  
  MedicationStatus _parseMedicationStatus(String? value) {
    if (value == null) return MedicationStatus.current;
    switch (value.toLowerCase()) {
      case 'current': return MedicationStatus.current;
      case 'stopped': return MedicationStatus.stopped;
      case 'as_needed': 
      case 'asneeded': return MedicationStatus.asNeeded;
      default: return MedicationStatus.unknown;
    }
  }
  
  Severity? _parseSeverity(String? value) {
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'mild': return Severity.mild;
      case 'moderate': return Severity.moderate;
      case 'severe': return Severity.severe;
      case 'critical': return Severity.critical;
      default: return Severity.unknown;
    }
  }
  
  AllergyType _parseAllergyType(String? value) {
    if (value == null) return AllergyType.unknown;
    switch (value.toLowerCase()) {
      case 'drug': return AllergyType.drug;
      case 'food': return AllergyType.food;
      case 'environmental': return AllergyType.environmental;
      case 'insect': return AllergyType.insect;
      case 'latex': return AllergyType.latex;
      default: return AllergyType.unknown;
    }
  }
  
  LifestyleStatus _parseLifestyleStatus(String? value) {
    if (value == null) return LifestyleStatus.current;
    switch (value.toLowerCase()) {
      case 'current': return LifestyleStatus.current;
      case 'former': return LifestyleStatus.former;
      case 'never': return LifestyleStatus.never;
      default: return LifestyleStatus.current;
    }
  }
  
  VitalType _parseVitalType(String? value) {
    if (value == null) return VitalType.other;
    switch (value.toLowerCase().replaceAll('_', '')) {
      case 'bloodpressure':
      case 'bloodpressuresystolic': return VitalType.bloodPressureSystolic;
      case 'bloodpressurediastolic': return VitalType.bloodPressureDiastolic;
      case 'heartrate':
      case 'pulse': return VitalType.heartRate;
      case 'temperature': return VitalType.temperature;
      case 'weight': return VitalType.weight;
      case 'height': return VitalType.height;
      case 'bmi': return VitalType.bmi;
      case 'bloodsugar':
      case 'glucose': return VitalType.bloodSugar;
      case 'oxygensaturation':
      case 'spo2': return VitalType.oxygenSaturation;
      default: return VitalType.other;
    }
  }
  
  FamilyRelation _parseFamilyRelation(String? value) {
    if (value == null) return FamilyRelation.other;
    switch (value.toLowerCase()) {
      case 'father': return FamilyRelation.father;
      case 'mother': return FamilyRelation.mother;
      case 'brother': return FamilyRelation.brother;
      case 'sister': return FamilyRelation.sister;
      case 'grandfather':
      case 'paternalgrandfather': return FamilyRelation.paternalGrandfather;
      case 'grandmother':
      case 'paternalgrandmother': return FamilyRelation.paternalGrandmother;
      case 'maternalgrandfather': return FamilyRelation.maternalGrandfather;
      case 'maternalgrandmother': return FamilyRelation.maternalGrandmother;
      case 'uncle': return FamilyRelation.uncle;
      case 'aunt': return FamilyRelation.aunt;
      case 'cousin': return FamilyRelation.cousin;
      default: return FamilyRelation.other;
    }
  }
}

/// Result of extraction operation
class ExtractionResult {
  final bool success;
  final String message;
  final int count;
  final List<String> entities;
  
  ExtractionResult({
    required this.success,
    required this.message,
    this.count = 0,
    this.entities = const [],
  });
}
