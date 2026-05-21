part of 'chat_bloc.dart';

/// Base class for all chat events
abstract class ChatEvent extends Equatable {
  const ChatEvent();
  
  @override
  List<Object?> get props => [];
}

/// Initialize the chat and check backend health
class ChatInitialized extends ChatEvent {
  const ChatInitialized();
}

/// User sends a message
class MessageSent extends ChatEvent {
  final String message;
  final String analysisType;
  
  const MessageSent({
    required this.message,
    this.analysisType = 'general_health',
  });
  
  @override
  List<Object?> get props => [message, analysisType];
}

/// Stop the current generation
class GenerationStopped extends ChatEvent {
  const GenerationStopped();
}

/// Edit a previous message and regenerate
class MessageEdited extends ChatEvent {
  final String messageId;
  final String newContent;
  
  const MessageEdited({
    required this.messageId,
    required this.newContent,
  });
  
  @override
  List<Object?> get props => [messageId, newContent];
}

/// Toggle reasoning visibility for a message
class ReasoningToggled extends ChatEvent {
  final String messageId;
  
  const ReasoningToggled({required this.messageId});
  
  @override
  List<Object?> get props => [messageId];
}

/// Regenerate the last AI response
class ResponseRegenerated extends ChatEvent {
  const ResponseRegenerated();
}

/// User uploads a document
class DocumentUploaded extends ChatEvent {
  final String filePath;
  final String fileName;
  final List<int> fileBytes;
  final String? docType;
  final String? userMessage; // Optional message to send with the document
  
  const DocumentUploaded({
    required this.filePath,
    required this.fileName,
    required this.fileBytes,
    this.docType,
    this.userMessage,
  });
  
  @override
  List<Object?> get props => [filePath, fileName, docType, userMessage];
}

/// User requests explanation for an AI response ("Why?" button)
class ExplanationRequested extends ChatEvent {
  final String originalResponse;
  final List<String> referencedDocIds;
  
  const ExplanationRequested({
    required this.originalResponse,
    required this.referencedDocIds,
  });
  
  @override
  List<Object?> get props => [originalResponse, referencedDocIds];
}

/// Clear chat history
class ChatCleared extends ChatEvent {
  const ChatCleared();
}

/// Load messages from a saved session (when opening from history)
class ChatMessagesLoaded extends ChatEvent {
  final List<ChatMessage> messages;
  
  const ChatMessagesLoaded(this.messages);
  
  @override
  List<Object?> get props => [messages];
}

/// Toggle multi-agent consultation mode
class ToggleConsultationMode extends ChatEvent {
  const ToggleConsultationMode();
}
