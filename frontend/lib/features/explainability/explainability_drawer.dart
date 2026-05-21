import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/ai_service.dart';

/// Explainability Drawer
/// 
/// Transparency panel showing which documents influenced the AI's response.
/// Displays:
/// - Referenced documents with timestamps
/// - Relevance scores
/// - "This response used: Lab Report from Jan 15" citations
class ExplainabilityDrawer extends StatelessWidget {
  final List<ReferencedDocument> documents;
  final VoidCallback onClose;
  
  const ExplainabilityDrawer({
    super.key,
    required this.documents,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle and header
          _buildHeader(context),
          
          // Document list
          if (documents.isEmpty)
            _buildEmptyState(context)
          else
            _buildDocumentList(context),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.darkBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How I Reached This Conclusion',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${documents.length} documents referenced',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                color: AppTheme.textSecondaryDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 48,
            color: AppTheme.textSecondaryDark,
          ),
          const SizedBox(height: 16),
          Text(
            'No Documents Referenced',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This response was based on general medical knowledge, '
            'not your stored health documents.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
  
  Widget _buildDocumentList(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: documents.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final doc = documents[index];
        return _DocumentCard(
          document: doc,
          index: index,
        ).animate().fadeIn(delay: (index * 100).ms).slideX(
          begin: 0.1,
          end: 0,
          delay: (index * 100).ms,
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final ReferencedDocument document;
  final int index;
  
  const _DocumentCard({
    required this.document,
    required this.index,
  });
  
  IconData _getIconForDocType(String docType) {
    switch (docType) {
      case 'lab_report':
        return Icons.science_outlined;
      case 'prescription':
        return Icons.medication_outlined;
      case 'radiology':
        return Icons.image_outlined;
      case 'notes':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
  
  String _getDocTypeLabel(String docType) {
    switch (docType) {
      case 'lab_report':
        return 'Lab Report';
      case 'prescription':
        return 'Prescription';
      case 'radiology':
        return 'X-Ray / Imaging';
      case 'notes':
        return 'Medical Notes';
      default:
        return 'Document';
    }
  }

  @override
  Widget build(BuildContext context) {
    final relevancePercent = (document.relevance * 100).toInt();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          // Doc type icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getIconForDocType(document.docType),
              color: AppTheme.primary,
              size: 22,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Document info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.source,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getDocTypeLabel(document.docType),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Relevance score
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$relevancePercent%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _getRelevanceColor(document.relevance),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'relevance',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondaryDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Color _getRelevanceColor(double relevance) {
    if (relevance >= 0.8) return AppTheme.success;
    if (relevance >= 0.5) return AppTheme.primary;
    if (relevance >= 0.3) return AppTheme.warning;
    return AppTheme.textSecondaryDark;
  }
}

/// Show the explainability drawer as a bottom sheet
void showExplainabilityDrawer(
  BuildContext context,
  List<ReferencedDocument> documents,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => ExplainabilityDrawer(
      documents: documents,
      onClose: () => Navigator.pop(context),
    ),
  );
}
