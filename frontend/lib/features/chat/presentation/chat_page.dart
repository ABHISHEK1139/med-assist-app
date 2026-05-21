import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/chat_history_service.dart';
import '../../../services/pc_backend_service.dart';
import '../../../screens/documents_screen.dart';
import '../../profile/presentation/profile_page.dart';
import '../../history/history_drawer.dart';
import '../bloc/chat_bloc.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/multimodal_input_bar.dart';
import '../widgets/reasoning_steps_widget.dart';
import '../../../widgets/privacy_badge.dart';

/// Main Chat Page
/// 
/// The primary interface for interacting with Med Assist App.
/// Features:
/// - Message list with AI and user bubbles
/// - Multimodal input bar (text + file upload)
/// - Privacy badge (always visible)
/// - "Why?" button for explainability
/// - Chat history drawer with search
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ChatHistoryService _historyService;
  String? _currentSessionId;
  
  @override
  void initState() {
    super.initState();
    _historyService = ChatHistoryService();
    _initializeHistory();
    // Initialize chat and check backend health
    context.read<ChatBloc>().add(const ChatInitialized());
  }
  
  Future<void> _initializeHistory() async {
    await _historyService.initialize();
    final session = await _historyService.getCurrentSession();
    setState(() => _currentSessionId = session.id);
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: HistoryDrawer(
        historyService: _historyService,
        currentSessionId: _currentSessionId,
        onSessionSelected: _handleSessionSelected,
        onNewChat: _handleNewChat,
      ),
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: Column(
          children: [
            // Chat messages
            Expanded(
              child: BlocConsumer<ChatBloc, ChatState>(
                listener: (context, state) {
                  // Scroll to bottom when new message added
                  if (state.messages.isNotEmpty) {
                    _scrollToBottom();
                    // Save messages to current session
                    _saveCurrentMessages(state.messages);
                  }
                  
                  // Show error snackbar if needed
                  if (state.error != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.error!),
                        backgroundColor: AppTheme.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                builder: (context, state) {
                  if (state.status == ChatStatus.initial ||
                      state.status == ChatStatus.loading) {
                    return _buildLoadingState();
                  }
                  
                  if (state.messages.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  
                  return _buildMessageList(context, state);
                },
              ),
            ),
            
            // Input bar
            const MultimodalInputBar(),
          ],
        ),
      ),
    );
  }
  
  void _handleSessionSelected(ChatSession session) async {
    setState(() => _currentSessionId = session.id);
    
    // Clear current chat
    context.read<ChatBloc>().add(const ChatCleared());
    
    // Load messages from session into server memory (ONCE)
    if (session.messages.isNotEmpty) {
      final history = PCBackendService.messagesToHistory(session.messages);
      await PCBackendService().loadChatSession(history, sessionId: session.id);
      
      // Load messages into the chat bloc UI
      context.read<ChatBloc>().add(ChatMessagesLoaded(session.messages));
    }
  }
  
  void _handleNewChat() async {
    // Clear server session first
    await PCBackendService().clearConversationSession();
    
    final session = await _historyService.startNewConversation();
    setState(() => _currentSessionId = session.id);
    context.read<ChatBloc>().add(const ChatCleared());
  }
  
  void _saveCurrentMessages(List<ChatMessage> messages) async {
    if (_currentSessionId == null || messages.isEmpty) return;
    
    final session = await _historyService.loadSession(_currentSessionId!);
    if (session == null) return;
    
    // Only save if there are new messages
    if (messages.length > session.messages.length) {
      final lastMessage = messages.last;
      await _historyService.addMessageToCurrentSession(lastMessage);
    }
  }
  
  void _toggleBookmark(String messageId) async {
    if (_currentSessionId == null) return;
    
    await _historyService.toggleBookmark(messageId, _currentSessionId!);
    // Force a rebuild to show the updated bookmark state
    setState(() {});
  }
  
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.menu,
            color: Colors.white,
            size: 18,
          ),
        ),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        tooltip: 'Chat History',
      ),
      title: Column(
        children: [
          const Text('Med Assist App'),
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return Text(
                state.isThinking ? 'Analyzing...' : 'Local AI Assistant',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondaryDark,
                ),
              );
            },
          ),
        ],
      ),
      actions: [
        // Documents button
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple, Colors.purple.shade700],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.folder_special,
              color: Colors.white,
              size: 16,
            ),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DocumentsScreen(),
              ),
            );
          },
          tooltip: 'Medical Documents',
        ),
        
        // Health Archive button
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal, Colors.teal.shade700],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.medical_services,
              color: Colors.white,
              size: 16,
            ),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfilePage(),
              ),
            );
          },
          tooltip: 'Health Archive',
        ),
        
        // Privacy Badge
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: PrivacyBadge(),
        ),
        
        // More options menu
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'clear') {
              context.read<ChatBloc>().add(const ChatCleared());
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete_outline),
                  SizedBox(width: 8),
                  Text('Clear Chat'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: AppTheme.glassDecoration(opacity: 0.1),
            child: const CircularProgressIndicator(
              color: AppTheme.primary,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Connecting to Med Assist App...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Initializing local AI model',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ).animate().fadeIn(duration: 300.ms),
    );
  }
  
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo/Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.medical_services_rounded,
                color: Colors.white,
                size: 40,
              ),
            ).animate().scale(
              duration: 400.ms,
              curve: Curves.elasticOut,
            ),
            
            const SizedBox(height: 32),
            
            Text(
              'Welcome to Med Assist App',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 200.ms),
            
            const SizedBox(height: 12),
            
            Text(
              'Your privacy-first medical AI assistant.\nAll processing happens locally on your device.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms),
            
            const SizedBox(height: 32),
            
            // Quick action chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip(
                  context,
                  '🔬 Analyze lab results',
                  'Analyze my recent blood test results',
                ),
                _buildSuggestionChip(
                  context,
                  '💊 Medication info',
                  'What should I know about metformin?',
                ),
                _buildSuggestionChip(
                  context,
                  '🩺 Symptom check',
                  'I have a headache and fatigue',
                ),
              ],
            ).animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSuggestionChip(
    BuildContext context,
    String label,
    String query,
  ) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        context.read<ChatBloc>().add(MessageSent(message: query));
      },
      backgroundColor: AppTheme.darkCard,
      side: const BorderSide(color: AppTheme.darkBorder),
      labelStyle: const TextStyle(color: AppTheme.textPrimaryDark),
    );
  }
  
  Widget _buildMessageList(BuildContext context, ChatState state) {
    return Column(
      children: [
        // Message list
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: state.messages.length,
            itemBuilder: (context, index) {
              final message = state.messages[index];
              return ChatMessageBubble(
                message: message,
                onExplainTapped: !message.isUser && !message.isSystemMessage
                    ? () {
                        context.read<ChatBloc>().add(ExplanationRequested(
                          originalResponse: message.content,
                          referencedDocIds: [],
                        ));
                      }
                    : null,
                onBookmarkToggled: _currentSessionId != null
                    ? () => _toggleBookmark(message.id)
                    : null,
                onReasoningToggled: message.hasReasoning
                    ? () {
                        context.read<ChatBloc>().add(
                          ReasoningToggled(messageId: message.id),
                        );
                      }
                    : null,
                onEditTapped: message.isUser
                    ? () => _showEditDialog(context, message)
                    : null,
                onRegenerateTapped: !message.isUser && !message.isSystemMessage
                    ? () {
                        context.read<ChatBloc>().add(const ResponseRegenerated());
                      }
                    : null,
              );
            },
          ),
        ),
        
        // Live reasoning indicator (shown during generation)
        if (state.isReasoning || (state.isThinking && state.currentReasoning.isNotEmpty))
          LiveReasoningIndicator(
            steps: state.currentReasoning,
            onStop: () {
              context.read<ChatBloc>().add(const GenerationStopped());
            },
          ),
        
        // Simple thinking indicator (when no reasoning steps yet)
        if (state.isThinking && state.currentReasoning.isEmpty)
          _buildSimpleThinkingIndicator(),
      ],
    );
  }
  
  void _showEditDialog(BuildContext context, ChatMessage message) {
    final controller = TextEditingController(text: message.content);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Enter your message...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          style: const TextStyle(color: AppTheme.textPrimaryDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (controller.text.isNotEmpty && controller.text != message.content) {
                context.read<ChatBloc>().add(
                  MessageEdited(
                    messageId: message.id,
                    newContent: controller.text,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
            ),
            child: const Text('Save & Regenerate'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSimpleThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.glassDecoration(
              color: AppTheme.accent,
              opacity: 0.1,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Connecting to AI...',
                  style: TextStyle(
                    color: AppTheme.accent.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ).animate(
            onPlay: (controller) => controller.repeat(),
          ).shimmer(
            duration: 1500.ms,
            color: AppTheme.accent.withOpacity(0.3),
          ),
        ],
      ),
    );
  }
}
