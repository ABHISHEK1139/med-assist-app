library health_archive_models;

/// Data models for the Digital Health Archive
/// 
/// These models represent all medical information extracted from conversations.

import 'package:equatable/equatable.dart';

/// Base class for all medical entities
abstract class MedicalEntity extends Equatable {
  final int? id;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? sourceMessage;
  
  const MedicalEntity({
    this.id,
    required this.createdAt,
    this.updatedAt,
    this.sourceMessage,
  });
}

/// Medical Condition (Disease/Diagnosis)
class Condition extends MedicalEntity {
  final String name;
  final ConditionStatus status;
  final DateTime? onsetDate;
  final int? onsetYear;
  final String? diagnosedBy;
  final Severity? severity;
  final String? notes;
  
  const Condition({
    super.id,
    required this.name,
    this.status = ConditionStatus.active,
    this.onsetDate,
    this.onsetYear,
    this.diagnosedBy,
    this.severity,
    this.notes,
    required super.createdAt,
    super.updatedAt,
    super.sourceMessage,
  });
  
  @override
  List<Object?> get props => [id, name, status, onsetDate, onsetYear];
  
  Map<String, dynamic> toMap() => {
    'name': name,
    'status': status.name,
    'onset_date': onsetDate?.toIso8601String(),
    'onset_year': onsetYear,
    'diagnosed_by': diagnosedBy,
    'severity': severity?.name,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'source_message': sourceMessage,
  };
  
  factory Condition.fromMap(Map<String, dynamic> map) => Condition(
    id: map['id'] as int?,
    name: map['name'] as String,
    status: ConditionStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => ConditionStatus.active,
    ),
    onsetDate: map['onset_date'] != null ? DateTime.tryParse(map['onset_date']) : null,
    onsetYear: map['onset_year'] as int?,
    diagnosedBy: map['diagnosed_by'] as String?,
    severity: map['severity'] != null 
        ? Severity.values.firstWhere((e) => e.name == map['severity'], orElse: () => Severity.unknown)
        : null,
    notes: map['notes'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    sourceMessage: map['source_message'] as String?,
  );
}

enum ConditionStatus { active, resolved, managed, unknown }
enum Severity { mild, moderate, severe, critical, unknown }

/// Medication
class Medication extends MedicalEntity {
  final String name;
  final String? genericName;
  final String? dosage;
  final String? dosageUnit;
  final String? frequency;
  final String? timing; // morning, evening, with food, etc.
  final String route; // oral, injection, topical, etc.
  final MedicationStatus status;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? prescribedFor;
  final String? prescribedBy;
  final String? notes;
  
  const Medication({
    super.id,
    required this.name,
    this.genericName,
    this.dosage,
    this.dosageUnit,
    this.frequency,
    this.timing,
    this.route = 'oral',
    this.status = MedicationStatus.current,
    this.startDate,
    this.endDate,
    this.prescribedFor,
    this.prescribedBy,
    this.notes,
    required super.createdAt,
    super.updatedAt,
    super.sourceMessage,
  });
  
  @override
  List<Object?> get props => [id, name, dosage, status];
  
  Map<String, dynamic> toMap() => {
    'name': name,
    'generic_name': genericName,
    'dosage': dosage,
    'dosage_unit': dosageUnit,
    'frequency': frequency,
    'timing': timing,
    'route': route,
    'status': status.name,
    'start_date': startDate?.toIso8601String(),
    'end_date': endDate?.toIso8601String(),
    'prescribed_for': prescribedFor,
    'prescribed_by': prescribedBy,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'source_message': sourceMessage,
  };
  
  factory Medication.fromMap(Map<String, dynamic> map) => Medication(
    id: map['id'] as int?,
    name: map['name'] as String,
    genericName: map['generic_name'] as String?,
    dosage: map['dosage'] as String?,
    dosageUnit: map['dosage_unit'] as String?,
    frequency: map['frequency'] as String?,
    timing: map['timing'] as String?,
    route: map['route'] as String? ?? 'oral',
    status: MedicationStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => MedicationStatus.current,
    ),
    startDate: map['start_date'] != null ? DateTime.tryParse(map['start_date']) : null,
    endDate: map['end_date'] != null ? DateTime.tryParse(map['end_date']) : null,
    prescribedFor: map['prescribed_for'] as String?,
    prescribedBy: map['prescribed_by'] as String?,
    notes: map['notes'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    sourceMessage: map['source_message'] as String?,
  );
}

enum MedicationStatus { current, stopped, asNeeded, unknown }

