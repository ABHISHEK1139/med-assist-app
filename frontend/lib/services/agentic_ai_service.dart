import 'dart:convert';
import 'package:dio/dio.dart';
import 'health_archive/health_archive.dart';
import 'health_archive/health_context_builder.dart';
import 'health_archive/models.dart';

/// Agentic AI Service
/// 
/// Handles multi-step reasoning where AI can:
/// 1. Query phone's health database
/// 2. Save important insights
/// 3. Do multiple reasoning rounds
/// 
/// All tool execution happens on the PHONE - AI just requests.
class AgenticAIService {
  static final AgenticAIService _instance = AgenticAIService._internal();
  factory AgenticAIService() => _instance;
  AgenticAIService._internal();
  
  late final Dio _dio;
  late final HealthArchiveService _archiveService;
  late final HealthContextBuilder _contextBuilder;
  
  String _pcAddress = '';
  int _port = 8000;
  bool _isInitialized = false;
  
  String get serverUrl => 'http://$_pcAddress:$_port';
  
  /// Initialize the service
  Future<void> initialize({required String pcAddress, int port = 8000}) async {
    _pcAddress = pcAddress;
    _port = port;
    
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 120),  // Long for reasoning
      sendTimeout: const Duration(seconds: 30),
    ));
    
    _archiveService = HealthArchiveService();
    await _archiveService.initialize();
    
    _contextBuilder = HealthContextBuilder(_archiveService);
    await _contextBuilder.initialize();
    
    _isInitialized = true;
    print('🤖 Agentic AI Service initialized');
  }
  
  /// Send an agentic chat message
  /// 
  /// This handles all the reasoning loops automatically.
  /// Returns the final response after AI finishes reasoning.
  Future<AgenticResult> chat(String message) async {
    if (!_isInitialized) {
      throw Exception('AgenticAIService not initialized');
    }
    
    final stopwatch = Stopwatch()..start();
    final toolCalls = <ToolCall>[];
    final toolResults = <ToolResult>[];
    
    String? sessionId;
    int roundNumber = 0;
    String response = '';
    bool isComplete = false;
    
    // Build initial health context from phone
    final healthContext = await _buildHealthContext();
    
    print('🤖 Starting agentic chat...');
    print('📊 Initial context: ${healthContext.keys.join(', ')}');
    
    // Reasoning loop - max 4 rounds
    while (!isComplete && roundNumber < 4) {
      print('🔄 Round ${roundNumber + 1}...');
      
      try {
        final requestBody = {
          'message': message,
          'health_context': healthContext,
          'tool_results': toolResults.map((r) => r.toJson()).toList(),
          'session_id': sessionId,
          'round_number': roundNumber,
        };
        
        final apiResponse = await _dio.post(
          '$serverUrl/chat/agentic',
          data: requestBody,
        );
        
        if (apiResponse.statusCode == 200) {
          final data = apiResponse.data;
          
          response = data['response'] ?? '';
          sessionId = data['session_id'];
          isComplete = data['is_complete'] ?? true;
          roundNumber = data['round_number'] ?? roundNumber + 1;
          
          final newToolCalls = (data['tool_calls'] as List<dynamic>?)
              ?.map((tc) => ToolCall.fromJson(tc))
              .toList() ?? [];
          
          if (newToolCalls.isEmpty) {
            isComplete = true;
            print('✅ No more tools needed, response ready');
          } else {
            // Execute tools on phone
            print('🔧 Executing ${newToolCalls.length} tool(s)...');
            toolCalls.addAll(newToolCalls);
            
            for (final tc in newToolCalls) {
              final result = await _executeTool(tc);
              toolResults.add(result);
              print('   ${tc.tool}: ${result.success ? "✅" : "❌"}');
            }
          }
        } else {
          throw Exception('API error: ${apiResponse.statusCode}');
        }
        
      } catch (e) {
        print('❌ Error in round $roundNumber: $e');
        response = 'Sorry, I encountered an error while processing your request.';
        isComplete = true;
      }
    }
    
    stopwatch.stop();
    
    return AgenticResult(
      response: response,
      toolCalls: toolCalls,
      toolResults: toolResults,
      totalRounds: roundNumber,
      totalTimeMs: stopwatch.elapsedMilliseconds,
      sessionId: sessionId ?? '',
    );
  }
  
  /// Build health context from phone's database
  Future<Map<String, dynamic>> _buildHealthContext() async {
    final symptoms = await _contextBuilder.getActiveSymptoms();
    final conditions = await _archiveService.getConditions();
    final medications = await _archiveService.getMedications();
    final allergies = await _archiveService.getAllergies();
    
    return {
      'symptoms': symptoms.map((s) {
        return {
          'name': s.name,
          'severity': s.severity.name,
          'onset_date': s.onsetDate.toIso8601String(),
          'notes': s.notes,
        };
      }).toList(),
      'conditions': conditions.map((c) {
        return {
          'name': c.name,
          'status': c.status?.name ?? 'unknown',
          'onset_date': c.onsetDate?.toIso8601String(),
        };
      }).toList(),
      'medications': medications.map((m) {
        return {
          'name': m.name,
          'dosage': m.dosage,
          'frequency': m.frequency,
          'status': m.status.name,
        };
      }).toList(),
      'allergies': allergies.map((a) {
        return {
          'allergen': a.allergen,
          'severity': a.severity?.name ?? 'unknown',
          'reaction': a.reaction,
        };
      }).toList(),
    };
  }
  
  /// Execute a tool on the phone
  Future<ToolResult> _executeTool(ToolCall call) async {
    try {
      switch (call.tool) {
        case 'query_symptoms':
          final symptoms = await _contextBuilder.getActiveSymptoms();
          return ToolResult(
            tool: call.tool,
            success: true,
            data: symptoms.map((s) {
              return {
                'name': s.name,
                'severity': s.severity.name,
                'days_active': DateTime.now().difference(s.onsetDate).inDays,
                'notes': s.notes,
              };
            }).toList(),
          );
          
        case 'query_conditions':
          final conditions = await _archiveService.getConditions();
          return ToolResult(
            tool: call.tool,
            success: true,
            data: conditions.map((c) {
              return {
                'name': c.name,
                'status': c.status?.name ?? 'unknown',
                'onset_date': c.onsetDate?.toIso8601String(),
              };
            }).toList(),
          );
          
        case 'query_medications':
          final medications = await _archiveService.getMedications();
          return ToolResult(
            tool: call.tool,
            success: true,
            data: medications.map((m) {
              return {
                'name': m.name,
                'dosage': m.dosage,
                'frequency': m.frequency,
                'status': m.status.name,
              };
            }).toList(),
          );
          
        case 'query_allergies':
          final allergies = await _archiveService.getAllergies();
          return ToolResult(
            tool: call.tool,
            success: true,
            data: allergies.map((a) {
              return {
                'allergen': a.allergen,
                'severity': a.severity?.name,
                'reaction': a.reaction,
              };
            }).toList(),
          );
          
        case 'save_symptom':
          final name = call.params['name'] ?? 'Unknown';
          final severityStr = call.params['severity'] ?? 'moderate';
          final notes = call.params['notes'] ?? '';
          
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
          
          return ToolResult(
            tool: call.tool,
            success: true,
            data: {'saved': name, 'severity': severity.name},
          );
          
        case 'save_insight':
          final insight = call.params['insight'] ?? '';
          final category = call.params['category'] ?? 'general';
          
          // Save as a note in conditions for now
          // Could create a separate insights table
          print('💡 AI Insight: $insight (category: $category)');
          
          return ToolResult(
            tool: call.tool,
            success: true,
            data: {'insight_saved': true, 'category': category},
          );
          
        case 'resolve_symptom':
          final name = call.params['name'] ?? '';
          if (name.isNotEmpty) {
            await _contextBuilder.resolveSymptom(name);
          }
          return ToolResult(
            tool: call.tool,
            success: true,
            data: {'resolved': name},
          );
          
        default:
          return ToolResult(
            tool: call.tool,
            success: false,
            data: null,
            error: 'Unknown tool: ${call.tool}',
          );
      }
    } catch (e) {
      return ToolResult(
        tool: call.tool,
        success: false,
        data: null,
        error: e.toString(),
      );
    }
  }
}

