import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Model download states
enum ModelDownloadState {
  notStarted,
  checkingStorage,
  requestingPermission,
  connecting,
  downloading,
  verifying,
  completed,
  error,
}

/// Model loading states (after download)
enum ModelLoadState {
  notLoaded,
  locatingModel,
  loadingToMemory,
  initializingEngine,
  warmingUp,
  ready,
  error,
}

/// Download progress info
class DownloadProgress {
  final ModelDownloadState state;
  final double progress; // 0.0 to 1.0
  final int downloadedBytes;
  final int totalBytes;
  final String message;
  final String? error;
  final double? speedMBps;
  final String? currentFile;
  
  const DownloadProgress({
    required this.state,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.message = '',
    this.error,
    this.speedMBps,
    this.currentFile,
  });
  
  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';
  
  String get downloadedSize {
    if (downloadedBytes < 1024) return '$downloadedBytes B';
    if (downloadedBytes < 1024 * 1024) return '${(downloadedBytes / 1024).toStringAsFixed(1)} KB';
    if (downloadedBytes < 1024 * 1024 * 1024) {
      return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(downloadedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  
  String get totalSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  
  String get speedText {
    if (speedMBps == null) return '';
    return '${speedMBps!.toStringAsFixed(1)} MB/s';
  }
  
  String get etaText {
    if (speedMBps == null || speedMBps == 0 || totalBytes == 0) return '';
    final remainingBytes = totalBytes - downloadedBytes;
    final remainingSeconds = remainingBytes / (speedMBps! * 1024 * 1024);
    if (remainingSeconds < 60) return '${remainingSeconds.toStringAsFixed(0)}s remaining';
    if (remainingSeconds < 3600) return '${(remainingSeconds / 60).toStringAsFixed(0)}m remaining';
    return '${(remainingSeconds / 3600).toStringAsFixed(1)}h remaining';
  }
}

/// Load progress info
class LoadProgress {
  final ModelLoadState state;
  final double progress; // 0.0 to 1.0
  final String message;
  final String? error;
  
  const LoadProgress({
    required this.state,
    this.progress = 0.0,
    this.message = '',
    this.error,
  });
}

/// Model file info
class ModelFile {
  final String name;
  final String url;
  final int expectedSize;
  final bool isRequired;
  
  const ModelFile({
    required this.name,
    required this.url,
    required this.expectedSize,
    this.isRequired = true,
  });
}

/// Service to download and manage Med Assist App 2B model (MediaPipe .task format)
class ModelDownloadService {
  static final ModelDownloadService _instance = ModelDownloadService._internal();
  factory ModelDownloadService() => _instance;
  ModelDownloadService._internal();
  
  // Google Drive direct download URL for Med Assist App 2B .task
  // Your existing 2.53GB model in MediaPipe format
  static const List<ModelFile> _modelFiles = [
    ModelFile(
      name: 'med-assist-app-2b.task',
      url: 'https://drive.google.com/uc?export=download&id=1OoL_WxgG3HXWC_rSKDmwf6Jw9dEQT36V&confirm=t',
      expectedSize: 2713000000, // ~2.53 GB
      isRequired: true,
    ),
  ];
  
  static const String _mainModelName = 'med-assist-app-2b.task';
  
  // Stream controllers for progress updates
  final _downloadProgressController = StreamController<DownloadProgress>.broadcast();
  final _loadProgressController = StreamController<LoadProgress>.broadcast();
  
  Stream<DownloadProgress> get downloadProgress => _downloadProgressController.stream;
  Stream<LoadProgress> get loadProgress => _loadProgressController.stream;
  
  bool _isDownloading = false;
  bool _isCancelled = false;
  
  /// Get the persistent model directory
  Future<String> get modelDirectory async {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Documents/Med Assist App/models';
    } else {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}/Med Assist App/models';
    }
  }
  
  /// Get the main model path
  Future<String> get modelPath async {
    final dir = await modelDirectory;
    return '$dir/$_mainModelName';
  }
  
  /// Public method to get model path (for external use)
  Future<String?> getModelPath() async {
    try {
      final path = await modelPath;
      final file = File(path);
      if (await file.exists()) {
        return path;
      }
    } catch (_) {}
    return null;
  }
  
  /// Check if main model is downloaded
  Future<bool> isModelDownloaded() async {
    try {
      final path = await modelPath;
      final file = File(path);
      
      if (!await file.exists()) return false;
      
      final size = await file.length();
      // Accept if at least 2GB (model should be ~2.5GB)
      return size > 2000000000;
    } catch (e) {
      return false;
    }
  }
  
  /// Get current model size if exists
  Future<int?> getDownloadedSize() async {
    try {
      final path = await modelPath;
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return null;
  }
  
  /// Get total expected download size
  int get totalExpectedSize {
    return _modelFiles.fold(0, (sum, file) => sum + file.expectedSize);
  }
  
  /// Request storage permissions
  Future<bool> _requestPermissions() async {
    _emitDownloadProgress(ModelDownloadState.requestingPermission, 
        message: 'Requesting storage permission...');
    
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;
      
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return true;
  }
  
  /// Download all model files from HuggingFace
  Future<bool> downloadModel({
    bool includeMultimodal = true,
    Function(DownloadProgress)? onProgress,
  }) async {
    if (_isDownloading) {
      _emitDownloadProgress(ModelDownloadState.error, 
          error: 'Download already in progress');
      return false;
    }
    
    _isDownloading = true;
    _isCancelled = false;
    
    try {
      // Step 1: Check storage space
      _emitDownloadProgress(ModelDownloadState.checkingStorage,
          message: 'Checking available storage (~3.5 GB needed)...');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Step 2: Request permissions
      if (!await _requestPermissions()) {
        _emitDownloadProgress(ModelDownloadState.error,
            error: 'Storage permission denied. Please grant permission in Settings.');
        _isDownloading = false;
        return false;
      }
      
      // Step 3: Create directory
      final dir = await modelDirectory;
      await Directory(dir).create(recursive: true);
      
      // Step 4: Download each file
      final filesToDownload = includeMultimodal 
          ? _modelFiles 
          : _modelFiles.where((f) => f.isRequired).toList();
      
      int totalBytesDownloaded = 0;
      int totalBytes = filesToDownload.fold(0, (sum, f) => sum + f.expectedSize);
      
      for (final modelFile in filesToDownload) {
        if (_isCancelled) {
          _emitDownloadProgress(ModelDownloadState.error, error: 'Download cancelled');
          _isDownloading = false;
          return false;
        }
        
        final success = await _downloadFile(
          modelFile: modelFile,
          directory: dir,
          totalBytesDownloaded: totalBytesDownloaded,
          totalBytes: totalBytes,
        );
        
        if (!success && modelFile.isRequired) {
          _isDownloading = false;
          return false;
        }
        
        totalBytesDownloaded += modelFile.expectedSize;
      }
      
      // Step 5: Verify downloads
      _emitDownloadProgress(ModelDownloadState.verifying,
          progress: 1.0,
          message: 'Verifying downloaded files...');
      
      if (!await isModelDownloaded()) {
        _emitDownloadProgress(ModelDownloadState.error,
            error: 'Model verification failed');
        _isDownloading = false;
        return false;
      }
      
      _emitDownloadProgress(ModelDownloadState.completed,
          progress: 1.0,
          message: 'Med Assist App downloaded! Ready for on-device AI.');
      
      _isDownloading = false;
      return true;
      
    } catch (e) {
      _emitDownloadProgress(ModelDownloadState.error,
          error: 'Download failed: $e');
      _isDownloading = false;
      return false;
    }
  }
  
  /// Download a single model file
  Future<bool> _downloadFile({
    required ModelFile modelFile,
    required String directory,
    required int totalBytesDownloaded,
    required int totalBytes,
  }) async {
    final filePath = '$directory/${modelFile.name}';
    final tempPath = '$filePath.downloading';
    
    // Check if already downloaded
    final existingFile = File(filePath);
    if (await existingFile.exists()) {
      final size = await existingFile.length();
      if (size > modelFile.expectedSize * 0.9) {
        print('✅ ${modelFile.name} already downloaded (${_formatBytes(size)})');
        return true;
      }
    }
    
    _emitDownloadProgress(ModelDownloadState.connecting,
        message: 'Connecting to HuggingFace...',
        currentFile: modelFile.name);
    
    // Delete partial download
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    
    final client = http.Client();
    
    try {
      print('📥 Downloading ${modelFile.name} from HuggingFace...');
      
      final request = http.Request('GET', Uri.parse(modelFile.url));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers['User-Agent'] = 'Med Assist App-App/1.0';
      
      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        _emitDownloadProgress(ModelDownloadState.error,
            error: 'Download failed: HTTP ${response.statusCode}');
        return false;
      }
      
      // Get content length
      int fileSize = modelFile.expectedSize;
      if (response.headers.containsKey('content-length')) {
        final contentLength = int.tryParse(response.headers['content-length']!);
        if (contentLength != null && contentLength > 1000000) {
          fileSize = contentLength;
        }
      }
      
      // Open file for writing
      final sink = tempFile.openWrite(mode: FileMode.write);
      
      int downloadedBytes = 0;
      DateTime lastSpeedUpdate = DateTime.now();
      int lastSpeedBytes = 0;
      double currentSpeed = 0;
      
      _emitDownloadProgress(ModelDownloadState.downloading,
          progress: totalBytesDownloaded / totalBytes,
          downloadedBytes: totalBytesDownloaded,
          totalBytes: totalBytes,
          message: 'Downloading ${modelFile.name}...',
          currentFile: modelFile.name);
      
      await for (final chunk in response.stream) {
        if (_isCancelled) {
          await sink.close();
          return false;
        }
        
        sink.add(chunk);
        downloadedBytes += chunk.length;
        
        // Calculate speed every second
        final now = DateTime.now();
        final elapsed = now.difference(lastSpeedUpdate).inMilliseconds;
        if (elapsed >= 1000) {
          currentSpeed = (downloadedBytes - lastSpeedBytes) / (elapsed / 1000) / (1024 * 1024);
          lastSpeedBytes = downloadedBytes;
          lastSpeedUpdate = now;
        }
        
        // Update progress
        final overallProgress = (totalBytesDownloaded + downloadedBytes) / totalBytes;
        _emitDownloadProgress(ModelDownloadState.downloading,
            progress: overallProgress,
            downloadedBytes: totalBytesDownloaded + downloadedBytes,
            totalBytes: totalBytes,
            message: 'Downloading ${modelFile.name}...',
            speedMBps: currentSpeed,
            currentFile: modelFile.name);
      }
      
      await sink.flush();
      await sink.close();
      
      // Verify downloaded size
      final downloadedSize = await tempFile.length();
      print('📦 Downloaded ${_formatBytes(downloadedSize)}');
      
      if (downloadedSize < modelFile.expectedSize * 0.5) {
        _emitDownloadProgress(ModelDownloadState.error,
            error: '${modelFile.name} download incomplete');
        await tempFile.delete();
        return false;
      }
      
      // Rename temp file to final
      await tempFile.rename(filePath);
      
      print('✅ ${modelFile.name} downloaded successfully');
      return true;
      
    } catch (e) {
      print('❌ Download error for ${modelFile.name}: $e');
      _emitDownloadProgress(ModelDownloadState.error,
          error: 'Failed to download ${modelFile.name}: $e');
      return false;
    } finally {
      client.close();
    }
  }
  
  /// Cancel ongoing download
  void cancelDownload() {
    _isCancelled = true;
  }
  
  /// Delete downloaded model files
  Future<bool> deleteModel() async {
    try {
      final dir = await modelDirectory;
      final directory = Directory(dir);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Emit model loading progress
  void emitLoadProgress(ModelLoadState state, {
    double progress = 0.0,
    String message = '',
    String? error,
  }) {
    _loadProgressController.add(LoadProgress(
      state: state,
      progress: progress,
      message: message,
      error: error,
    ));
  }
  
  void _emitDownloadProgress(
    ModelDownloadState state, {
    double progress = 0.0,
    int downloadedBytes = 0,
    int totalBytes = 0,
    String message = '',
    String? error,
    double? speedMBps,
    String? currentFile,
  }) {
    _downloadProgressController.add(DownloadProgress(
      state: state,
      progress: progress,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      message: message,
      error: error,
      speedMBps: speedMBps,
      currentFile: currentFile,
    ));
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  
  void dispose() {
    _downloadProgressController.close();
    _loadProgressController.close();
  }
}