/// Allergy
class Allergy extends MedicalEntity {
  final String allergen;
  final AllergyType? type;
  final String? reaction;
  final Severity? severity;
  final DateTime? discoveredDate;
  final String? notes;
  
  const Allergy({
    super.id,
    required this.allergen,
    this.type,
    this.reaction,
    this.severity,
    this.discoveredDate,
    this.notes,
    required super.createdAt,
    super.sourceMessage,
  });
  
  @override
  List<Object?> get props => [id, allergen, type];
  
  Map<String, dynamic> toMap() => {
    'allergen': allergen,
    'type': type?.name,
    'reaction': reaction,
    'severity': severity?.name,
    'discovered_date': discoveredDate?.toIso8601String(),
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'source_message': sourceMessage,
  };
  
  factory Allergy.fromMap(Map<String, dynamic> map) => Allergy(
    id: map['id'] as int?,
    allergen: map['allergen'] as String,
    type: map['type'] != null 
        ? AllergyType.values.firstWhere((e) => e.name == map['type'], orElse: () => AllergyType.unknown)
        : null,
    reaction: map['reaction'] as String?,
    severity: map['severity'] != null 
        ? Severity.values.firstWhere((e) => e.name == map['severity'], orElse: () => Severity.unknown)
        : null,
    discoveredDate: map['discovered_date'] != null ? DateTime.tryParse(map['discovered_date']) : null,
    notes: map['notes'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    sourceMessage: map['source_message'] as String?,
  );
}

enum AllergyType { drug, food, environmental, insect, latex, unknown }

/// Surgery/Procedure
class Surgery extends MedicalEntity {
  final String procedureName;
  final DateTime? date;
  final int? year;
  final String? hospital;
  final String? surgeon;
  final String? outcome;
  final String? complications;
  final String? notes;
  
  const Surgery({
    super.id,
    required this.procedureName,
    this.date,
    this.year,
    this.hospital,
    this.surgeon,
    this.outcome,
    this.complications,
    this.notes,
    required super.createdAt,
    super.sourceMessage,
  });
  
  @override
  List<Object?> get props => [id, procedureName, date, year];
  
  Map<String, dynamic> toMap() => {
    'procedure_name': procedureName,
    'date': date?.toIso8601String(),
    'year': year,
    'hospital': hospital,
    'surgeon': surgeon,
    'outcome': outcome,
    'complications': complications,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'source_message': sourceMessage,
  };
  
  factory Surgery.fromMap(Map<String, dynamic> map) => Surgery(
    id: map['id'] as int?,
    procedureName: map['procedure_name'] as String,
    date: map['date'] != null ? DateTime.tryParse(map['date']) : null,
    year: map['year'] as int?,
    hospital: map['hospital'] as String?,
    surgeon: map['surgeon'] as String?,
    outcome: map['outcome'] as String?,
    complications: map['complications'] as String?,
    notes: map['notes'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    sourceMessage: map['source_message'] as String?,
  );
}

/// Vital Signs
class VitalSign extends MedicalEntity {
  final VitalType type;
  final double value;
  final String? unit;
  final DateTime recordedAt;
  final String? notes;
  
  const VitalSign({
    super.id,
    required this.type,
    required this.value,
    this.unit,
    required this.recordedAt,
    this.notes,
    required super.createdAt,
    super.sourceMessage,
  });
  
  @override
  List<Object?> get props => [id, type, value, recordedAt];
  
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'value': value,
    'unit': unit,
    'recorded_at': recordedAt.toIso8601String(),
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'source_message': sourceMessage,
  };
  
  factory VitalSign.fromMap(Map<String, dynamic> map) => VitalSign(
    id: map['id'] as int?,
    type: VitalType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => VitalType.other,
    ),
    value: (map['value'] as num).toDouble(),
    unit: map['unit'] as String?,
    recordedAt: DateTime.tryParse(map['recorded_at'] ?? '') ?? DateTime.now(),
    notes: map['notes'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    sourceMessage: map['source_message'] as String?,
  );
}

enum VitalType { 
  bloodPressureSystolic,
  bloodPressureDiastolic,
  heartRate,
  temperature,
  weight,
  height,
  bmi,
  bloodSugar,
  oxygenSaturation,
  respiratoryRate,
  other
}

/// Lifestyle Factor
class LifestyleFactor extends MedicalEntity {
  final String factor;
  final String? value;
  final String? frequency;
  final DateTime? startDate;
  final DateTime? endDate;
  final LifestyleStatus status;
  final String? notes;
  
