import 'dart:convert';
import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';

/// AI Service - Bridge to the Python backend
/// 
/// This service handles all communication with the Med Assist App backend.
/// When porting to mobile, this will be replaced with direct MediaPipe calls.
class AIService {
  final Dio _dio;
  final String baseUrl;
  
  AIService({
    required this.baseUrl,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: AppConstants.apiTimeout,
      receiveTimeout: AppConstants.longRequestTimeout,
      headers: {
        'Content-Type': 'application/json',
      },
    );
    
    // Add logging interceptor for debugging
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('AI Service: $obj'),
    ));
  }
  
  /// Check if the backend is healthy and ready
  Future<HealthStatus> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return HealthStatus.fromJson(response.data);
    } on DioException catch (e) {
      return HealthStatus(
        status: 'offline',
        modelReady: false,
        memoryReady: false,
        gpuEnabled: false,
        documentCount: 0,
        version: 'unknown',
        error: e.message,
      );
    }
  }
  
  /// Send a chat message and receive AI response
  Future<ChatResponse> sendMessage({
    required String message,
    String analysisType = 'general_health',
    bool includeContext = true,
    int maxContextDocs = 3,
  }) async {
    try {
      final response = await _dio.post('/chat', data: {
        'message': message,
        'analysis_type': analysisType,
        'include_context': includeContext,
        'max_context_docs': maxContextDocs,
      });
      
      return ChatResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw AIServiceException(
        'Failed to send message: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }
  
  /// Request explanation for an AI response ("Why?" button)
  Future<ChatResponse> explainResponse({
    required String originalResponse,
    required List<String> referencedDocIds,
  }) async {
    try {
      final response = await _dio.post('/explain', data: {
        'original_response': originalResponse,
        'referenced_doc_ids': referencedDocIds,
      });
      
      return ChatResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw AIServiceException(
        'Failed to get explanation: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }
  
  /// Upload a medical document
  Future<UploadResponse> uploadDocument({
    required String filePath,
    required String fileName,
    required List<int> fileBytes,
    String? docType,
    List<String>? tags,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
        ),
        if (docType != null) 'doc_type': docType,
        if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
      });
      
      final response = await _dio.post('/upload', data: formData);
      return UploadResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw AIServiceException(
        'Failed to upload document: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }
  
  /// Search for relevant context documents
  Future<List<ContextResult>> searchContext({
    required String query,
    int nResults = 5,
    String? docType,
  }) async {
    try {
      final response = await _dio.post('/context', data: {
        'query': query,
        'n_results': nResults,
        if (docType != null) 'doc_type': docType,
      });
      
      return (response.data as List)
          .map((json) => ContextResult.fromJson(json))
          .toList();
    } on DioException catch (e) {
      throw AIServiceException(
        'Failed to search context: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }
}

// ============================================================================
// Data Models
// ============================================================================

class HealthStatus {
  final String status;
  final bool modelReady;
  final bool memoryReady;
  final bool gpuEnabled;
  final int documentCount;
  final String version;
  final String? error;
  
  HealthStatus({
    required this.status,
    required this.modelReady,
    required this.memoryReady,
    required this.gpuEnabled,
    required this.documentCount,
    required this.version,
    this.error,
  });
  
  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      status: json['status'] ?? 'unknown',
      modelReady: json['model_ready'] ?? false,
      memoryReady: json['memory_ready'] ?? false,
      gpuEnabled: json['gpu_enabled'] ?? false,
      documentCount: json['document_count'] ?? 0,
      version: json['version'] ?? 'unknown',
    );
  }
  
  bool get isHealthy => status == 'healthy' && modelReady;
}

class ChatResponse {
  final String response;
  final List<ReferencedDocument> referencedDocuments;
  final double inferenceTimeMs;
  final bool modelReady;
  
  ChatResponse({
    required this.response,
    required this.referencedDocuments,
    required this.inferenceTimeMs,
    required this.modelReady,
  });
  
  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      response: json['response'] ?? '',
      referencedDocuments: (json['referenced_documents'] as List?)
          ?.map((doc) => ReferencedDocument.fromJson(doc))
          .toList() ?? [],
      inferenceTimeMs: (json['inference_time_ms'] ?? 0).toDouble(),
      modelReady: json['model_ready'] ?? false,
    );
  }
}

class ReferencedDocument {
  final String docId;
  final String source;
  final String docType;
  final double relevance;
  
  ReferencedDocument({
    required this.docId,
    required this.source,
    required this.docType,
    required this.relevance,
  });
  
  factory ReferencedDocument.fromJson(Map<String, dynamic> json) {
    return ReferencedDocument(
      docId: json['doc_id'] ?? '',
      source: json['source'] ?? 'Unknown',
      docType: json['doc_type'] ?? 'general',
      relevance: (json['relevance'] ?? 0).toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'doc_id': docId,
    'source': source,
    'doc_type': docType,
    'relevance': relevance,
  };
}

class UploadResponse {
  final bool success;
  final String docId;
  final String docType;
  final String message;
  final int chunksCreated;
  
  UploadResponse({
    required this.success,
    required this.docId,
    required this.docType,
    required this.message,
    required this.chunksCreated,
  });
  
  factory UploadResponse.fromJson(Map<String, dynamic> json) {
    return UploadResponse(
      success: json['success'] ?? false,
      docId: json['doc_id'] ?? '',
      docType: json['doc_type'] ?? 'general',
      message: json['message'] ?? '',
      chunksCreated: json['chunks_created'] ?? 0,
    );
  }
}

class ContextResult {
  final String content;
  final String source;
  final String docType;
  final String timestamp;
  final double relevanceScore;
  
  ContextResult({
    required this.content,
    required this.source,
    required this.docType,
    required this.timestamp,
    required this.relevanceScore,
  });
  
  factory ContextResult.fromJson(Map<String, dynamic> json) {
    return ContextResult(
      content: json['content'] ?? '',
      source: json['source'] ?? 'Unknown',
      docType: json['doc_type'] ?? 'general',
      timestamp: json['timestamp'] ?? '',
      relevanceScore: (json['relevance_score'] ?? 0).toDouble(),
    );
  }
}

class AIServiceException implements Exception {
  final String message;
  final int? statusCode;
  
  AIServiceException(this.message, {this.statusCode});
  
  @override
  String toString() => 'AIServiceException: $message (status: $statusCode)';
}