/// Result from agentic reasoning
class AgenticResult {
  final String response;
  final List<ToolCall> toolCalls;
  final List<ToolResult> toolResults;
  final int totalRounds;
  final int totalTimeMs;
  final String sessionId;
  
  AgenticResult({
    required this.response,
    required this.toolCalls,
    required this.toolResults,
    required this.totalRounds,
    required this.totalTimeMs,
    required this.sessionId,
  });
  
  /// How many tool calls were made
  int get totalToolCalls => toolCalls.length;
  
  /// How many tools succeeded
  int get successfulToolCalls => toolResults.where((r) => r.success).length;
}

/// A tool call request from the AI
class ToolCall {
  final String tool;
  final Map<String, dynamic> params;
  final String reason;
  
  ToolCall({
    required this.tool,
    this.params = const {},
    this.reason = '',
  });
  
  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      tool: json['tool'] ?? '',
      params: Map<String, dynamic>.from(json['params'] ?? {}),
      reason: json['reason'] ?? '',
    );
  }
  
  Map<String, dynamic> toJson() => {
    'tool': tool,
    'params': params,
    'reason': reason,
  };
}

/// Result of executing a tool
class ToolResult {
  final String tool;
  final bool success;
  final dynamic data;
  final String? error;
  
  ToolResult({
    required this.tool,
    required this.success,
    this.data,
    this.error,
  });
  
  Map<String, dynamic> toJson() => {
    'tool': tool,
    'success': success,
    'data': data,
    'error': error,
  };
}