  const LifestyleFactor({
    super.id,
    required this.factor,
    this.value,
    this.frequency,
    this.startDate,
    this.endDate,
    this.status = LifestyleStatus.current,
    this.notes,
    required super.createdAt,
    super.sourceMessage,
  });
  
  @override
  List<Object?> get props => [id, factor, status];
  
  Map<String, dynamic> toMap() => {
    'factor': factor,
    'value': value,
    'frequency': frequency,
    'start_date': startDate?.toIso8601String(),
    'end_date': endDate?.toIso8601String(),
    'status': status.name,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'source_message': sourceMessage,
  };
  
  factory LifestyleFactor.fromMap(Map<String, dynamic> map) => LifestyleFactor(
    id: map['id'] as int?,
    factor: map['factor'] as String,
    value: map['value'] as String?,
    frequency: map['frequency'] as String?,
    startDate: map['start_date'] != null ? DateTime.tryParse(map['start_date']) : null,
    endDate: map['end_date'] != null ? DateTime.tryParse(map['end_date']) : null,
    status: LifestyleStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => LifestyleStatus.current,
    ),
    notes: map['notes'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    sourceMessage: map['source_message'] as String?,
  );
}

enum LifestyleStatus { current, former, never }

/// Family History Entry
class FamilyHistory extends MedicalEntity {
  final String condition;
  final FamilyRelation relation;
  final int? ageAtDiagnosis;
  final String? notes;
  
  const FamilyHistory({
    super.id,
    required this.condition,
    required this.relation,
    this.ageAtDiagnosis,
    this.notes,
    required super.createdAt,
    super.sourceMessage,
  });
  
  @override
  List<Object?> get props => [id, condition, relation];
  
  Map<String, dynamic> toMap() => {
    'condition': condition,
    'relation': relation.name,
    'age_at_diagnosis': ageAtDiagnosis,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'source_message': sourceMessage,
  };
  
  factory FamilyHistory.fromMap(Map<String, dynamic> map) => FamilyHistory(
    id: map['id'] as int?,
    condition: map['condition'] as String,
    relation: FamilyRelation.values.firstWhere(
      (e) => e.name == map['relation'],
      orElse: () => FamilyRelation.other,
    ),
    ageAtDiagnosis: map['age_at_diagnosis'] as int?,
    notes: map['notes'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    sourceMessage: map['source_message'] as String?,
  );
}

enum FamilyRelation { 
  father, mother, brother, sister, 
  paternalGrandfather, paternalGrandmother,
  maternalGrandfather, maternalGrandmother,
  uncle, aunt, cousin, other 
}

/// Complete Health Profile Summary
class HealthProfile {
  final List<Condition> conditions;
  final List<Medication> medications;
  final List<Allergy> allergies;
  final List<Surgery> surgeries;
  final List<VitalSign> vitals;
  final List<LifestyleFactor> lifestyle;
  final List<FamilyHistory> familyHistory;
  
  const HealthProfile({
    this.conditions = const [],
    this.medications = const [],
    this.allergies = const [],
    this.surgeries = const [],
    this.vitals = const [],
    this.lifestyle = const [],
    this.familyHistory = const [],
  });
  
  /// Check if profile is empty
  bool get isEmpty => 
      conditions.isEmpty && 
      medications.isEmpty && 
      allergies.isEmpty && 
      surgeries.isEmpty && 
      vitals.isEmpty && 
      lifestyle.isEmpty && 
      familyHistory.isEmpty;
  
  /// Get current medications only
  List<Medication> get currentMedications => 
      medications.where((m) => m.status == MedicationStatus.current).toList();
  
  /// Get active conditions only  
  List<Condition> get activeConditions =>
      conditions.where((c) => c.status == ConditionStatus.active).toList();
  
  /// Summary text for AI context
  String toContextString() {
    final buffer = StringBuffer();
    
    if (activeConditions.isNotEmpty) {
      buffer.writeln('Active Conditions:');
      for (final c in activeConditions) {
        final onset = c.onsetYear != null ? ' (since ${c.onsetYear})' : '';
        buffer.writeln('- ${c.name}$onset');
      }
    }
    
    if (currentMedications.isNotEmpty) {
      buffer.writeln('Current Medications:');
      for (final m in currentMedications) {
        final dose = m.dosage != null ? ' ${m.dosage}' : '';
        final freq = m.frequency != null ? ' ${m.frequency}' : '';
        buffer.writeln('- ${m.name}$dose$freq');
      }
    }
    
    if (allergies.isNotEmpty) {
      buffer.writeln('Allergies:');
      for (final a in allergies) {
        buffer.writeln('- ${a.allergen}');
      }
    }
    
    return buffer.toString();
  }
}
