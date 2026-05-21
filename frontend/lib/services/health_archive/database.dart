import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

/// Digital Health Archive - Local SQLite Database
/// 
/// Stores the complete medical history extracted from conversations.
/// 100% On-Device - Your health data never leaves your phone.
/// 
/// ⚠️ DATA PERSISTS EVEN AFTER APP UNINSTALL
/// Stored in: /storage/emulated/0/Documents/Med Assist App/
class HealthArchiveDatabase {
  static Database? _database;
  static const String _dbName = 'health_archive.db';
  static const int _dbVersion = 1;
  static const String _appFolder = 'Med Assist App';
  
  /// Get database instance
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  /// Get the persistent storage path (survives app uninstall)
  static Future<String> _getPersistentPath() async {
    // Request storage permission
    await _requestPermissions();
    
    // Use shared Documents folder - survives app uninstall!
    // Path: /storage/emulated/0/Documents/Med Assist App/
    String basePath;
    
    if (Platform.isAndroid) {
      // Try external storage first (survives uninstall)
      basePath = '/storage/emulated/0/Documents/$_appFolder';
    } else {
      // iOS/Desktop fallback
      final docs = await getApplicationDocumentsDirectory();
      basePath = '${docs.path}/$_appFolder';
    }
    
    // Create directory if doesn't exist
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    return basePath;
  }
  
  /// Request necessary permissions
  static Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Check Android version
      if (await Permission.manageExternalStorage.isGranted) {
        return;
      }
      
      // Request storage permissions
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        // Try manage external storage for Android 11+
        await Permission.manageExternalStorage.request();
      }
    }
  }
  
  /// Initialize the database in persistent location
  static Future<Database> _initDatabase() async {
    final persistentPath = await _getPersistentPath();
    final path = '$persistentPath/$_dbName';
    
    print('📁 Health Archive DB: $path');
    
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );
  }
  
  /// Create all tables
  static Future<void> _createTables(Database db, int version) async {
    // Medical Conditions (Diseases)
    await db.execute('''
      CREATE TABLE conditions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        status TEXT DEFAULT 'active',
        onset_date TEXT,
        onset_year INTEGER,
        diagnosed_by TEXT,
        severity TEXT,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        source_message TEXT
      )
    ''');
    
    // Medications
    await db.execute('''
      CREATE TABLE medications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        generic_name TEXT,
        dosage TEXT,
        dosage_unit TEXT,
        frequency TEXT,
        timing TEXT,
        route TEXT DEFAULT 'oral',
        status TEXT DEFAULT 'current',
        start_date TEXT,
        end_date TEXT,
        prescribed_for TEXT,
        prescribed_by TEXT,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        source_message TEXT
      )
    ''');
    
    // Allergies
    await db.execute('''
      CREATE TABLE allergies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        allergen TEXT NOT NULL,
        type TEXT,
        reaction TEXT,
        severity TEXT,
        discovered_date TEXT,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        source_message TEXT
      )
    ''');
    
    // Surgeries / Procedures
    await db.execute('''
      CREATE TABLE surgeries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        procedure_name TEXT NOT NULL,
        date TEXT,
        year INTEGER,
        hospital TEXT,
        surgeon TEXT,
        outcome TEXT,
        complications TEXT,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        source_message TEXT
      )
    ''');
    
    // Vital Signs History
    await db.execute('''
      CREATE TABLE vitals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT,
        recorded_at TEXT DEFAULT CURRENT_TIMESTAMP,
        notes TEXT,
        source_message TEXT
      )
    ''');
    
    // Lifestyle Factors
    await db.execute('''
      CREATE TABLE lifestyle (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        factor TEXT NOT NULL,
        value TEXT,
        frequency TEXT,
        start_date TEXT,
        end_date TEXT,
        status TEXT DEFAULT 'current',
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        source_message TEXT
      )
    ''');
    
    // Family Medical History
    await db.execute('''
      CREATE TABLE family_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        condition TEXT NOT NULL,
        relation TEXT NOT NULL,
        age_at_diagnosis INTEGER,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        source_message TEXT
      )
    ''');
    
    // Lab Results
    await db.execute('''
      CREATE TABLE lab_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        test_name TEXT NOT NULL,
        value TEXT,
        unit TEXT,
        reference_range TEXT,
        status TEXT,
        test_date TEXT,
        lab_name TEXT,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        source_message TEXT
      )
    ''');
    
    // Conversation Extractions Log
    await db.execute('''
      CREATE TABLE extraction_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        extracted_entities TEXT,
        extraction_date TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // Create indexes for fast searching
    await db.execute('CREATE INDEX idx_conditions_name ON conditions(name)');
    await db.execute('CREATE INDEX idx_medications_name ON medications(name)');
    await db.execute('CREATE INDEX idx_medications_status ON medications(status)');
    await db.execute('CREATE INDEX idx_vitals_type ON vitals(type)');
  }
  
  /// Handle database upgrades
  static Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    // Add migration logic here for future versions
  }
  
  /// Close database
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
