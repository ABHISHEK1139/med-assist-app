import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'dart:io';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/glass_container.dart';
import '../bloc/chat_bloc.dart';

/// Multimodal Input Bar
/// 
/// Smart input component with:
/// - Text input with send button
/// - "+" button for file/image attachment
/// - File type selector (Lab Report, X-ray, Prescription)
/// - "Digesting File..." progress indicator
class MultimodalInputBar extends StatefulWidget {
  const MultimodalInputBar({super.key});

  @override
  State<MultimodalInputBar> createState() => _MultimodalInputBarState();
}

// Pending file attachment model
class PendingAttachment {
  final String fileName;
  final List<int> fileBytes;
  final String docType;
  final String? filePath;
  
  PendingAttachment({
    required this.fileName,
    required this.fileBytes,
    required this.docType,
    this.filePath,
  });
}

class _MultimodalInputBarState extends State<MultimodalInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isExpanded = false;
  bool _hasText = false;  // Track text state for send button
  PendingAttachment? _pendingAttachment; // Store file until user sends
  
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastRecognizedWords = '';
  
  @override
  void initState() {
    super.initState();
    // Listen for text changes to update send button state
    _controller.addListener(_onTextChanged);
    _initSpeech();
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (val) => print('Speech Error: $val'),
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (mounted) setState(() {});
  }

  void _startListening() async {
    if (!_speechEnabled) return;
    
    // Clear any previous temporary dictation
    _lastRecognizedWords = '';
    
    await _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
    );
    if (mounted) setState(() => _isListening = true);
  }

  void _stopListening() async {
    await _speechToText.stop();
    if (mounted) setState(() => _isListening = false);
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (mounted) {
      setState(() {
        // Find what was just recognized in this session
        final newWords = result.recognizedWords;
        
        // Remove the previous _lastRecognizedWords from the controller if we appended it
        final currentText = _controller.text;
        if (currentText.endsWith(_lastRecognizedWords) && _lastRecognizedWords.isNotEmpty) {
           _controller.text = currentText.substring(0, currentText.length - _lastRecognizedWords.length);
        }
        
        // Append the new recognized string
        final separator = _controller.text.isEmpty || _controller.text.endsWith(' ') ? '' : ' ';
        _controller.text = _controller.text + separator + newWords;
        
        // Move cursor to end
        _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length));
            
        _lastRecognizedWords = separator + newWords;
      });
    }
  }
  
  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }
  
  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  void _sendMessage() {
    final message = _controller.text.trim();
    
    // If there's a pending attachment, send it with the message
    if (_pendingAttachment != null) {
      context.read<ChatBloc>().add(DocumentUploaded(
        filePath: _pendingAttachment!.filePath ?? '',
        fileName: _pendingAttachment!.fileName,
        fileBytes: _pendingAttachment!.fileBytes,
        docType: _pendingAttachment!.docType,
        userMessage: message.isNotEmpty ? message : null, // Include user's message
      ));
      setState(() => _pendingAttachment = null);
      _controller.clear();
      _focusNode.requestFocus();
      return;
    }
    
    // Normal text message
    if (message.isEmpty) return;
    
    context.read<ChatBloc>().add(MessageSent(message: message));
    _controller.clear();
    _focusNode.requestFocus();
  }
  
  void _clearPendingAttachment() {
    setState(() => _pendingAttachment = null);
  }
  
  Future<void> _pickDocument(String docType) async {
    setState(() => _isExpanded = false);
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: AppConstants.allowedFileExtensions,
        withData: true, // Get file bytes
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        if (file.bytes != null) {
          if (!mounted) return;
          
          // Store the file as pending - DON'T upload yet!
          // User must click send button to upload
          setState(() {
            _pendingAttachment = PendingAttachment(
              fileName: file.name,
              fileBytes: file.bytes!,
              docType: docType,
              filePath: file.path,
            );
          });
          
          // Focus the text field so user can add a message
          _focusNode.requestFocus();
        }
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick file: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  /// Capture photo with camera
  Future<void> _capturePhoto(String docType) async {
    setState(() => _isExpanded = false);
    
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image != null) {
        final file = File(image.path);
        final bytes = await file.readAsBytes();
        final fileName = 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
        
        if (!mounted) return;
        
        setState(() {
          _pendingAttachment = PendingAttachment(
            fileName: fileName,
            fileBytes: bytes,
            docType: docType,
            filePath: image.path,
          );
        });
        
        // Focus the text field so user can add a message
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Camera error: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: GlassContainer(
              padding: const EdgeInsets.all(8),
              borderRadius: 30,
              opacity: 0.15,
              blur: 15,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Upload progress indicator
                if (state.isUploadingDocument)
                  _buildUploadProgress(state.uploadProgress ?? 'Uploading...'),
                
                // Expanded file type picker
                if (_isExpanded) _buildFileTypePicker(),
                
                // Pending attachment preview - shows file before sending
                if (_pendingAttachment != null) _buildPendingAttachmentPreview(),
                
                // Main input row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Attach button
                    _buildAttachButton(),
                    
                    const SizedBox(width: 8),
                    
                    // Text input
                    Expanded(
                      child: _buildTextInput(state),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Mic button (if speech is enabled and we aren't typing heavily)
                    if (_speechEnabled && !(_hasText && !_isListening))
                      _buildMicButton(),
                    
                    if (_speechEnabled && !(_hasText && !_isListening))
                      const SizedBox(width: 8),
                    
                    // Send button
                    _buildSendButton(state),
                  ],
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildUploadProgress(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ).animate(
        onPlay: (controller) => controller.repeat(),
      ).shimmer(
        duration: 1500.ms,
        color: AppTheme.accent.withOpacity(0.2),
      ),
    );
  }
  
  Widget _buildPendingAttachmentPreview() {
    final docTypeLabels = {
      'lab_report': 'Lab Report',
      'prescription': 'Prescription',
      'radiology': 'X-Ray / Imaging',
      'notes': 'Medical Notes',
      'general': 'Document',
    };
    
    final docTypeIcons = {
      'lab_report': Icons.science_outlined,
      'prescription': Icons.medication_outlined,
      'radiology': Icons.image_outlined,
      'notes': Icons.notes_outlined,
      'general': Icons.insert_drive_file_outlined,
    };
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            docTypeIcons[_pendingAttachment!.docType] ?? Icons.attach_file,
            color: AppTheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pendingAttachment!.fileName,
                  style: TextStyle(
                    color: AppTheme.textPrimaryDark,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Tap send when ready →',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Remove button
          InkWell(
            onTap: _clearPendingAttachment,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.close,
                color: AppTheme.error,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.2, end: 0);
  }
  
  Widget _buildFileTypePicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Camera and file upload
          Row(
            children: [
              _buildFileTypeChip(
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                onTap: () => _capturePhoto('radiology'),
              ),
              const SizedBox(width: 8),
              _buildFileTypeChip(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: () => _pickImageFromGallery('radiology'),
              ),
              const SizedBox(width: 8),
              _buildFileTypeChip(
                icon: Icons.insert_drive_file_outlined,
                label: 'File',
                onTap: () => _pickDocument('general'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Document types
          Row(
            children: [
              _buildFileTypeChip(
                icon: Icons.science_outlined,
                label: 'Lab Report',
                onTap: () => _pickDocument('lab_report'),
              ),
              const SizedBox(width: 8),
              _buildFileTypeChip(
                icon: Icons.medication_outlined,
                label: 'Prescription',
                onTap: () => _pickDocument('prescription'),
              ),
              const SizedBox(width: 8),
              _buildFileTypeChip(
                icon: Icons.image_outlined,
                label: 'X-Ray',
                onTap: () => _pickDocument('radiology'),
              ),
            ],
          ),
        ],
      ).animate().fadeIn().slideY(begin: 0.2, end: 0),
    );
  }
  
  /// Pick image from gallery
  Future<void> _pickImageFromGallery(String docType) async {
    setState(() => _isExpanded = false);
    
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image != null) {
        final file = File(image.path);
        final bytes = await file.readAsBytes();
        final fileName = image.name.isNotEmpty 
            ? image.name 
            : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        
        if (!mounted) return;
        
        setState(() {
          _pendingAttachment = PendingAttachment(
            fileName: fileName,
            fileBytes: bytes,
            docType: docType,
            filePath: image.path,
          );
        });
        
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gallery error: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
  
  Widget _buildFileTypeChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              children: [
                Icon(icon, color: AppTheme.primary, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondaryDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAttachButton() {
    return Container(
      decoration: BoxDecoration(
        color: _isExpanded ? AppTheme.primary.withOpacity(0.2) : AppTheme.darkCard.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: GestureDetector(
        onTap: () {
          // Single tap: directly open file picker (like modern chatbots)
          _pickDocument('general');
        },
        onLongPress: () {
          // Long press: show document type options
          setState(() => _isExpanded = !_isExpanded);
        },
        child: IconButton(
          onPressed: null, // Handled by GestureDetector
          icon: AnimatedRotation(
            turns: _isExpanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _pendingAttachment != null ? Icons.attach_file : Icons.add,
              color: _pendingAttachment != null 
                  ? AppTheme.primary 
                  : (_isExpanded ? AppTheme.primary : AppTheme.textSecondaryDark),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildTextInput(ChatState state) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: state.canSendMessage,
        maxLines: 4,
        minLines: 1,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _sendMessage(),
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: state.isThinking
              ? 'AI is thinking...'
              : _pendingAttachment != null
                  ? 'Add a message...'
                  : 'Ask a health question...',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          fillColor: Colors.transparent, // Let glass show through
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
  
  Widget _buildSendButton(ChatState state) {
    // Enable send if there's text OR a pending attachment
    final hasContent = _hasText || _pendingAttachment != null;
    final canSend = state.canSendMessage && hasContent;
    
    return Container(
      decoration: BoxDecoration(
        gradient: hasContent ? AppTheme.primaryGradient : null,
        color: !hasContent ? AppTheme.darkCard.withOpacity(0.5) : null,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: canSend ? _sendMessage : null,
        icon: Icon(
          Icons.arrow_upward_rounded,
          color: hasContent ? Colors.white : AppTheme.textSecondaryDark,
        ),
        tooltip: 'Send message',
      ),
    );
  }

  Widget _buildMicButton() {
    return Container(
      decoration: BoxDecoration(
        color: _isListening ? AppTheme.error.withOpacity(0.2) : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: _isListening ? AppTheme.error : Colors.transparent,
        ),
      ),
      child: IconButton(
        onPressed: _speechToText.isNotListening ? _startListening : _stopListening,
        icon: Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          color: _isListening ? AppTheme.error : AppTheme.textSecondaryDark,
        ),
        tooltip: 'Hold to speak',
      ).animate(target: _isListening ? 1 : 0)
       .scaleXY(begin: 1.0, end: 1.1, duration: 200.ms)
       .tint(color: AppTheme.error.withOpacity(0.5)),
    );
  }
}
