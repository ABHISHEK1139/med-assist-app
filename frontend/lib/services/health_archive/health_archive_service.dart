import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'database.dart';
import 'models.dart';

/// Health Archive Service
/// 
/// Manages the Digital Health Archive - extracts and stores medical
/// information from conversations with proper temporal reasoning.
class HealthArchiveService {
  Database? _db;
  
  /// Initialize the service
  Future<void> initialize() async {
    _db = await HealthArchiveDatabase.database;
  }
  
  // ==================== CONDITIONS ====================
  
  Future<int> addCondition(Condition condition) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.insert('conditions', condition.toMap());
  }
  
  Future<List<Condition>> getConditions({ConditionStatus? status}) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final List<Map<String, dynamic>> maps;
    
    if (status != null) {
      maps = await db.query('conditions', where: 'status = ?', whereArgs: [status.name]);
    } else {
      maps = await db.query('conditions', orderBy: 'onset_year DESC');
    }
    
    return maps.map((m) => Condition.fromMap(m)).toList();
  }
  
  Future<void> updateCondition(Condition condition) async {
    if (condition.id == null) return;
    final db = _db ?? await HealthArchiveDatabase.database;
    await db.update('conditions', condition.toMap(), where: 'id = ?', whereArgs: [condition.id]);
  }
  
  // ==================== MEDICATIONS ====================
  
  Future<int> addMedication(Medication medication) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.insert('medications', medication.toMap());
  }
  
  Future<List<Medication>> getMedications({MedicationStatus? status}) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final List<Map<String, dynamic>> maps;
    
    if (status != null) {
      maps = await db.query('medications', where: 'status = ?', whereArgs: [status.name]);
    } else {
      maps = await db.query('medications', orderBy: 'status, name');
    }
    
    return maps.map((m) => Medication.fromMap(m)).toList();
  }
  
  Future<void> updateMedication(Medication medication) async {
    if (medication.id == null) return;
    final db = _db ?? await HealthArchiveDatabase.database;
    await db.update('medications', medication.toMap(), where: 'id = ?', whereArgs: [medication.id]);
  }
  
  // ==================== ALLERGIES ====================
  
  Future<int> addAllergy(Allergy allergy) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.insert('allergies', allergy.toMap());
  }
  
  Future<List<Allergy>> getAllergies() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final maps = await db.query('allergies');
    return maps.map((m) => Allergy.fromMap(m)).toList();
  }
  
  // ==================== SURGERIES ====================
  
  Future<int> addSurgery(Surgery surgery) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.insert('surgeries', surgery.toMap());
  }
  
  Future<List<Surgery>> getSurgeries() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final maps = await db.query('surgeries', orderBy: 'year DESC, date DESC');
    return maps.map((m) => Surgery.fromMap(m)).toList();
  }
  
  // ==================== VITALS ====================
  
  Future<int> addVitalSign(VitalSign vital) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.insert('vitals', vital.toMap());
  }
  
  Future<List<VitalSign>> getVitals({VitalType? type, int limit = 50}) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final List<Map<String, dynamic>> maps;
    
    if (type != null) {
      maps = await db.query('vitals', 
        where: 'type = ?', 
        whereArgs: [type.name],
        orderBy: 'recorded_at DESC',
        limit: limit,
      );
    } else {
      maps = await db.query('vitals', orderBy: 'recorded_at DESC', limit: limit);
    }
    
    return maps.map((m) => VitalSign.fromMap(m)).toList();
  }
  
  // ==================== LIFESTYLE ====================
  
  Future<int> addLifestyleFactor(LifestyleFactor factor) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.insert('lifestyle', factor.toMap());
  }
  
  Future<List<LifestyleFactor>> getLifestyleFactors() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final maps = await db.query('lifestyle');
    return maps.map((m) => LifestyleFactor.fromMap(m)).toList();
  }
  
  // ==================== FAMILY HISTORY ====================
  
  Future<int> addFamilyHistory(FamilyHistory history) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.insert('family_history', history.toMap());
  }
  
  Future<List<FamilyHistory>> getFamilyHistory() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final maps = await db.query('family_history');
    return maps.map((m) => FamilyHistory.fromMap(m)).toList();
  }
  
  // ==================== FULL PROFILE ====================
  
  Future<HealthProfile> getFullProfile() async {
    return HealthProfile(
      conditions: await getConditions(),
      medications: await getMedications(),
      allergies: await getAllergies(),
      surgeries: await getSurgeries(),
      vitals: await getVitals(limit: 20),
      lifestyle: await getLifestyleFactors(),
      familyHistory: await getFamilyHistory(),
    );
  }
  
  // ==================== SEARCH ====================
  
  Future<List<dynamic>> searchArchive(String query) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    final results = <dynamic>[];
    final searchPattern = '%$query%';
    
    // Search conditions
    final conditions = await db.query('conditions',
      where: 'name LIKE ? OR notes LIKE ?',
      whereArgs: [searchPattern, searchPattern],
    );
    results.addAll(conditions.map((m) => Condition.fromMap(m)));
    
    // Search medications
    final medications = await db.query('medications',
      where: 'name LIKE ? OR generic_name LIKE ? OR notes LIKE ?',
      whereArgs: [searchPattern, searchPattern, searchPattern],
    );
    results.addAll(medications.map((m) => Medication.fromMap(m)));
    
    return results;
  }
  
  // ==================== STATISTICS ====================
  
  Future<Map<String, int>> getArchiveStats() async {
    final db = _db ?? await HealthArchiveDatabase.database;
    
    final conditionCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM conditions')
    ) ?? 0;
    
    final medicationCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM medications WHERE status = "current"')
    ) ?? 0;
    
    final allergyCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM allergies')
    ) ?? 0;
    
    final surgeryCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM surgeries')
    ) ?? 0;
    
    return {
      'conditions': conditionCount,
      'currentMedications': medicationCount,
      'allergies': allergyCount,
      'surgeries': surgeryCount,
    };
  }
  
  // ==================== DELETE ====================
  
  /// Delete an entry by type and ID
  Future<void> deleteEntry(String type, int id) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    
    String table;
    switch (type.toLowerCase()) {
      case 'condition':
      case 'conditions':
        table = 'conditions';
        break;
      case 'medication':
      case 'medications':
        table = 'medications';
        break;
      case 'allergy':
      case 'allergies':
        table = 'allergies';
        break;
      case 'surgery':
      case 'surgeries':
        table = 'surgeries';
        break;
      case 'vital':
      case 'vitals':
        table = 'vitals';
        break;
      case 'lifestyle':
        table = 'lifestyle';
        break;
      case 'family':
      case 'family_history':
        table = 'family_history';
        break;
      default:
        throw ArgumentError('Unknown entity type: $type');
    }
    
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
  
  // ==================== EXTRACTION LOG ====================
  
  /// Log an extraction for debugging/auditing
  Future<void> logExtraction(
    String sourceMessage, 
    Map<String, dynamic> extractedData,
  ) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    await db.insert('extraction_log', {
      'source_message': sourceMessage,
      'extracted_json': jsonEncode(extractedData),
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  
  /// Get extraction history for debugging
  Future<List<Map<String, dynamic>>> getExtractionLog({int limit = 50}) async {
    final db = _db ?? await HealthArchiveDatabase.database;
    return await db.query(
      'extraction_log',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
  
  /// Close the database
  Future<void> close() async {
    await HealthArchiveDatabase.close();
    _db = null;
  }
}
