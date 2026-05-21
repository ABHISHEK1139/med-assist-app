part of 'chat_bloc.dart';

/// Chat status enum
enum ChatStatus {
  initial,
  loading,
  ready,
  thinking,
  reasoning,  // NEW: Multi-step reasoning in progress
  degraded,
  error,
}

/// A reasoning step shown during agentic processing
class ReasoningStep extends Equatable {
  final String id;
  final String thought;
  final String? action;  // Tool being called
  final String? observation;  // Result of tool
  final bool isComplete;
  final DateTime timestamp;
  
  const ReasoningStep({
    required this.id,
    required this.thought,
    this.action,
    this.observation,
    this.isComplete = false,
    required this.timestamp,
  });
  
  @override
  List<Object?> get props => [id, thought, action, observation, isComplete];
  
  ReasoningStep copyWith({
    String? thought,
    String? action,
    String? observation,
    bool? isComplete,
  }) {
    return ReasoningStep(
      id: id,
      thought: thought ?? this.thought,
      action: action ?? this.action,
      observation: observation ?? this.observation,
      isComplete: isComplete ?? this.isComplete,
      timestamp: timestamp,
    );
  }
}

/// A single chat message
class ChatMessage extends Equatable {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final int? inferenceTimeMs;
  final bool isError;
  final bool isSystemMessage;
  final bool isExplanation;
  final bool isBookmarked;
  final bool isEdited;  // NEW: Was this message edited
  final List<ReasoningStep> reasoningSteps;  // NEW: Agentic reasoning
  final bool showReasoning;  // NEW: Whether to expand reasoning
  final int? toolCallsCount;  // NEW: How many tools were called
  
  const ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.inferenceTimeMs,
    this.isError = false,
    this.isSystemMessage = false,
    this.isExplanation = false,
    this.isBookmarked = false,
    this.isEdited = false,
    this.reasoningSteps = const [],
    this.showReasoning = false,
    this.toolCallsCount,
  });
  
  @override
  List<Object?> get props => [
    id,
    content,
    isUser,
    timestamp,
    inferenceTimeMs,
    isError,
    isSystemMessage,
    isExplanation,
    isBookmarked,
    isEdited,
    reasoningSteps,
    showReasoning,
    toolCallsCount,
  ];
  
  /// Whether this message has reasoning to show
  bool get hasReasoning => reasoningSteps.isNotEmpty;
  
  /// Create a copy with modified fields
  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    int? inferenceTimeMs,
    bool? isError,
    bool? isSystemMessage,
    bool? isExplanation,
    bool? isBookmarked,
    bool? isEdited,
    List<ReasoningStep>? reasoningSteps,
    bool? showReasoning,
    int? toolCallsCount,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      inferenceTimeMs: inferenceTimeMs ?? this.inferenceTimeMs,
      isError: isError ?? this.isError,
      isSystemMessage: isSystemMessage ?? this.isSystemMessage,
      isExplanation: isExplanation ?? this.isExplanation,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      isEdited: isEdited ?? this.isEdited,
      reasoningSteps: reasoningSteps ?? this.reasoningSteps,
      showReasoning: showReasoning ?? this.showReasoning,
      toolCallsCount: toolCallsCount ?? this.toolCallsCount,
    );
  }
  
  /// Serialize to JSON for persistence
  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
    'inferenceTimeMs': inferenceTimeMs,
    'isError': isError,
    'isSystemMessage': isSystemMessage,
    'isExplanation': isExplanation,
    'isBookmarked': isBookmarked,
  };
  
  /// Deserialize from JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      isUser: json['isUser'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      inferenceTimeMs: json['inferenceTimeMs'] as int?,
      isError: json['isError'] as bool? ?? false,
      isSystemMessage: json['isSystemMessage'] as bool? ?? false,
      isExplanation: json['isExplanation'] as bool? ?? false,
      isBookmarked: json['isBookmarked'] as bool? ?? false,
    );
  }
  
  /// Format timestamp for display
  String get formattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    final hour = timestamp.hour == 0 ? 12 : (timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour);
    final period = timestamp.hour >= 12 ? 'PM' : 'AM';
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final time = '$hour:$minute $period';
    
    if (messageDate == today) {
      return time;
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $time';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[timestamp.month - 1]} ${timestamp.day}, $time';
    }
  }
}

/// Chat state
class ChatState extends Equatable {
  final ChatStatus status;
  final List<ChatMessage> messages;
  final bool isModelReady;
  final bool isMemoryReady;
  final bool gpuEnabled;
  final bool isUploadingDocument;
  final String? uploadProgress;
  final String? error;
  final List<ReasoningStep> currentReasoning;  // NEW: Live reasoning steps
  final bool isCancelled;  // NEW: Was generation cancelled
  final String? editingMessageId;  // NEW: Message being edited
  final bool isConsultationMode; // NEW: Multi-agent debate mode
  
  const ChatState({
    required this.status,
    required this.messages,
    required this.isModelReady,
    required this.isMemoryReady,
    required this.gpuEnabled,
    required this.isUploadingDocument,
    this.uploadProgress,
    this.error,
    this.currentReasoning = const [],
    this.isCancelled = false,
    this.editingMessageId,
    this.isConsultationMode = false,
  });
  
  /// Initial state
  factory ChatState.initial() {
    return const ChatState(
      status: ChatStatus.initial,
      messages: [],
      isModelReady: false,
      isMemoryReady: false,
      gpuEnabled: false,
      isUploadingDocument: false,
      currentReasoning: [],
      isConsultationMode: false,
    );
  }
  
  /// Copy with modified fields
  ChatState copyWith({
    ChatStatus? status,
    List<ChatMessage>? messages,
    bool? isModelReady,
    bool? isMemoryReady,
    bool? gpuEnabled,
    bool? isUploadingDocument,
    String? uploadProgress,
    String? error,
    List<ReasoningStep>? currentReasoning,
    bool? isCancelled,
    String? editingMessageId,
    bool? isConsultationMode,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      isModelReady: isModelReady ?? this.isModelReady,
      isMemoryReady: isMemoryReady ?? this.isMemoryReady,
      gpuEnabled: gpuEnabled ?? this.gpuEnabled,
      isUploadingDocument: isUploadingDocument ?? this.isUploadingDocument,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: error,
      currentReasoning: currentReasoning ?? this.currentReasoning,
      isCancelled: isCancelled ?? this.isCancelled,
      editingMessageId: editingMessageId,
      isConsultationMode: isConsultationMode ?? this.isConsultationMode,
    );
  }
  
  @override
  List<Object?> get props => [
    status,
    messages,
    isModelReady,
    isMemoryReady,
    gpuEnabled,
    isUploadingDocument,
    uploadProgress,
    error,
    currentReasoning,
    isCancelled,
    editingMessageId,
    isConsultationMode,
  ];
  
  /// Whether the AI is currently processing
  bool get isThinking => status == ChatStatus.thinking || status == ChatStatus.reasoning;
  
  /// Whether currently in reasoning mode
  bool get isReasoning => status == ChatStatus.reasoning;
  
  /// Whether the chat is ready for input
  bool get canSendMessage =>
      status == ChatStatus.ready || status == ChatStatus.degraded;
}
