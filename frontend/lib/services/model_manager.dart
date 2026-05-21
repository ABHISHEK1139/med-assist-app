import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Model Manager for on-device LLM
/// 
/// Handles model file location and validation.
class ModelManager {
  static const String modelFileName = 'med-assist-app-2b.task';
  static const int expectedModelSizeMB = 2500; // ~2.5GB
  
  /// Get the model directory path
  static Future<String> getModelDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/models');
    
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    
    return modelDir.path;
  }
  
  /// Get the full model file path
  static Future<String> getModelPath() async {
    final dir = await getModelDirectory();
    return '$dir/$modelFileName';
  }
  
  /// Check if model exists and is valid
  static Future<ModelStatus> checkModelStatus() async {
    try {
      final modelPath = await getModelPath();
      final file = File(modelPath);
      
      if (!await file.exists()) {
        // Check external storage as fallback
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final externalPath = '${externalDir.path}/models/$modelFileName';
          final externalFile = File(externalPath);
          if (await externalFile.exists()) {
            final size = await externalFile.length();
            return ModelStatus(
              exists: true,
              path: externalPath,
              sizeMB: size ~/ (1024 * 1024),
              isValid: size > expectedModelSizeMB * 0.9 * 1024 * 1024,
            );
          }
        }
        
        return ModelStatus(
          exists: false,
          path: modelPath,
          sizeMB: 0,
          isValid: false,
        );
      }
      
      final size = await file.length();
      final sizeMB = size ~/ (1024 * 1024);
      
      return ModelStatus(
        exists: true,
        path: modelPath,
        sizeMB: sizeMB,
        isValid: sizeMB > expectedModelSizeMB * 0.9, // Allow 10% tolerance
      );
      
    } catch (e) {
      return ModelStatus(
        exists: false,
        path: '',
        sizeMB: 0,
        isValid: false,
        error: e.toString(),
      );
    }
  }
  
  /// Get instructions for model setup
  static String getSetupInstructions() {
    return '''
📱 Med Assist App Model Setup

To run Med Assist App 100% on-device:

1. Download the quantized model:
   - File: med-assist-app-2b.task (~2.5GB)
   - Source: Google AI Edge / HuggingFace

2. Copy to your phone:
   - Path: Android/data/com.med_assist_app.app/files/models/
   - Or: Documents/models/

3. Restart the app

⚡ Performance Tips:
- Model runs on your phone's NPU/GPU
- First response may take 10-20 seconds
- Subsequent responses: 5-10 seconds
- No internet required!
''';
  }
}

/// Model status information
class ModelStatus {
  final bool exists;
  final String path;
  final int sizeMB;
  final bool isValid;
  final String? error;
  
  ModelStatus({
    required this.exists,
    required this.path,
    required this.sizeMB,
    required this.isValid,
    this.error,
  });
  
  @override
  String toString() {
    if (!exists) return 'Model not found at: $path';
    if (!isValid) return 'Model may be corrupted (${sizeMB}MB)';
    return 'Model ready: ${sizeMB}MB at $path';
  }
}
