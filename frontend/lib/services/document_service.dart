import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

/// Document Service
/// 
/// Handles uploading medical documents to PC backend for processing.
/// Supported formats: PDF, images (JPG, PNG), text files
/// 
/// Documents are processed by PC and stored in vector database for
/// context-aware AI responses.
class DocumentService {
  static final DocumentService _instance = DocumentService._internal();
  factory DocumentService() => _instance;
  DocumentService._internal();
  
  late Dio _dio;
  String _serverUrl = '';
  bool _isInitialized = false;
  
  /// Initialize with PC backend URL
  void initialize(String serverUrl) {
    _serverUrl = serverUrl;
    _dio = Dio(BaseOptions(
      baseUrl: serverUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 120),
    ));
    _isInitialized = true;
    print('📄 Document Service initialized: $serverUrl');
  }
  
  /// Pick and upload a document
  Future<DocumentUploadResult> pickAndUpload({
    String? docType,
    List<String>? tags,
  }) async {
    if (!_isInitialized) {
      return DocumentUploadResult.error('Document service not initialized');
    }
    
    try {
      // Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'txt', 'doc', 'docx'],
        allowMultiple: false,
      );
      
      if (result == null || result.files.isEmpty) {
        return DocumentUploadResult.cancelled();
      }
      
      final file = result.files.first;
      if (file.path == null) {
        return DocumentUploadResult.error('Could not access file');
      }
      
      // Upload
      return await uploadFile(
        filePath: file.path!,
        docType: docType,
        tags: tags,
      );
    } catch (e) {
      print('❌ File pick error: $e');
      return DocumentUploadResult.error('Failed to pick file: $e');
    }
  }
  
  /// Upload a file from path
  Future<DocumentUploadResult> uploadFile({
    required String filePath,
    String? docType,
    List<String>? tags,
  }) async {
    if (!_isInitialized) {
      return DocumentUploadResult.error('Document service not initialized');
    }
    
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return DocumentUploadResult.error('File not found');
      }
      
      final fileName = path.basename(filePath);
      print('📤 Uploading: $fileName');
      
      // Create multipart form data
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: fileName,
        ),
        if (docType != null) 'doc_type': docType,
        if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
      });
      
      // Upload to PC backend
      final response = await _dio.post(
        '/api/upload',
        data: formData,
        onSendProgress: (sent, total) {
          final progress = (sent / total * 100).toStringAsFixed(0);
          print('📤 Upload progress: $progress%');
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        print('✅ Upload success: ${data['doc_type']} - ${data['chunks_created']} chunks');
        return DocumentUploadResult.success(
          docId: data['doc_id'] ?? '',
          docType: data['doc_type'] ?? 'unknown',
          message: data['message'] ?? 'Document uploaded',
          chunksCreated: data['chunks_created'] ?? 0,
        );
      } else {
        return DocumentUploadResult.error(
          response.data?['detail'] ?? 'Upload failed',
        );
      }
    } on DioException catch (e) {
      print('❌ Upload error: ${e.message}');
      if (e.type == DioExceptionType.connectionTimeout) {
        return DocumentUploadResult.error('Connection timeout - is PC connected?');
      }
      return DocumentUploadResult.error('Upload failed: ${e.message}');
    } catch (e) {
      print('❌ Upload error: $e');
      return DocumentUploadResult.error('Upload failed: $e');
    }
  }
  
  /// Get list of uploaded documents
  Future<List<StoredDocument>> getDocuments() async {
    if (!_isInitialized) return [];
    
    try {
      final response = await _dio.get('/api/documents');
      if (response.statusCode == 200) {
        final List<dynamic> docs = response.data ?? [];
        return docs.map((d) => StoredDocument.fromJson(d)).toList();
      }
    } catch (e) {
      print('❌ Get documents error: $e');
    }
    return [];
  }
  
  /// Search documents by query
  Future<List<DocumentSearchResult>> searchDocuments(
    String query, {
    int maxResults = 5,
    String? docType,
  }) async {
    if (!_isInitialized) return [];
    
    try {
      final response = await _dio.post('/api/context', data: {
        'query': query,
        'n_results': maxResults,
        if (docType != null) 'doc_type': docType,
      });
      
      if (response.statusCode == 200) {
        final List<dynamic> results = response.data ?? [];
        return results.map((r) => DocumentSearchResult.fromJson(r)).toList();
      }
    } catch (e) {
      print('❌ Search error: $e');
    }
    return [];
  }
}

/// Result of document upload
class DocumentUploadResult {
  final bool success;
  final bool cancelled;
  final String? error;
  final String? docId;
  final String? docType;
  final String? message;
  final int chunksCreated;
  
  DocumentUploadResult._({
    required this.success,
    this.cancelled = false,
    this.error,
    this.docId,
    this.docType,
    this.message,
    this.chunksCreated = 0,
  });
  
  factory DocumentUploadResult.success({
    required String docId,
    required String docType,
    required String message,
    required int chunksCreated,
  }) => DocumentUploadResult._(
    success: true,
    docId: docId,
    docType: docType,
    message: message,
    chunksCreated: chunksCreated,
  );
  
  factory DocumentUploadResult.error(String error) => DocumentUploadResult._(
    success: false,
    error: error,
  );
  
  factory DocumentUploadResult.cancelled() => DocumentUploadResult._(
    success: false,
    cancelled: true,
  );
}

/// Stored document info
class StoredDocument {
  final String docId;
  final String source;
  final String docType;
  final DateTime timestamp;
  final String summary;
  final List<String> tags;
  
  StoredDocument({
    required this.docId,
    required this.source,
    required this.docType,
    required this.timestamp,
    required this.summary,
    this.tags = const [],
  });
  
  factory StoredDocument.fromJson(Map<String, dynamic> json) => StoredDocument(
    docId: json['doc_id'] ?? '',
    source: json['source'] ?? '',
    docType: json['doc_type'] ?? 'unknown',
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    summary: json['summary'] ?? '',
    tags: List<String>.from(json['tags'] ?? []),
  );
  
  String get icon {
    switch (docType) {
      case 'lab_report': return '🧪';
      case 'prescription': return '💊';
      case 'radiology': return '🩻';
      case 'notes': return '📝';
      default: return '📄';
    }
  }
}

/// Document search result
class DocumentSearchResult {
  final String content;
  final String source;
  final String docType;
  final String timestamp;
  final double relevanceScore;
  
  DocumentSearchResult({
    required this.content,
    required this.source,
    required this.docType,
    required this.timestamp,
    required this.relevanceScore,
  });
  
  factory DocumentSearchResult.fromJson(Map<String, dynamic> json) => DocumentSearchResult(
    content: json['content'] ?? '',
    source: json['source'] ?? '',
    docType: json['doc_type'] ?? 'unknown',
    timestamp: json['timestamp'] ?? '',
    relevanceScore: (json['relevance_score'] ?? 0.0).toDouble(),
  );
}
