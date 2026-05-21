import 'dart:async';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

/// On-Device LLM Service using MediaPipe with Med Assist App 2B
/// 
/// This service runs Med Assist App entirely on-device.
/// NO INTERNET REQUIRED - 100% Privacy Preserved.
/// 
/// ⚠️ MODEL PERSISTS EVEN AFTER APP UNINSTALL
/// Stored in: /storage/emulated/0/Documents/Med Assist App/models/
class OnDeviceLLMService {
  static const MethodChannel _channel = MethodChannel('com.med_assist_app/llm');
  static const String _appFolder = 'Med Assist App';
  static const String _modelName = 'med-assist-app-2b.task';
  
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _modelPath;
  
  // Streaming response controller
  final StreamController<String> _responseStream = StreamController.broadcast();
  Stream<String> get responseStream => _responseStream.stream;
  
  /// Check if model is ready
  bool get isReady => _isInitialized;
  bool get isLoading => _isLoading;
  
  /// Initialize the on-device LLM with MediaPipe
  Future<bool> initialize({String? customModelPath}) async {
    if (_isInitialized) return true;
    _isLoading = true;
    
    try {
      // Get model path
      _modelPath = customModelPath ?? await _getModelPath();
      
      if (_modelPath == null || !await File(_modelPath!).exists()) {
        print('❌ Model file not found at: $_modelPath');
        _isLoading = false;
        return false;
      }
      
      // Check model file size
      final modelFile = File(_modelPath!);
      final sizeBytes = await modelFile.length();
      final sizeMB = sizeBytes / (1024 * 1024);
      print('📁 MediaPipe model file size: ${sizeMB.toStringAsFixed(1)} MB');
      
      if (sizeMB < 500) {
        print('❌ Model file too small (${sizeMB.toStringAsFixed(1)} MB) - likely corrupted');
        _isLoading = false;
        return false;
      }
      
      print('🚀 Initializing MediaPipe with Med Assist App 2B...');
      
      // Initialize MediaPipe LLM via platform channel
      final result = await _channel.invokeMethod('initializeModel', {
        'modelPath': _modelPath,
        'useGpu': true,
      }).timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          print('❌ Model initialization timed out');
          return false;
        },
      );
      
      _isInitialized = result == true;
      _isLoading = false;
      
      if (_isInitialized) {
        print('✅ Med Assist App 2B loaded via MediaPipe!');
      } else {
        print('❌ LLM initialization failed');
      }
      
      return _isInitialized;
      
    } on PlatformException catch (e) {
      print('❌ Platform error: ${e.code} - ${e.message}');
      _isLoading = false;
      return false;
    } catch (e) {
      print('❌ Failed to initialize: $e');
      _isLoading = false;
      return false;
    }
  }
  
  /// Get main model path
  Future<String?> _getModelPath() async {
    try {
      await _requestPermissions();
      
      // Persistent location
      if (Platform.isAndroid) {
        final persistentPath = '/storage/emulated/0/Documents/$_appFolder/models/$_modelName';
        if (await File(persistentPath).exists()) {
          print('✅ Model found: $persistentPath');
          return persistentPath;
        }
      }
      
      // App documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final appModelPath = '${appDir.path}/models/$_modelName';
      if (await File(appModelPath).exists()) {
        return appModelPath;
      }
      
      print('⚠️ Model not found! Download required.');
      return null;
    } catch (e) {
      print('Error getting model path: $e');
      return null;
    }
  }
  
  /// Request storage permissions
  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      if (!await Permission.storage.isGranted) {
        await Permission.storage.request();
      }
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
  }
  
  /// Get the persistent model directory path
  static Future<String> getPersistentModelPath() async {
    if (Platform.isAndroid) {
      final path = '/storage/emulated/0/Documents/$_appFolder/models';
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return '$path/$_modelName';
    } else {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}/$_appFolder/models/$_modelName';
    }
  }
  
  /// Generate response from the on-device model
  Future<String> generateResponse(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 256,
    double temperature = 0.7,
  }) async {
    if (!_isInitialized) {
      return '[Error: Model not initialized]';
    }
    
    try {
      // Build full prompt with system context
      final fullPrompt = _buildPrompt(prompt, systemPrompt);
      
      final response = await _channel.invokeMethod('generateResponse', {
        'prompt': fullPrompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
      });
      
      return response ?? '[No response generated]';
      
    } catch (e) {
      print('Generation error: $e');
      return '[Error: $e]';
    }
  }
  
  /// Generate response with image (text-only model - provides guidance)
  Future<String> generateWithImage(
    String prompt,
    String imagePath, {
    int maxTokens = 256,
  }) async {
    if (!_isInitialized) {
      return '[Error: Model not initialized]';
    }
    
    try {
      // Med Assist App 2B is text-only, but can still provide guidance
      final response = await _channel.invokeMethod('generateWithImage', {
        'prompt': prompt,
        'imagePath': imagePath,
        'maxTokens': maxTokens,
      });
      
      return response ?? '[No response generated]';
      
    } catch (e) {
      print('Image generation error: $e');
      return '[Error: $e]';
    }
  }
  
  /// Build a medical prompt with context
  String buildMedicalPrompt({
    required String userMessage,
    List<String>? medicalHistory,
    String? currentConditions,
  }) {
    final buffer = StringBuffer();
    
    buffer.writeln('<start_of_turn>user');
    buffer.writeln('You are Med Assist App, a medical AI assistant focused on health education.');
    buffer.writeln('Provide helpful, accurate medical information while always recommending professional consultation.');
    buffer.writeln();
    
    if (medicalHistory != null && medicalHistory.isNotEmpty) {
      buffer.writeln('Patient History Context:');
      for (final item in medicalHistory) {
        buffer.writeln('- $item');
      }
      buffer.writeln();
    }
    
    if (currentConditions != null && currentConditions.isNotEmpty) {
      buffer.writeln('Current Conditions: $currentConditions');
      buffer.writeln();
    }
    
    buffer.writeln('User Question: $userMessage');
    buffer.writeln('<end_of_turn>');
    buffer.writeln('<start_of_turn>model');
    
    return buffer.toString();
  }
  
  /// Build prompt with optional system context
  String _buildPrompt(String userMessage, String? systemPrompt) {
    final buffer = StringBuffer();
    
    buffer.writeln('<start_of_turn>user');
    
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln(systemPrompt);
      buffer.writeln();
    }
    
    buffer.writeln(userMessage);
    buffer.writeln('<end_of_turn>');
    buffer.writeln('<start_of_turn>model');
    
    return buffer.toString();
  }
  
  /// Close and release resources
  Future<void> dispose() async {
    if (_isInitialized) {
      try {
        await _channel.invokeMethod('dispose');
      } catch (e) {
        print('Error disposing LLM: $e');
      }
      _isInitialized = false;
    }
    await _responseStream.close();
  }
}
