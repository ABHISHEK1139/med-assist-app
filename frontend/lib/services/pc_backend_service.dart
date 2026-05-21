import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'health_archive/health_archive_service.dart';
import 'health_archive/health_context_builder.dart';
import 'health_archive/symptom_extractor.dart';
import 'health_archive/ai_memory_manager.dart';
import 'health_archive/ai_memory_commands.dart';
import 'health_archive/models.dart';

/// PC Backend Service
/// 
/// Connects phone to your PC running Gemma-2B on RTX 3050.
/// 
/// Architecture (GDPR Compliant):
/// - Phone: Stores all health data, extracts symptoms locally
/// - PC: Runs AI model, processes requests, returns responses
/// - NO data stored on PC - just processes and forgets
/// - AI can REQUEST storage - phone decides to accept/reject
/// 
/// Bidirectional Memory Flow:
/// 1. Phone sends health context → PC processes with AI
/// 2. AI sends response + storage commands → Phone executes approved commands
/// 3. All decisions made by phone (user control)
/// 
/// Benefits:
/// - Faster inference (GPU vs phone CPU)
/// - Larger context windows
/// - All data stays on YOUR devices
/// - AI can learn and store insights (with user consent)
class PCBackendService {
  static final PCBackendService _instance = PCBackendService._internal();
  factory PCBackendService() => _instance;
  PCBackendService._internal();
  
  late final Dio _dio;
  late final HealthArchiveService _archiveService;
  late final HealthContextBuilder _contextBuilder;
  late final SymptomExtractor _symptomExtractor;
  late final AIMemoryManager _aiMemoryManager;
  
  String _pcAddress = '';
  int _port = 8000;
  bool _isInitialized = false;
  bool _isConnected = false;
  String? _error;
  
  bool get isReady => _isInitialized && _isConnected;
  bool get isConnected => _isConnected;
  String? get error => _error;
  String get serverUrl => 'http://$_pcAddress:$_port';
  
  /// Stream of pending AI storage requests (needs user approval)
  Stream<List<AIStorageCommand>> get pendingAICommands => _aiMemoryManager.pendingApprovals;
  
