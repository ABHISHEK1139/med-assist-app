import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/med_assist_service.dart';
import '../../../services/pc_backend_service.dart';

part 'chat_event.dart';
part 'chat_state.dart';

/// Chat BLoC - Manages chat state and AI interactions
/// 
/// Features:
/// - Agentic reasoning with visible thinking steps
/// - Stop generation mid-response
/// - Edit and regenerate messages
/// - Automatic medical data extraction
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final MedAssistAppService _medAssistApp = MedAssistAppService();
  final PCBackendService _backend = PCBackendService();
  
  // Cancellation support
  bool _isCancelled = false;
  Completer<void>? _currentGeneration;
  
  ChatBloc({
    dynamic aiService, // Kept for compatibility, not used
  }) : super(ChatState.initial()) {
    on<ChatInitialized>(_onInitialized);
    on<MessageSent>(_onMessageSent);
    on<GenerationStopped>(_onGenerationStopped);
    on<MessageEdited>(_onMessageEdited);
    on<ReasoningToggled>(_onReasoningToggled);
    on<ResponseRegenerated>(_onResponseRegenerated);
    on<DocumentUploaded>(_onDocumentUploaded);
    on<ExplanationRequested>(_onExplanationRequested);
    on<ChatCleared>(_onChatCleared);
    on<ChatMessagesLoaded>(_onMessagesLoaded);
  }
  
  Future<void> _onInitialized(
    ChatInitialized event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.loading));
    
    try {
      // Initialize on-device Med Assist App
      final ready = await _medAssistApp.initialize();
      final status = await _medAssistApp.checkStatus();
      
      if (ready) {
        emit(state.copyWith(
          status: ChatStatus.ready,
          isModelReady: status.modelLoaded,
          isMemoryReady: status.archiveReady,
          gpuEnabled: true,
        ));
      } else {
        emit(state.copyWith(
          status: ChatStatus.degraded,
          isModelReady: false,
          error: status.error ?? 'Model not loaded.',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        error: 'Failed to initialize: $e',
      ));
    }
  }
  
  Future<void> _onMessageSent(
    MessageSent event,
    Emitter<ChatState> emit,
  ) async {
    _isCancelled = false;
    _currentGeneration = Completer<void>();
    
    // Add user message to chat
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: event.message,
      isUser: true,
      timestamp: DateTime.now(),
    );
    
    // Start with reasoning status
    emit(state.copyWith(
      messages: [...state.messages, userMessage],
      status: ChatStatus.reasoning,
      currentReasoning: [],
      isCancelled: false,
    ));
    
    try {
      final startTime = DateTime.now();
      final reasoningSteps = <ReasoningStep>[];
      
      // Add initial "thinking" step
      reasoningSteps.add(ReasoningStep(
        id: '${DateTime.now().millisecondsSinceEpoch}_think1',
        thought: 'Understanding your question...',
        timestamp: DateTime.now(),
      ));
      emit(state.copyWith(currentReasoning: List.from(reasoningSteps)));
      
      if (_isCancelled) {
        _handleCancellation(emit, reasoningSteps);
        return;
      }
      
      // Add "checking health data" step
      await Future.delayed(const Duration(milliseconds: 300));
      reasoningSteps.add(ReasoningStep(
        id: '${DateTime.now().millisecondsSinceEpoch}_think2',
        thought: 'Checking your health records...',
        action: 'query_symptoms',
        timestamp: DateTime.now(),
      ));
      emit(state.copyWith(currentReasoning: List.from(reasoningSteps)));
      
      if (_isCancelled) {
        _handleCancellation(emit, reasoningSteps);
        return;
      }
      
      // Update status to show we're calling the AI
      reasoningSteps.add(ReasoningStep(
        id: '${DateTime.now().millisecondsSinceEpoch}_think3',
        thought: 'Analyzing with AI...',
        timestamp: DateTime.now(),
      ));
      emit(state.copyWith(
        currentReasoning: List.from(reasoningSteps),
        status: ChatStatus.thinking,
      ));
      
      // Use agentic chat for smart responses
      final response = await _medAssistApp.chat(event.message);
      
      if (_isCancelled) {
        _handleCancellation(emit, reasoningSteps);
        return;
      }
      
      final inferenceTime = DateTime.now().difference(startTime).inMilliseconds;
      
      // Mark reasoning as complete
      final completedSteps = reasoningSteps.map((s) => s.copyWith(isComplete: true)).toList();
      completedSteps.add(ReasoningStep(
        id: '${DateTime.now().millisecondsSinceEpoch}_done',
        thought: 'Generated response',
        isComplete: true,
        timestamp: DateTime.now(),
      ));
      
      // Add AI response to chat with reasoning history
      final aiMessage = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_ai',
        content: response,
        isUser: false,
        timestamp: DateTime.now(),
        inferenceTimeMs: inferenceTime,
        reasoningSteps: completedSteps,
        toolCallsCount: completedSteps.where((s) => s.action != null).length,
      );
      
      emit(state.copyWith(
        messages: [...state.messages, aiMessage],
        status: ChatStatus.ready,
        currentReasoning: [],
      ));
      
    } catch (e) {
      if (_isCancelled) return;
      
      final errorMessage = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_error',
        content: 'Sorry, I encountered an error: $e',
        isUser: false,
        timestamp: DateTime.now(),
        isError: true,
      );
      
      emit(state.copyWith(
        messages: [...state.messages, errorMessage],
        status: ChatStatus.ready,
        currentReasoning: [],
        error: e.toString(),
      ));
    } finally {
      _currentGeneration?.complete();
      _currentGeneration = null;
    }
  }
  
  void _handleCancellation(Emitter<ChatState> emit, List<ReasoningStep> steps) {
    final cancelledMessage = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_cancelled',
      content: '⏹️ Generation stopped by user',
      isUser: false,
      timestamp: DateTime.now(),
      isSystemMessage: true,
      reasoningSteps: steps,
    );
    
    emit(state.copyWith(
      messages: [...state.messages, cancelledMessage],
      status: ChatStatus.ready,
      currentReasoning: [],
      isCancelled: true,
    ));
  }
  
  void _onGenerationStopped(
    GenerationStopped event,
    Emitter<ChatState> emit,
  ) {
    _isCancelled = true;
    emit(state.copyWith(isCancelled: true));
  }
  
  Future<void> _onMessageEdited(
    MessageEdited event,
    Emitter<ChatState> emit,
  ) async {
    // Find the message index
    final messageIndex = state.messages.indexWhere((m) => m.id == event.messageId);
    if (messageIndex == -1) return;
    
    // Remove all messages after this one (including AI responses)
    final newMessages = state.messages.sublist(0, messageIndex);
    
    // Add edited message marker
    final editedMessage = state.messages[messageIndex].copyWith(
      content: event.newContent,
      isEdited: true,
    );
    newMessages.add(editedMessage);
    
    emit(state.copyWith(messages: newMessages));
    
    // Regenerate response with edited content
    add(MessageSent(message: event.newContent));
  }
  
  void _onReasoningToggled(
    ReasoningToggled event,
    Emitter<ChatState> emit,
  ) {
    final updatedMessages = state.messages.map((m) {
      if (m.id == event.messageId) {
        return m.copyWith(showReasoning: !m.showReasoning);
      }
      return m;
    }).toList();
    
    emit(state.copyWith(messages: updatedMessages));
  }
  
  Future<void> _onResponseRegenerated(
    ResponseRegenerated event,
    Emitter<ChatState> emit,
  ) async {
    // Find the last user message
    final lastUserMsgIndex = state.messages.lastIndexWhere((m) => m.isUser);
    if (lastUserMsgIndex == -1) return;
    
    final lastUserMsg = state.messages[lastUserMsgIndex];
    
    // Remove all messages after and including the last AI response
    final newMessages = state.messages.sublist(0, lastUserMsgIndex + 1);
    emit(state.copyWith(messages: newMessages));
    
    // Regenerate
    add(MessageSent(message: lastUserMsg.content));
  }
  
  Future<void> _onDocumentUploaded(
    DocumentUploaded event,
    Emitter<ChatState> emit,
  ) async {
    // Show uploading status
    final uploadingMessage = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_uploading',
      content: '📤 Uploading ${event.fileName}...',
      isUser: false,
      timestamp: DateTime.now(),
      isSystemMessage: true,
    );
    
    emit(state.copyWith(
      messages: [...state.messages, uploadingMessage],
      status: ChatStatus.thinking,
    ));
    
    try {
      // Upload document to PC backend
      final result = await _backend.uploadDocument(
        filePath: event.filePath,
        fileName: event.fileName,
        fileBytes: event.fileBytes,
        docType: event.docType,
        userMessage: event.userMessage,
      );
      
      // Remove uploading message
      final messagesWithoutUploading = state.messages
          .where((m) => m.id != uploadingMessage.id)
          .toList();
      
      if (result.success) {
        // Add user message showing what was uploaded
        final userMessage = ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}_user',
          content: '📄 Uploaded: ${event.fileName}'
              '${event.userMessage != null ? '\n${event.userMessage}' : ''}',
          isUser: true,
          timestamp: DateTime.now(),
        );
        
        // Add AI analysis response
        final aiResponse = ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}_ai',
          content: result.aiAnalysis ?? 
              '✅ Document processed (${result.docType ?? "unknown type"})\n\n'
              '${result.message ?? "Stored for future reference."}',
          isUser: false,
          timestamp: DateTime.now(),
        );
        
        emit(state.copyWith(
          messages: [...messagesWithoutUploading, userMessage, aiResponse],
          status: ChatStatus.ready,
        ));
      } else {
        // Error message
        final errorMessage = ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}_error',
          content: '❌ Failed to upload document:\n${result.error ?? "Unknown error"}',
          isUser: false,
          timestamp: DateTime.now(),
          isSystemMessage: true,
        );
        
        emit(state.copyWith(
          messages: [...messagesWithoutUploading, errorMessage],
          status: ChatStatus.ready,
        ));
      }
    } catch (e) {
      // Remove uploading message and show error
      final messagesWithoutUploading = state.messages
          .where((m) => m.id != uploadingMessage.id)
          .toList();
      
      final errorMessage = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_error',
        content: '❌ Document upload failed: $e',
        isUser: false,
        timestamp: DateTime.now(),
        isSystemMessage: true,
      );
      
      emit(state.copyWith(
        messages: [...messagesWithoutUploading, errorMessage],
        status: ChatStatus.ready,
        error: e.toString(),
      ));
    }
  }
  
  Future<void> _onExplanationRequested(
    ExplanationRequested event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.thinking));
    
    try {
      final response = await _medAssistApp.chat(
        'Please explain this in simpler terms: ${event.originalResponse}'
      );
      
      final explanationMessage = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_explain',
        content: '💡 **Explanation**\n\n$response',
        isUser: false,
        timestamp: DateTime.now(),
        isExplanation: true,
      );
      
      emit(state.copyWith(
        messages: [...state.messages, explanationMessage],
        status: ChatStatus.ready,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.ready,
        error: 'Failed to get explanation: $e',
      ));
    }
  }
  
  void _onChatCleared(
    ChatCleared event,
    Emitter<ChatState> emit,
  ) {
    // Clear conversation session on server
    _backend.clearConversationSession();
    
    emit(ChatState.initial().copyWith(
      isModelReady: state.isModelReady,
      isMemoryReady: state.isMemoryReady,
      gpuEnabled: state.gpuEnabled,
      status: ChatStatus.ready,
    ));
  }
  
  void _onMessagesLoaded(
    ChatMessagesLoaded event,
    Emitter<ChatState> emit,
  ) {
    // Load messages from history into the UI
    emit(state.copyWith(
      messages: event.messages,
      status: ChatStatus.ready,
    ));
  }
}
