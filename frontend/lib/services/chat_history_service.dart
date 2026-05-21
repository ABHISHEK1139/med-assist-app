import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../features/chat/bloc/chat_bloc.dart';

/// Service for persisting and searching chat history locally
class ChatHistoryService {
  static const String _sessionsBoxName = 'chat_sessions';
  static const String _bookmarksBoxName = 'bookmarks';
  static const String _currentSessionKey = 'current_session_id';
  
  late Box<String> _sessionsBox;
  late Box<String> _bookmarksBox;
  bool _initialized = false;
  
  /// Initialize Hive boxes for persistence
  Future<void> initialize() async {
    if (_initialized) return;
    
    await Hive.initFlutter();
    _sessionsBox = await Hive.openBox<String>(_sessionsBoxName);
    _bookmarksBox = await Hive.openBox<String>(_bookmarksBoxName);
    _initialized = true;
  }
  
  /// Create a new chat session
  Future<ChatSession> createSession() async {
    final session = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New Conversation',
      messages: [],
      createdAt: DateTime.now(),
      lastUpdatedAt: DateTime.now(),
    );
    
    await saveSession(session);
    await _sessionsBox.put(_currentSessionKey, session.id);
    return session;
  }
  
  /// Get or create current session
  Future<ChatSession> getCurrentSession() async {
    final currentId = _sessionsBox.get(_currentSessionKey);
    
    if (currentId != null) {
      final session = await loadSession(currentId);
      if (session != null) return session;
    }
    
    return await createSession();
  }
  
  /// Save a chat session
  Future<void> saveSession(ChatSession session) async {
    final json = jsonEncode(session.toJson());
    await _sessionsBox.put(session.id, json);
  }
  
  /// Load a specific session
  Future<ChatSession?> loadSession(String sessionId) async {
    final json = _sessionsBox.get(sessionId);
    if (json == null) return null;
    
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return ChatSession.fromJson(map);
    } catch (e) {
      return null;
    }
  }
  
  /// Load all sessions (for history drawer)
  Future<List<ChatSession>> loadAllSessions() async {
    final sessions = <ChatSession>[];
    
    for (final key in _sessionsBox.keys) {
      if (key == _currentSessionKey) continue;
      
      final json = _sessionsBox.get(key);
      if (json != null) {
        try {
          final map = jsonDecode(json) as Map<String, dynamic>;
          sessions.add(ChatSession.fromJson(map));
        } catch (e) {
          // Skip invalid sessions
        }
      }
    }
    
    // Sort by last updated (newest first)
    sessions.sort((a, b) => b.lastUpdatedAt.compareTo(a.lastUpdatedAt));
    return sessions;
  }
  
  /// Update current session with new message
  Future<void> addMessageToCurrentSession(ChatMessage message) async {
    final session = await getCurrentSession();
    final updatedMessages = [...session.messages, message];
    
    // Auto-generate title from first user message
    String title = session.title;
    if (title == 'New Conversation' && message.isUser) {
      title = message.content.length > 40
          ? '${message.content.substring(0, 40)}...'
          : message.content;
    }
    
    final updatedSession = session.copyWith(
      messages: updatedMessages,
      title: title,
      lastUpdatedAt: DateTime.now(),
    );
    
    await saveSession(updatedSession);
  }
  
  /// Search all sessions for messages matching a query
  Future<List<SearchResult>> searchMessages(String query) async {
    final results = <SearchResult>[];
    final queryLower = query.toLowerCase();
    final sessions = await loadAllSessions();
    
    // Include current session
    final current = await getCurrentSession();
    sessions.insert(0, current);
    
    for (final session in sessions) {
      for (final message in session.messages) {
        if (message.content.toLowerCase().contains(queryLower)) {
          results.add(SearchResult(
            message: message,
            session: session,
            matchedText: _extractMatchContext(message.content, queryLower),
          ));
        }
      }
    }
    
    // Sort by timestamp (newest first)
    results.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return results;
  }
  
  /// Get frequency analysis for a search term
  Future<SearchAnalysis> analyzeSearchTerm(String query) async {
    final results = await searchMessages(query);
    final userMentions = results.where((r) => r.message.isUser).toList();
    
    // Group by date
    final Map<String, int> byDate = {};
    for (final result in userMentions) {
      final dateKey = _formatDate(result.message.timestamp);
      byDate[dateKey] = (byDate[dateKey] ?? 0) + 1;
    }
    
    return SearchAnalysis(
      query: query,
      totalMentions: userMentions.length,
      firstMention: userMentions.isNotEmpty ? userMentions.last.message.timestamp : null,
      lastMention: userMentions.isNotEmpty ? userMentions.first.message.timestamp : null,
      mentionsByDate: byDate,
      results: results,
    );
  }
  
  /// Toggle bookmark on a message
  Future<void> toggleBookmark(String messageId, String sessionId, {String? note}) async {
    final key = '$sessionId:$messageId';
    
    if (_bookmarksBox.containsKey(key)) {
      await _bookmarksBox.delete(key);
    } else {
      final bookmark = BookmarkedMessage(
        messageId: messageId,
        sessionId: sessionId,
        note: note,
        createdAt: DateTime.now(),
      );
      await _bookmarksBox.put(key, jsonEncode(bookmark.toJson()));
    }
  }
  
  /// Check if a message is bookmarked
  bool isBookmarked(String messageId, String sessionId) {
    return _bookmarksBox.containsKey('$sessionId:$messageId');
  }
  
  /// Get all bookmarked messages
  Future<List<BookmarkedMessage>> getBookmarks() async {
    final bookmarks = <BookmarkedMessage>[];
    
    for (final json in _bookmarksBox.values) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        bookmarks.add(BookmarkedMessage.fromJson(map));
      } catch (e) {
        // Skip invalid bookmarks
      }
    }
    
    // Sort by creation date (newest first)
    bookmarks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return bookmarks;
  }
  
  /// Switch to a different session
  Future<ChatSession> switchToSession(String sessionId) async {
    final session = await loadSession(sessionId);
    if (session == null) {
      throw Exception('Session not found');
    }
    
    await _sessionsBox.put(_currentSessionKey, sessionId);
    return session;
  }
  
  /// Start a new conversation
  Future<ChatSession> startNewConversation() async {
    return await createSession();
  }
  
  /// Delete a session
  Future<void> deleteSession(String sessionId) async {
    await _sessionsBox.delete(sessionId);
    
    // If deleting current session, create a new one
    final currentId = _sessionsBox.get(_currentSessionKey);
    if (currentId == sessionId) {
      await createSession();
    }
  }
  
  /// Helper: Extract context around matched text
  String _extractMatchContext(String content, String query) {
    final index = content.toLowerCase().indexOf(query);
    if (index == -1) return content;
    
    final start = (index - 30).clamp(0, content.length);
    final end = (index + query.length + 30).clamp(0, content.length);
    
    String result = content.substring(start, end);
    if (start > 0) result = '...$result';
    if (end < content.length) result = '$result...';
    
    return result;
  }
  
  /// Helper: Format date for grouping
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);
    
    if (messageDate == today) return 'Today';
    if (messageDate == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// A chat session containing multiple messages
class ChatSession {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  
  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.lastUpdatedAt,
  });
  
  ChatSession copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
  };
  
  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: (json['messages'] as List)
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUpdatedAt: DateTime.parse(json['lastUpdatedAt'] as String),
    );
  }
  
  /// Get preview text for history drawer
  String get preview {
    if (messages.isEmpty) return 'No messages';
    final lastMsg = messages.last;
    final content = lastMsg.content;
    return content.length > 60 ? '${content.substring(0, 60)}...' : content;
  }
  
  /// Get bookmarked message count
  int get messageCount => messages.length;
}

