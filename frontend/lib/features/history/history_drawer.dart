import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/chat_history_service.dart';
import '../chat/bloc/chat_bloc.dart';
import '../profile/presentation/profile_page.dart';

/// History Drawer - Shows past chat sessions with search
class HistoryDrawer extends StatefulWidget {
  final ChatHistoryService historyService;
  final Function(ChatSession) onSessionSelected;
  final VoidCallback onNewChat;
  final String? currentSessionId;
  
  const HistoryDrawer({
    super.key,
    required this.historyService,
    required this.onSessionSelected,
    required this.onNewChat,
    this.currentSessionId,
  });

  @override
  State<HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends State<HistoryDrawer> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatSession> _sessions = [];
  SearchAnalysis? _searchAnalysis;
  bool _isLoading = true;
  bool _isSearching = false;
  
  @override
  void initState() {
    super.initState();
    _loadSessions();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await widget.historyService.loadAllSessions();
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchAnalysis = null;
        _isSearching = false;
      });
      return;
    }
    
    setState(() => _isSearching = true);
    
    try {
      final analysis = await widget.historyService.analyzeSearchTerm(query);
      setState(() {
        _searchAnalysis = analysis;
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.darkBg,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Medical Archive Entry
            _buildArchiveButton(context),
            
            // Search bar
            _buildSearchBar(),
            
            // Content (sessions or search results)
            Expanded(
              child: _searchAnalysis != null
                  ? _buildSearchResults()
                  : _buildSessionsList(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.darkBorder),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.history,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Chat History',
              style: TextStyle(
                color: AppTheme.textPrimaryDark,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // New Chat button
          IconButton(
            onPressed: () {
              widget.onNewChat();
              Navigator.pop(context);
            },
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.add,
                color: AppTheme.primary,
                size: 18,
              ),
            ),
            tooltip: 'New Chat',
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: InkWell(
        onTap: () {
          Navigator.pop(context); // Close drawer
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfilePage()),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withOpacity(0.2),
                AppTheme.accent.withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.darkBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.medical_information,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Health Archive',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Digital medical profile',
                      style: TextStyle(
                        color: AppTheme.textSecondaryDark,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1, end: 0);
  }
  
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchController,
        onChanged: _performSearch,
        decoration: InputDecoration(
          hintText: 'Search your history...',
          hintStyle: TextStyle(color: AppTheme.textSecondaryDark),
          prefixIcon: Icon(
            _isSearching ? Icons.hourglass_empty : Icons.search,
            color: AppTheme.textSecondaryDark,
            size: 20,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchAnalysis = null);
                  },
                  icon: const Icon(Icons.close, size: 18),
                )
              : null,
          filled: true,
          fillColor: AppTheme.darkCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: const TextStyle(color: AppTheme.textPrimaryDark),
      ),
    );
  }
  
  Widget _buildSessionsList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    
    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppTheme.textSecondaryDark.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No conversations yet',
              style: TextStyle(
                color: AppTheme.textSecondaryDark,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final isCurrentSession = session.id == widget.currentSessionId;
        
        return _SessionTile(
          session: session,
          isCurrentSession: isCurrentSession,
          onTap: () {
            widget.onSessionSelected(session);
            Navigator.pop(context);
          },
          onDelete: () async {
            await widget.historyService.deleteSession(session.id);
            _loadSessions();
          },
        ).animate().fadeIn(delay: (index * 50).ms);
      },
    );
  }
  
  Widget _buildSearchResults() {
    final analysis = _searchAnalysis!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.accent.withOpacity(0.1),
                AppTheme.primary.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: AppTheme.accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Search Analysis',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                analysis.summary,
                style: const TextStyle(
                  color: AppTheme.textPrimaryDark,
                  fontSize: 14,
                ),
              ),
              if (analysis.mentionsByDate.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: analysis.mentionsByDate.entries.map((e) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${e.key}: ${e.value}x',
                        style: TextStyle(
                          color: AppTheme.textSecondaryDark,
                          fontSize: 11,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ).animate().fadeIn().slideY(begin: -0.1, end: 0),
        
        const SizedBox(height: 12),
        
        // Results list
        Expanded(
          child: analysis.results.isEmpty
              ? Center(
                  child: Text(
                    'No matches found',
                    style: TextStyle(color: AppTheme.textSecondaryDark),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: analysis.results.length,
                  itemBuilder: (context, index) {
                    final result = analysis.results[index];
                    return _SearchResultTile(
                      result: result,
                      searchQuery: analysis.query,
                      onTap: () {
                        widget.onSessionSelected(result.session);
                        Navigator.pop(context);
                      },
                    ).animate().fadeIn(delay: (index * 30).ms);
                  },
                ),
        ),
      ],
    );
  }
}

/// Session tile widget
class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isCurrentSession;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  
  const _SessionTile({
    required this.session,
    required this.isCurrentSession,
    required this.onTap,
    required this.onDelete,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrentSession
            ? AppTheme.primary.withOpacity(0.1)
            : AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentSession ? AppTheme.primary : AppTheme.darkBorder,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: TextStyle(
                          color: isCurrentSession
                              ? AppTheme.primary
                              : AppTheme.textPrimaryDark,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.preview,
                        style: TextStyle(
                          color: AppTheme.textSecondaryDark,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: AppTheme.textSecondaryDark.withOpacity(0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(session.lastUpdatedAt),
                            style: TextStyle(
                              color: AppTheme.textSecondaryDark.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${session.messageCount} msgs',
                            style: TextStyle(
                              color: AppTheme.textSecondaryDark.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: AppTheme.textSecondaryDark,
                    size: 18,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: AppTheme.error, size: 18),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: AppTheme.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);
    
    if (messageDate == today) return 'Today';
    if (messageDate == today.subtract(const Duration(days: 1))) return 'Yesterday';
    
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }
}

/// Search result tile
class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final String searchQuery;
  final VoidCallback onTap;
  
  const _SearchResultTile({
    required this.result,
    required this.searchQuery,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      result.message.isUser ? Icons.person : Icons.smart_toy,
                      size: 14,
                      color: result.message.isUser 
                          ? AppTheme.primary 
                          : AppTheme.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      result.message.isUser ? 'You' : 'Med Assist App',
                      style: TextStyle(
                        color: result.message.isUser 
                            ? AppTheme.primary 
                            : AppTheme.accent,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      result.message.formattedTime,
                      style: TextStyle(
                        color: AppTheme.textSecondaryDark.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildHighlightedText(result.matchedText, searchQuery),
                const SizedBox(height: 6),
                Text(
                  'In: ${result.session.title}',
                  style: TextStyle(
                    color: AppTheme.textSecondaryDark,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHighlightedText(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final startIndex = lowerText.indexOf(lowerQuery);
    
    if (startIndex == -1) {
      return Text(
        text,
        style: const TextStyle(color: AppTheme.textPrimaryDark, fontSize: 13),
      );
    }
    
    final endIndex = startIndex + query.length;
    
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: AppTheme.textPrimaryDark, fontSize: 13),
        children: [
          TextSpan(text: text.substring(0, startIndex)),
          TextSpan(
            text: text.substring(startIndex, endIndex),
            style: const TextStyle(
              backgroundColor: Color(0x4400FF00),
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: text.substring(endIndex)),
        ],
      ),
    );
  }
}
