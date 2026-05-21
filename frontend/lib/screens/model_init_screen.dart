import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/model_download_service.dart';
import '../services/med_assist_service.dart';
import '../core/theme/app_theme.dart';

/// Beautiful model initialization screen with download/loading progress
class ModelInitScreen extends StatefulWidget {
  final VoidCallback onReady;
  final VoidCallback? onSkip;
  
  const ModelInitScreen({
    super.key,
    required this.onReady,
    this.onSkip,
  });
  
  @override
  State<ModelInitScreen> createState() => _ModelInitScreenState();
}

class _ModelInitScreenState extends State<ModelInitScreen>
    with TickerProviderStateMixin {
  final ModelDownloadService _downloadService = ModelDownloadService();
  final MedAssistAppService _MedAssistAppService = MedAssistAppService();
  
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _waveController;
  
  // State
  bool _isChecking = true;
  bool _needsDownload = false;
  bool _isDownloading = false;
  bool _isLoading = false;
  bool _isReady = false;
  String _statusMessage = 'Checking model status...';
  String? _errorMessage;
  
  // Download progress
  DownloadProgress? _downloadProgress;
  LoadProgress? _loadProgress;
  
  StreamSubscription<DownloadProgress>? _downloadSub;
  StreamSubscription<LoadProgress>? _loadSub;
  
  @override
  void initState() {
    super.initState();
    
    // Animation controllers
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _rotateController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    
    // Listen to progress streams
    _downloadSub = _downloadService.downloadProgress.listen((progress) {
      setState(() {
        _downloadProgress = progress;
        _statusMessage = progress.message;
        if (progress.error != null) {
          _errorMessage = progress.error;
          _isDownloading = false;
        }
        if (progress.state == ModelDownloadState.completed) {
          _isDownloading = false;
          _loadModel();
        }
      });
    });
    
    _loadSub = _downloadService.loadProgress.listen((progress) {
      setState(() {
        _loadProgress = progress;
        _statusMessage = progress.message;
        if (progress.error != null) {
          _errorMessage = progress.error;
          _isLoading = false;
        }
        if (progress.state == ModelLoadState.ready) {
          _isLoading = false;
          _isReady = true;
          Future.delayed(const Duration(milliseconds: 500), widget.onReady);
        }
      });
    });
    
    _checkModelStatus();
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _waveController.dispose();
    _downloadSub?.cancel();
    _loadSub?.cancel();
    super.dispose();
  }
  
  Future<void> _checkModelStatus() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Checking model status...';
    });
    
    await Future.delayed(const Duration(milliseconds: 800));
    
    final isDownloaded = await _downloadService.isModelDownloaded();
    
    setState(() {
      _isChecking = false;
      _needsDownload = !isDownloaded;
    });
    
    if (isDownloaded) {
      _loadModel();
    } else {
      setState(() {
        _statusMessage = 'Model not found. Tap Download to get Med Assist App from HuggingFace (~3.5 GB)';
      });
      // Auto-start download after showing message briefly
      // Uncomment below line to auto-download:
      // Future.delayed(const Duration(seconds: 2), _startDownload);
    }
  }
  
  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _statusMessage = 'Starting download...';
    });
    
    await _downloadService.downloadModel();
  }
  
  Future<void> _loadModel() async {
    setState(() {
      _isLoading = true;
      _needsDownload = false;
      _statusMessage = 'Initializing AI engine...';
      _errorMessage = null;
    });
    
    try {
      // First check model file exists and get its size
      final modelPath = await _downloadService.getModelPath();
      String fileSizeInfo = '';
      if (modelPath != null) {
        final file = File(modelPath);
        if (await file.exists()) {
          final sizeBytes = await file.length();
          final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
          fileSizeInfo = ' (${sizeMB}MB)';
          print('📁 Model file: $modelPath$fileSizeInfo');
        }
      }
      
      // Emit loading states
      _downloadService.emitLoadProgress(ModelLoadState.locatingModel,
          progress: 0.1, message: 'Locating model file$fileSizeInfo...');
      await Future.delayed(const Duration(milliseconds: 500));
      
      _downloadService.emitLoadProgress(ModelLoadState.loadingToMemory,
          progress: 0.3, message: 'Loading model to memory$fileSizeInfo...');
      await Future.delayed(const Duration(milliseconds: 300));
      
      _downloadService.emitLoadProgress(ModelLoadState.initializingEngine,
          progress: 0.6, message: 'Initializing inference engine (this may take 30-60 seconds)...');
      
      // Actually initialize the service with error handling
      final success = await _MedAssistAppService.initialize();
      
      if (success) {
        _downloadService.emitLoadProgress(ModelLoadState.warmingUp,
            progress: 0.9, message: 'Warming up neural networks...');
        await Future.delayed(const Duration(milliseconds: 500));
        
        _downloadService.emitLoadProgress(ModelLoadState.ready,
            progress: 1.0, message: 'Med Assist App ready!');
      } else {
        final status = await _MedAssistAppService.checkStatus();
        String errorMsg = status.error ?? 'Failed to initialize model';
        
        // Add file size info for debugging
        if (fileSizeInfo.isNotEmpty) {
          errorMsg += '\n\nModel file exists$fileSizeInfo but failed to load.';
        }
        
        // Provide more helpful error messages
        if (errorMsg.contains('not found')) {
          errorMsg = 'Model file not found. Download may have failed - try again.';
        } else if (errorMsg.contains('memory')) {
          errorMsg = 'Not enough memory. Try closing other apps and restart.';
        } else if (errorMsg.contains('too small')) {
          errorMsg = 'Model file corrupted (too small). Please re-download.';
        }
        
        _downloadService.emitLoadProgress(ModelLoadState.error, error: errorMsg);
      }
    } catch (e) {
      print('❌ Exception during model load: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString().split('\n').first}';
      });
      _downloadService.emitLoadProgress(ModelLoadState.error,
          error: 'Initialization crashed. Model format may be incompatible.');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            // Animated background
            _buildAnimatedBackground(),
            
            // Main content
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo/Icon with animation
                    _buildAnimatedLogo(),
                    const SizedBox(height: 48),
                    
                    // Title
                    Text(
                      'Med Assist App',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      'AI Medical Assistant',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white60,
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                    
                    const SizedBox(height: 48),
                    
                    // Progress section
                    _buildProgressSection(),
                    
                    const SizedBox(height: 32),
                    
                    // Action buttons
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return CustomPaint(
          painter: WaveBackgroundPainter(
            animation: _waveController.value,
            color: AppTheme.accent.withOpacity(0.1),
          ),
          size: Size.infinite,
        );
      },
    );
  }
  
  Widget _buildAnimatedLogo() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _rotateController]),
      builder: (context, child) {
        final pulse = 1.0 + (_pulseController.value * 0.1);
        final rotate = _isLoading || _isDownloading ? _rotateController.value * 2 * math.pi : 0.0;
        
        return Transform.scale(
          scale: pulse,
          child: Transform.rotate(
            angle: rotate * 0.1,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accent.withOpacity(0.3),
                    AppTheme.accent.withOpacity(0.1),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring
                  if (_isDownloading || _isLoading)
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: _getCurrentProgress(),
                        strokeWidth: 3,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(AppTheme.accent),
                      ),
                    ),
                  
                  // Inner icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.darkSurface,
                      border: Border.all(
                        color: AppTheme.accent.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _getStatusIcon(),
                      size: 40,
                      color: _isReady ? Colors.green : AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildProgressSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.glassDecoration(
        color: AppTheme.darkSurface,
        opacity: 0.3,
      ),
      child: Column(
        children: [
          // Status message
          Text(
            _statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ).animate(
            onPlay: (controller) => controller.repeat(),
          ).shimmer(
            duration: 2000.ms,
            color: Colors.white24,
          ),
          
          const SizedBox(height: 16),
          
          // Download progress bar
          if (_isDownloading && _downloadProgress != null) ...[
            _buildDownloadProgress(),
          ],
          
          // Loading progress bar
          if (_isLoading && _loadProgress != null) ...[
            _buildLoadProgress(),
          ],
          
          // Error message
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ).animate().shake(),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2);
  }
  
  Widget _buildDownloadProgress() {
    final progress = _downloadProgress!;
    return Column(
      children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.progress,
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(AppTheme.accent),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Progress details
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              progress.progressPercent,
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${progress.downloadedSize} / ${progress.totalSize}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (progress.speedText.isNotEmpty)
                  Text(
                    '${progress.speedText} • ${progress.etaText}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Animated particles during download
        SizedBox(
          height: 20,
          child: _buildDownloadParticles(),
        ),
      ],
    );
  }
  
  Widget _buildLoadProgress() {
    final progress = _loadProgress!;
    return Column(
      children: [
        // Progress bar with gradient
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              LinearProgressIndicator(
                value: progress.progress,
                minHeight: 8,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(Colors.green),
              ),
              // Shimmer effect
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ).animate(
                  onPlay: (c) => c.repeat(),
                ).moveX(
                  begin: -200,
                  end: 200,
                  duration: 1500.ms,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Stage indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildStageIndicator('Locate', progress.state.index >= 1),
            _buildStageLine(progress.state.index >= 2),
            _buildStageIndicator('Load', progress.state.index >= 2),
            _buildStageLine(progress.state.index >= 3),
            _buildStageIndicator('Init', progress.state.index >= 3),
            _buildStageLine(progress.state.index >= 4),
            _buildStageIndicator('Ready', progress.state.index >= 5),
          ],
        ),
      ],
    );
  }
  
  Widget _buildStageIndicator(String label, bool active) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.green : Colors.white24,
          ),
          child: active
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white54,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStageLine(bool active) {
    return Container(
      width: 30,
      height: 2,
      margin: const EdgeInsets.only(bottom: 16),
      color: active ? Colors.green : Colors.white24,
    );
  }
  
  Widget _buildDownloadParticles() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accent,
          ),
        ).animate(
          onPlay: (c) => c.repeat(),
          delay: Duration(milliseconds: index * 100),
        ).scale(
          begin: const Offset(0.5, 0.5),
          end: const Offset(1.0, 1.0),
          duration: 500.ms,
        ).then().scale(
          begin: const Offset(1.0, 1.0),
          end: const Offset(0.5, 0.5),
          duration: 500.ms,
        );
      }),
    );
  }
  
  Widget _buildActionButtons() {
    // Show loading spinner while checking
    if (_isChecking) {
      return const CircularProgressIndicator(color: Colors.white54);
    }
    
    if (_isReady) {
      return ElevatedButton.icon(
        onPressed: widget.onReady,
        icon: const Icon(Icons.arrow_forward),
        label: const Text('Start Chat'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
      ).animate().scale(delay: 200.ms);
    }
    
    if (_needsDownload && !_isDownloading) {
      return Column(
        children: [
          // BIG download button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.cloud_download, size: 28),
              label: const Text(
                'DOWNLOAD MODEL\n(2.53 GB from Google Drive)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Manual option
          Text(
            'Or copy med-assist-app-2b.task to:\nDocuments/Med Assist App/models/',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ).animate().fadeIn(delay: 300.ms);
    }
    
    if (_isDownloading) {
      return TextButton.icon(
        onPressed: () {
          _downloadService.cancelDownload();
          setState(() {
            _isDownloading = false;
            _needsDownload = true;
            _statusMessage = 'Download cancelled';
          });
        },
        icon: const Icon(Icons.cancel, color: Colors.red),
        label: const Text('Cancel Download', style: TextStyle(color: Colors.red)),
      );
    }
    
    if (_errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: _needsDownload ? _startDownload : _loadModel,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: widget.onReady,  // Skip and continue to app
            icon: const Icon(Icons.skip_next, color: Colors.white54),
            label: const Text(
              'Skip for now (limited functionality)',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      );
    }
    
    return const SizedBox.shrink();
  }
  
  double? _getCurrentProgress() {
    if (_isDownloading && _downloadProgress != null) {
      return _downloadProgress!.progress;
    }
    if (_isLoading && _loadProgress != null) {
      return _loadProgress!.progress;
    }
    return null;
  }
  
  IconData _getStatusIcon() {
    if (_isReady) return Icons.check_circle;
    if (_errorMessage != null) return Icons.error;
    if (_isDownloading) return Icons.cloud_download;
    if (_isLoading) return Icons.memory;
    if (_needsDownload) return Icons.cloud_off;
    return Icons.local_hospital;
  }
}

/// Wave background painter
class WaveBackgroundPainter extends CustomPainter {
  final double animation;
  final Color color;
  
  WaveBackgroundPainter({required this.animation, required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = Path();
    final waveHeight = 50.0;
    final waveLength = size.width / 2;
    
    path.moveTo(0, size.height);
    
    for (double x = 0; x <= size.width; x++) {
      final y = size.height - 100 +
          math.sin((x / waveLength * 2 * math.pi) + (animation * 2 * math.pi)) * waveHeight;
      path.lineTo(x, y);
    }
    
    path.lineTo(size.width, size.height);
    path.close();
    
    canvas.drawPath(path, paint);
    
    // Second wave
    final paint2 = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    
    final path2 = Path();
    path2.moveTo(0, size.height);
    
    for (double x = 0; x <= size.width; x++) {
      final y = size.height - 60 +
          math.sin((x / waveLength * 2 * math.pi) + (animation * 2 * math.pi) + math.pi / 4) * waveHeight * 0.7;
      path2.lineTo(x, y);
    }
    
    path2.lineTo(size.width, size.height);
    path2.close();
    
    canvas.drawPath(path2, paint2);
  }
  
  @override
  bool shouldRepaint(covariant WaveBackgroundPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