/// A bookmarked message reference
class BookmarkedMessage {
  final String messageId;
  final String sessionId;
  final String? note;
  final DateTime createdAt;
  
  BookmarkedMessage({
    required this.messageId,
    required this.sessionId,
    this.note,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'sessionId': sessionId,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory BookmarkedMessage.fromJson(Map<String, dynamic> json) {
    return BookmarkedMessage(
      messageId: json['messageId'] as String,
      sessionId: json['sessionId'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Search result with context
class SearchResult {
  final ChatMessage message;
  final ChatSession session;
  final String matchedText;
  
  SearchResult({
    required this.message,
    required this.session,
    required this.matchedText,
  });
}

/// Analysis of search results
class SearchAnalysis {
  final String query;
  final int totalMentions;
  final DateTime? firstMention;
  final DateTime? lastMention;
  final Map<String, int> mentionsByDate;
  final List<SearchResult> results;
  
  SearchAnalysis({
    required this.query,
    required this.totalMentions,
    this.firstMention,
    this.lastMention,
    required this.mentionsByDate,
    required this.results,
  });
  
  /// Get formatted summary
  String get summary {
    if (totalMentions == 0) return 'No mentions found';
    
    final timeRange = firstMention != null && lastMention != null
        ? 'from ${_formatDate(firstMention!)} to ${_formatDate(lastMention!)}'
        : '';
    
    return 'Found $totalMentions mention${totalMentions == 1 ? '' : 's'} $timeRange';
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
