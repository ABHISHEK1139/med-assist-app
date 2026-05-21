import 'dart:async';
import 'pc_backend_service.dart';
import 'health_archive/health_archive.dart';

/// Unified Med Assist App Service (PC Backend Mode)
/// 
/// Architecture:
/// ┌─────────────────────────────────────────────────────────┐
/// │  📱 PHONE                        💻 PC (Your Laptop)    │
/// │  ┌─────────────────┐             ┌─────────────────┐    │
/// │  │ Health Memory   │ ──────────► │ Gemma-2B GPU    │    │
/// │  │ Symptom Extract │    WiFi     │ Fast inference  │    │
/// │  │ Profile Storage │ ◄────────── │ No data stored  │    │
/// │  └─────────────────┘             └─────────────────┘    │
/// └─────────────────────────────────────────────────────────┘
/// 
/// Phone OWNS data, PC just PROCESSES it
class MedAssistAppService {
  static final MedAssistAppService _instance = MedAssistAppService._internal();
  factory MedAssistAppService() => _instance;
  MedAssistAppService._internal();
  
  final PCBackendService _backendService = PCBackendService();
  final HealthArchiveService _archiveService = HealthArchiveService();
  
  bool _isInitialized = false;
  String? _initError;
  String _pcAddress = '';
  
  bool get isReady => _isInitialized && _backendService.isConnected;
  bool get isLoading => false; // No local model loading needed
  bool get isConnected => _backendService.isConnected;
  String? get error => _initError ?? _backendService.error;
  String get pcAddress => _pcAddress;
  
  /// Initialize the service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      print('🚀 Initializing Med Assist App Service (PC Backend Mode)...');
      
      // 1. Initialize Health Archive (local on phone)
      await _archiveService.initialize();
      print('✅ Health Archive ready (on phone)');
      
      // 2. Initialize PC Backend service
      await _backendService.initialize();
      print('✅ PC Backend service ready');
      
      _isInitialized = true;
      _initError = null;
      print('🎉 Med Assist App initialized! Ready to connect to PC.');
      return true;
      
    } catch (e) {
      _initError = e.toString();
      print('❌ Initialization failed: $e');
      return false;
    }
  }
  
  /// Connect to your PC running the AI model
  Future<bool> connectToPC(String pcAddress, {int port = 8000}) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    _pcAddress = pcAddress;
    final connected = await _backendService.connectToPC(pcAddress, port: port);
    
    if (connected) {
      print('✅ Connected to PC at $pcAddress:$port');
    } else {
      print('❌ Failed to connect to PC');
    }
    
    return connected;
  }
  
  /// Send a chat message - symptoms extracted locally, AI on PC
  /// Uses agentic mode for multi-step reasoning (AI can query DB)
  Future<String> chat(String message, {bool useAgentic = true}) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        return 'Error: $_initError';
      }
    }
    
    if (!_backendService.isConnected) {
      return '''❌ Not connected to PC.

To connect:
1. Start backend on your laptop:
   cd backend
   python main.py --host 0.0.0.0 --port 8000

2. Find laptop IP: ipconfig (look for IPv4)

3. Enter IP in Settings screen

Make sure phone and laptop are on same WiFi!''';
    }
    
    // Use agentic chat for smarter responses
    // AI can query database, save insights, do multi-step reasoning
    if (useAgentic) {
      try {
        final result = await _backendService.agenticChat(message);
        return result.response;
      } catch (e) {
        print('⚠️ Agentic chat failed, falling back to regular: $e');
        // Fall back to regular chat
      }
    }
    
    final result = await _backendService.chat(message);
    return result.response;
  }
  
  /// Simple chat without agentic reasoning (faster but less smart)
  Future<String> simpleChat(String message) async {
    return chat(message, useAgentic: false);
  }
  
  /// Stream chat response
  Stream<String> chatStream(String message) async* {
    final response = await chat(message);
    
    // Simulate streaming for smooth UI
    final words = response.split(' ');
    for (int i = 0; i < words.length; i++) {
      yield words.sublist(0, i + 1).join(' ');
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }
  
  /// Analyze full health history on PC
  Future<String> analyzeFullHistory() async {
    if (!_backendService.isConnected) {
      return 'Not connected to PC';
    }
    
    final result = await _backendService.analyzeFullHistory();
    return result.response;
  }
  
  /// Get user's health profile (from local phone storage)
  Future<HealthProfile> getHealthProfile() async {
    return await _archiveService.getFullProfile();
  }
  
  /// Get archive statistics
  Future<Map<String, int>> getStats() async {
    return await _archiveService.getArchiveStats();
  }
  
  /// Search health archive
  Future<List<dynamic>> searchHealth(String query) async {
    return await _archiveService.searchArchive(query);
  }
  
  /// Check health status (for UI)
  Future<MedAssistAppStatus> checkStatus() async {
    final status = _backendService.checkStatus();
    
    return MedAssistAppStatus(
      isReady: isReady,
      isLoading: false,
      modelLoaded: status.isConnected,
      archiveReady: _isInitialized,
      pcConnected: status.isConnected,
      pcAddress: status.pcAddress,
      error: error,
    );
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await _backendService.dispose();
    await _archiveService.close();
    _isInitialized = false;
  }
}

/// Status of Med Assist App service
class MedAssistAppStatus {
  final bool isReady;
  final bool isLoading;
  final bool modelLoaded;
  final bool archiveReady;
  final bool pcConnected;
  final String pcAddress;
  final String? error;
  
  MedAssistAppStatus({
    required this.isReady,
    required this.isLoading,
    required this.modelLoaded,
    required this.archiveReady,
    this.pcConnected = false,
    this.pcAddress = '',
    this.error,
  });
}