  /// Initialize service with PC address
  Future<bool> initialize({String? pcAddress, int port = 8000}) async {
    if (_isInitialized && pcAddress == null) return _isConnected;
    
    _port = port;
    if (pcAddress != null) {
      _pcAddress = pcAddress;
    }
    
    try {
      print('🚀 Initializing PC Backend Service...');
      
      // 1. Initialize local health archive (on phone)
      _archiveService = HealthArchiveService();
      await _archiveService.initialize();
      print('✅ Health Archive ready (local)');
      
      // 2. Initialize context builder (on phone)
      _contextBuilder = HealthContextBuilder(_archiveService);
      await _contextBuilder.initialize();
      print('✅ Context Builder ready (local)');
      
      // 3. Initialize symptom extractor (on phone)
      _symptomExtractor = SymptomExtractor(_contextBuilder);
      print('✅ Symptom Extractor ready (local)');
      
      // 4. Initialize AI memory manager (bidirectional memory)
      _aiMemoryManager = AIMemoryManager(_contextBuilder);
      await _aiMemoryManager.initialize();
      print('✅ AI Memory Manager ready (bidirectional)');
      
      // 5. Setup HTTP client for PC connection
      // Extended timeouts for mobile hotspot connections (can be slower)
      _dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),   // Increased for hotspot
        receiveTimeout: const Duration(seconds: 300),  // 5 min for AI generation
        sendTimeout: const Duration(seconds: 60),      // Upload health context
        headers: {'Content-Type': 'application/json'},
        validateStatus: (status) => status != null && status < 500,
      ));
      
      // Add retry interceptor for flaky hotspot connections
      _dio.interceptors.add(InterceptorsWrapper(
        onError: (error, handler) async {
          if (_shouldRetry(error) && error.requestOptions.extra['retryCount'] == null) {
            error.requestOptions.extra['retryCount'] = 1;
            print('🔄 Retrying request due to: ${error.type}');
            await Future.delayed(const Duration(seconds: 2));
            try {
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } catch (_) {}
          }
          return handler.next(error);
        },
      ));
      
      _isInitialized = true;
      print('🎉 PC Backend Service initialized!');
      
      // Try to connect if address provided
      if (_pcAddress.isNotEmpty) {
        return await testConnection();
      }
      
      return true;
    } catch (e) {
      _error = e.toString();
      print('❌ Initialization failed: $e');
      return false;
    }
  }
  
  /// Set PC address and test connection
  Future<bool> connectToPC(String pcAddress, {int port = 8000}) async {
    _pcAddress = pcAddress;
    _port = port;
    return await testConnection();
  }
  
  /// Test connection to PC backend
  Future<bool> testConnection() async {
    if (_pcAddress.isEmpty) {
      _error = 'PC address not set';
      return false;
    }
    
    try {
      print('🔗 Testing connection to $serverUrl...');
      final response = await _dio.get('$serverUrl/health');
      
      if (response.statusCode == 200) {
        final data = response.data;
        _isConnected = data['model_ready'] == true;
        
        if (_isConnected) {
          print('✅ Connected to PC! GPU: ${data['gpu_enabled']}');
          _error = null;
        } else {
          _error = 'PC model not ready';
          print('⚠️ Connected but model not ready');
        }
        
        return _isConnected;
      }
    } catch (e) {
      _isConnected = false;
      _error = 'Cannot connect to PC: $e';
      print('❌ Connection failed: $e');
    }
    
    return false;
  }
  
  /// Check if error is retryable (network issues common on hotspots)
  bool _shouldRetry(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
           error.type == DioExceptionType.sendTimeout ||
           error.type == DioExceptionType.receiveTimeout ||
           error.type == DioExceptionType.connectionError;
  }
  
  /// User-friendly error message for common issues
  String _friendlyError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return '⏱️ Connection timeout - PC may be offline or IP incorrect';
        case DioExceptionType.sendTimeout:
          return '⏱️ Send timeout - hotspot connection may be slow';
        case DioExceptionType.receiveTimeout:
          return '⏱️ AI response timeout - try a shorter message';
        case DioExceptionType.connectionError:
          return '🔌 Cannot reach PC - check:\n'
              '• PC and phone on same network\n'
              '• Backend running: python main.py --host 0.0.0.0 --port 8000\n'
              '• Windows Firewall allows port 8000';
        case DioExceptionType.badResponse:
          return '❌ Server error: ${error.response?.statusCode}';
        default:
          return '❌ Network error: ${error.message}';
      }
    }
    return '❌ Error: $error';
  }

  /// Send chat message to PC with local health context
  /// 
  /// Flow:
  /// 1. Extract symptoms locally (on phone)
  /// 2. Build context packet locally (on phone)
  /// 3. Send message + context to PC
  /// 4. PC processes with GPU model
  /// 5. Return response to phone
  Future<PCBackendResponse> chat(String message) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (!_isConnected) {
      return PCBackendResponse(
        response: '❌ Not connected to PC. Please check:\n'
            '1. PC is running: python main.py --host 0.0.0.0 --port 8000\n'
            '2. Phone and PC on same WiFi\n'
            '3. PC address is correct: $_pcAddress',
        error: _error,
      );
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Step 1: Local symptom extraction (on phone)
      final extractedCount = await _symptomExtractor.quickExtractAndSave(message);
      print('📋 Extracted $extractedCount symptoms locally');
      
      // Step 2: Build context packet locally (on phone)
      final contextPacket = await _contextBuilder.buildChatContext(message);
      print('📦 Built context packet locally');
      
      // Step 3: Build full prompt with health context
      final prompt = _buildPromptWithContext(message, contextPacket);
      
      // Step 4: Send to PC for AI processing
      final response = await _dio.post(
        '$serverUrl/chat',
        data: {
          'message': prompt,
          'analysis_type': 'health_with_context',
          'include_context': false, // Context already in prompt
        },
      );
      
      stopwatch.stop();
      
      if (response.statusCode == 200) {
        final aiResponse = response.data['response'] ?? 'No response from AI';
        
        // Step 5: Process AI response for memory commands (bidirectional)
        final processed = await _aiMemoryManager.processAIResponse(aiResponse);
        print('🧠 AI Memory: ${processed.executedCommands.length} commands executed, '
            '${processed.pendingCommands.length} pending approval');
        
        return PCBackendResponse(
          response: processed.response, // Clean response without command markers
          symptomsExtracted: extractedCount,
          contextUsed: contextPacket,
          processingTimeMs: stopwatch.elapsedMilliseconds,
          aiCommandsExecuted: processed.executedCommands.length,
          aiCommandsPending: processed.pendingCommands.length,
        );
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
      
    } catch (e) {
      stopwatch.stop();
      return PCBackendResponse(
        response: _friendlyError(e),
        error: e.toString(),
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    }
  }
  
  /// Send full health history to PC for comprehensive analysis
  Future<PCBackendResponse> analyzeFullHistory() async {
    if (!_isConnected) {
      return PCBackendResponse(
        response: '❌ Not connected to PC',
        error: 'Not connected',
      );
    }
    
    try {
      // Gather all health data from phone
      final profile = await _archiveService.getFullProfile();
      final symptoms = await _contextBuilder.getActiveSymptoms();
      
      // Build comprehensive prompt using profile's toContextString()
      final profileContext = profile.toContextString();
      
      final prompt = '''
Please analyze this patient's complete health profile:

$profileContext

== ACTIVE SYMPTOMS ==
${symptoms.isEmpty ? 'No active symptoms tracked' : symptoms.map((s) => '- ${s.name} (${s.severity.name}, ${_daysSince(s.onsetDate)} days)').join('\n')}

Please provide:
1. Overall health assessment
2. Patterns or concerns you notice
3. Recommendations for the patient
4. Suggested topics to discuss with a doctor

Note: This is for informational purposes only, not medical advice.
''';
      
      final response = await _dio.post(
        '$serverUrl/chat',
        data: {
          'message': prompt,
          'analysis_type': 'comprehensive_analysis',
          'include_context': false,
        },
      );
      
      if (response.statusCode == 200) {
        return PCBackendResponse(
          response: response.data['response'] ?? 'No response',
        );
      }
      
      throw Exception('Server error');
      
    } catch (e) {
      return PCBackendResponse(
        response: '❌ Error: $e',
        error: e.toString(),
      );
    }
  }
  
  // Session ID for server-side conversation memory
  // Server remembers conversation history - app doesn't need to send it
  String? _currentSessionId;
  
  /// Agentic chat - AI can query database and do multi-step reasoning
  /// 
  /// This is the SMART chat mode where AI can:
  /// - Query the phone's health database for more info
  /// - Save important insights
  /// - Do multiple reasoning rounds before answering
  /// - Server REMEMBERS previous messages via session_id
  /// 
  /// All happens "under the hood" - user just sees final response.
  Future<PCBackendResponse> agenticChat(
    String message, {
    List<Map<String, dynamic>>? previousHistory,  // Only when loading old chat
    bool isLoadingHistory = false,  // True when loading from chat history
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (!_isConnected) {
      return PCBackendResponse(
        response: '❌ Not connected to PC',
        error: 'Not connected',
      );
    }
    
    final stopwatch = Stopwatch()..start();
    final toolCalls = <Map<String, dynamic>>[];
    final toolResults = <Map<String, dynamic>>[];
    
    int roundNumber = 0;
    String response = '';
    bool isComplete = false;
    
    // Step 1: Local symptom extraction first (quick pattern matching)
    final extractedCount = await _symptomExtractor.quickExtractAndSave(message);
    print('📋 Extracted $extractedCount symptoms locally');
    
    // Step 2: Build initial health context from phone
    final healthContext = await _buildHealthContextForAgentic();
    print('📦 Built health context: ${healthContext.keys.join(', ')}');
    
    // Step 3: Reasoning loop - max 4 rounds
    while (!isComplete && roundNumber < 4) {
      print('🔄 Agentic round ${roundNumber + 1}... (session: ${_currentSessionId ?? "new"})');
      
      try {
        final requestBody = {
          'message': message,
          'health_context': healthContext,
          'tool_results': toolResults,
          'session_id': _currentSessionId,  // Server remembers history via session
          'round_number': roundNumber,
          // Only send history when LOADING old chat (not every time!)
          if (isLoadingHistory && previousHistory != null && roundNumber == 0)
            'conversation_history': previousHistory,
          if (isLoadingHistory && roundNumber == 0)
            'is_loading_history': true,
        };
        
        final apiResponse = await _dio.post(
          '$serverUrl/chat/agentic',
          data: requestBody,
        );
        
        if (apiResponse.statusCode == 200) {
          final data = apiResponse.data;
          
          response = data['response'] ?? '';
          // Save session_id from server (it remembers our conversation)
          _currentSessionId = data['session_id'];
          isComplete = data['is_complete'] ?? true;
          roundNumber = data['round_number'] ?? roundNumber + 1;
          
          final newToolCalls = (data['tool_calls'] as List<dynamic>?) ?? [];
          
          if (newToolCalls.isEmpty) {
            isComplete = true;
            print('✅ No more tools needed, response ready');
          } else {
            // Execute tools on phone
            print('🔧 Executing ${newToolCalls.length} tool(s)...');
            toolCalls.addAll(newToolCalls.cast<Map<String, dynamic>>());
            
            for (final tc in newToolCalls) {
              final result = await _executeTool(tc as Map<String, dynamic>);
              toolResults.add(result);
              print('   ${tc['tool']}: ${result['success'] ? "✅" : "❌"}');
            }
          }
        } else {
          throw Exception('API error: ${apiResponse.statusCode}');
        }
        
      } catch (e) {
        print('❌ Error in agentic round $roundNumber: $e');
        // Fall back to regular chat
        response = await _fallbackToRegularChat(message);
        isComplete = true;
      }
    }
    
    stopwatch.stop();
    
    // Process AI memory commands in response
    final processed = await _aiMemoryManager.processAIResponse(response);
    
    // No need to track history client-side - server remembers via session_id!
    
    return PCBackendResponse(
      response: processed.response,
      symptomsExtracted: extractedCount,
      processingTimeMs: stopwatch.elapsedMilliseconds,
      aiCommandsExecuted: processed.executedCommands.length + toolCalls.length,
      aiCommandsPending: processed.pendingCommands.length,
    );
  }
  
  /// Load chat session from app's history into server memory
  /// Call this ONCE when user opens an old chat from history
  /// Then server maintains memory for the rest of the session
  Future<void> loadChatSession(List<Map<String, dynamic>> messages, {String? sessionId}) async {
    if (!_isConnected) {
      print('⚠️ Not connected, cannot load chat session');
      return;
    }
    
    _currentSessionId = sessionId;
    
    if (messages.isEmpty) {
      print('📭 No messages to load');
      return;
    }
    
    print('📚 Loading ${messages.length} messages into server memory...');
    
    // Send a dummy request with history to initialize server memory
    try {
      final requestBody = {
        'message': '[SYSTEM] Loading previous conversation',
        'health_context': {},
        'tool_results': [],
        'session_id': _currentSessionId,
        'round_number': 0,
        'conversation_history': messages,
        'is_loading_history': true,
      };
      
      final response = await _dio.post(
        '$serverUrl/chat/agentic',
        data: requestBody,
      );
      
      if (response.statusCode == 200) {
        _currentSessionId = response.data['session_id'];
        print('✅ Chat session loaded into server (session: $_currentSessionId)');
      }
    } catch (e) {
      print('⚠️ Failed to load chat session: $e');
    }
  }
  
  /// Convert ChatMessage list to format for server
  static List<Map<String, dynamic>> messagesToHistory(List<dynamic> messages) {
    return messages.map((m) => {
      'role': m.isUser ? 'user' : 'assistant',
      'content': m.content,
      'timestamp': m.timestamp.toIso8601String(),
    }).toList();
  }
  
  /// Clear conversation session (call when starting new chat)
  /// This tells the server to forget the conversation history
  Future<void> clearConversationSession() async {
    if (_currentSessionId != null && _isConnected) {
      try {
        await _dio.post(
          '$serverUrl/chat/session/clear',
          queryParameters: {'session_id': _currentSessionId},
        );
        print('🗑️ Server session cleared: $_currentSessionId');
      } catch (e) {
        print('⚠️ Failed to clear server session: $e');
      }
    }
    _currentSessionId = null;
    print('🆕 Ready for new conversation');
  }
  
  /// Upload a document to PC backend for OCR extraction and analysis
  /// Returns extracted text and AI analysis
  Future<DocumentUploadResult> uploadDocument({
    required String filePath,
    required String fileName,
    required List<int> fileBytes,
    String? docType,
    String? userMessage,
  }) async {
    if (!_isConnected) {
      return DocumentUploadResult(
        success: false,
        error: 'Not connected to PC',
      );
    }
    
    try {
      print('📤 Uploading document: $fileName');
      
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
        ),
        if (docType != null) 'doc_type': docType,
      });
      
      final response = await _dio.post(
        '$serverUrl/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        final docId = data['doc_id'] as String?;
        final extractedDocType = data['doc_type'] as String?;
        final message = data['message'] as String?;
        final chunks = data['chunks_created'] as int? ?? 0;
        
        print('✅ Document uploaded: $docId ($chunks chunks)');
        
        // Now let's analyze the document with AI if there's a user message
        String? aiAnalysis;
        if (userMessage != null && userMessage.isNotEmpty && docId != null) {
          final analysisResult = await agenticChat(
            '$userMessage\n\n[Document ID: $docId - $extractedDocType]',
          );
          aiAnalysis = analysisResult.response;
        } else if (docId != null) {
          // Auto-analyze the document
          final analysisResult = await agenticChat(
            'I just uploaded a document (${extractedDocType ?? "unknown type"}). '
            'Please analyze it and tell me what you found. '
            'Document ID: $docId',
          );
          aiAnalysis = analysisResult.response;
        }
        
        return DocumentUploadResult(
          success: true,
          docId: docId,
          docType: extractedDocType,
          message: message ?? 'Document processed',
          chunksCreated: chunks,
          aiAnalysis: aiAnalysis,
        );
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Document upload failed: $e');
      return DocumentUploadResult(
        success: false,
        error: _friendlyError(e),
      );
    }
  }
  
  /// Build health context for agentic chat
  Future<Map<String, dynamic>> _buildHealthContextForAgentic() async {
    final symptoms = await _contextBuilder.getActiveSymptoms();
    final conditions = await _archiveService.getConditions();
    final medications = await _archiveService.getMedications();
    final allergies = await _archiveService.getAllergies();
    
    return {
      'symptoms': symptoms.map((s) => {
        'name': s.name,
        'severity': s.severity.name,
        'onset_date': s.onsetDate.toIso8601String(),
        'days_active': DateTime.now().difference(s.onsetDate).inDays,
        'notes': s.notes,
      }).toList(),
      'conditions': conditions.map((c) => {
        'name': c.name,
        'status': c.status.name,
        'onset_date': c.onsetDate?.toIso8601String(),
      }).toList(),
      'medications': medications.map((m) => {
        'name': m.name,
        'dosage': m.dosage,
        'frequency': m.frequency,
        'status': m.status.name,
      }).toList(),
      'allergies': allergies.map((a) => {
        'allergen': a.allergen,
        'severity': a.severity?.name ?? 'unknown',
        'reaction': a.reaction,
      }).toList(),
      'current_time': DateTime.now().toIso8601String(),
    };
  }
  
  /// Execute a tool requested by AI
  Future<Map<String, dynamic>> _executeTool(Map<String, dynamic> toolCall) async {
    final tool = toolCall['tool'] as String? ?? '';
    final params = (toolCall['params'] as Map<String, dynamic>?) ?? {};
    
    try {
      switch (tool.toLowerCase()) {
        case 'query_symptoms':
          final symptoms = await _contextBuilder.getActiveSymptoms();
          return {
            'tool': tool,
            'success': true,
            'data': symptoms.map((s) => {
              'name': s.name,
              'severity': s.severity.name,
              'days_active': DateTime.now().difference(s.onsetDate).inDays,
              'notes': s.notes,
            }).toList(),
          };
          
        case 'query_conditions':
          final conditions = await _archiveService.getConditions();
          return {
            'tool': tool,
            'success': true,
            'data': conditions.map((c) => {
              'name': c.name,
              'status': c.status.name,
            }).toList(),
          };
          
        case 'query_medications':
          final medications = await _archiveService.getMedications();
          return {
            'tool': tool,
            'success': true,
            'data': medications.map((m) => {
              'name': m.name,
              'dosage': m.dosage,
              'frequency': m.frequency,
              'status': m.status.name,
            }).toList(),
          };
          
        case 'query_allergies':
          final allergies = await _archiveService.getAllergies();
          return {
            'tool': tool,
            'success': true,
            'data': allergies.map((a) => {
              'allergen': a.allergen,
              'severity': a.severity?.name,
            }).toList(),
          };
          
        case 'save_symptom':
          final name = params['name'] ?? 'Unknown';
          final severityStr = params['severity'] ?? 'moderate';
          final notes = params['notes'] ?? '';
          
          final severity = Severity.values.firstWhere(
            (s) => s.name.toLowerCase() == severityStr.toLowerCase(),
            orElse: () => Severity.moderate,
          );
          
          await _contextBuilder.trackSymptom(ActiveSymptom(
            name: name,
            severity: severity,
            onsetDate: DateTime.now(),
            notes: notes,
          ));
          
          return {
            'tool': tool,
            'success': true,
            'data': {'saved': name},
          };
          
        case 'resolve_symptom':
          final name = params['name'] ?? '';
          if (name.isNotEmpty) {
            await _contextBuilder.resolveSymptom(name);
          }
          return {
            'tool': tool,
            'success': true,
            'data': {'resolved': name},
          };
          
        case 'save_insight':
          // For now just log it - could add insights table later
          final insight = params['insight'] ?? '';
          print('💡 AI Insight: $insight');
          return {
            'tool': tool,
            'success': true,
            'data': {'insight_saved': true},
          };
          
        default:
          return {
            'tool': tool,
            'success': false,
            'error': 'Unknown tool',
          };
      }
    } catch (e) {
      return {
        'tool': tool,
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// Fallback to regular chat if agentic fails
  Future<String> _fallbackToRegularChat(String message) async {
    try {
      final result = await chat(message);
      return result.response;
    } catch (e) {
      return 'Sorry, I encountered an error processing your request.';
    }
  }
  
  /// Build prompt with health context
  String _buildPromptWithContext(String message, ChatContextPacket context) {
    final buffer = StringBuffer();
    
    buffer.writeln('You are a helpful medical AI assistant. Answer the patient\'s question using the provided health context.');
    buffer.writeln();
    
    // Add minimal relevant context
    if (context.activeSymptoms.isNotEmpty) {
      buffer.writeln('Current Symptoms: ${context.activeSymptoms.map((s) => s.name).join(", ")}');
    }
    
    if (context.chronicConditions.isNotEmpty) {
      buffer.writeln('Known Conditions: ${context.chronicConditions.join(", ")}');
    }
    
    if (context.currentMedications.isNotEmpty) {
      buffer.writeln('Current Medications: ${context.currentMedications.join(", ")}');
    }
    
    if (context.allergies.isNotEmpty) {
      buffer.writeln('Allergies: ${context.allergies.join(", ")}');
    }
    
    buffer.writeln();
    buffer.writeln('Patient Question: $message');
    buffer.writeln();
    buffer.writeln('Provide a helpful, accurate response. Always recommend consulting a healthcare professional for specific medical advice.');
    
    return buffer.toString();
  }
  
  String _daysSince(DateTime date) {
    return DateTime.now().difference(date).inDays.toString();
  }
  
  /// Get health profile (from local storage)
  Future<HealthProfile> getHealthProfile() async {
    return await _archiveService.getFullProfile();
  }
  
  /// Get archive stats (from local storage)
  Future<Map<String, int>> getStats() async {
    return await _archiveService.getArchiveStats();
  }
  
  /// Get active symptoms (from local storage)
  Future<List<ActiveSymptom>> getActiveSymptoms() async {
    return await _contextBuilder.getActiveSymptoms();
  }
  
  /// Check status
  PCBackendStatus checkStatus() {
    return PCBackendStatus(
      isInitialized: _isInitialized,
      isConnected: _isConnected,
      pcAddress: _pcAddress,
      port: _port,
      error: _error,
    );
  }
  
  // ============== AI Memory Management (GDPR Compliant) ==============
  
  /// Get AI insights stored on phone
  Future<List<Map<String, dynamic>>> getAIInsights() async {
    return await _aiMemoryManager.getActiveInsights();
  }
  
  /// Get AI warnings that need attention
  Future<List<Map<String, dynamic>>> getAIWarnings() async {
    return await _aiMemoryManager.getActiveWarnings();
  }
  
  /// Get conditions AI is watching for
  Future<List<Map<String, dynamic>>> getConditionWatchList() async {
    return await _aiMemoryManager.getConditionWatchList();
  }
  
  /// Approve pending AI storage command
  Future<void> approveAICommand(AIStorageCommand command) async {
    await _aiMemoryManager.approveCommand(command);
  }
  
  /// Reject pending AI storage command
  Future<void> rejectAICommand(AIStorageCommand command) async {
    await _aiMemoryManager.rejectCommand(command);
  }
  
  /// Acknowledge an AI warning
  Future<void> acknowledgeWarning(int warningId) async {
    await _aiMemoryManager.acknowledgeWarning(warningId);
  }
  
  /// Get AI memory audit log (GDPR transparency)
  Future<List<Map<String, dynamic>>> getAIMemoryLog() async {
    return await _aiMemoryManager.getMemoryLog();
  }
  
  /// GDPR: Clear all AI-stored data (Right to Erasure)
  Future<void> clearAllAIData() async {
    await _aiMemoryManager.clearAllAIData();
  }
  
  /// GDPR: Export all AI-stored data (Right to Portability)
  Future<Map<String, dynamic>> exportAllAIData() async {
    return await _aiMemoryManager.exportAllAIData();
  }
  
  /// Update AI memory settings
  void updateAIMemorySettings(AIMemorySettings settings) {
    _aiMemoryManager.updateSettings(settings);
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await _archiveService.close();
    _aiMemoryManager.dispose();
    _dio.close();
    _isInitialized = false;
    _isConnected = false;
  }
}

/// Response from PC backend
class PCBackendResponse {
  final String response;
  final int symptomsExtracted;
  final ChatContextPacket? contextUsed;
  final int processingTimeMs;
  final String? error;
  final int aiCommandsExecuted;
  final int aiCommandsPending;
  
  PCBackendResponse({
    required this.response,
    this.symptomsExtracted = 0,
    this.contextUsed,
    this.processingTimeMs = 0,
    this.error,
    this.aiCommandsExecuted = 0,
    this.aiCommandsPending = 0,
  });
  
  bool get hasError => error != null;
  bool get hasAICommands => aiCommandsExecuted > 0 || aiCommandsPending > 0;
}

/// Result of document upload to PC backend
class DocumentUploadResult {
  final bool success;
  final String? docId;
  final String? docType;
  final String? message;
  final int chunksCreated;
  final String? aiAnalysis;
  final String? error;
  
  DocumentUploadResult({
    required this.success,
    this.docId,
    this.docType,
    this.message,
    this.chunksCreated = 0,
    this.aiAnalysis,
    this.error,
  });
}

/// Status of PC Backend connection
class PCBackendStatus {
  final bool isInitialized;
  final bool isConnected;
  final String pcAddress;
  final int port;
  final String? error;
  
  PCBackendStatus({
    required this.isInitialized,
    required this.isConnected,
    required this.pcAddress,
    required this.port,
    this.error,
  });
  
  String get serverUrl => 'http://$pcAddress:$port';
}
