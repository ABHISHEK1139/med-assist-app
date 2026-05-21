import 'package:flutter/material.dart';
import '../services/document_service.dart';
import '../services/pc_backend_service.dart';

/// Documents Screen
/// 
/// Upload and manage medical documents (lab reports, prescriptions, etc.)
/// Documents are processed by PC backend and stored in vector database
/// for context-aware AI responses.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final DocumentService _documentService = DocumentService();
  final PCBackendService _pcService = PCBackendService();
  
  List<StoredDocument> _documents = [];
  bool _isLoading = false;
  bool _isUploading = false;
  String? _error;
  String? _selectedDocType;
  
  final List<String> _docTypes = [
    'lab_report',
    'prescription',
    'radiology',
    'notes',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  Future<void> _initialize() async {
    if (_pcService.isConnected) {
      _documentService.initialize(_pcService.serverUrl);
      await _loadDocuments();
    }
  }
  
  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    try {
      final docs = await _documentService.getDocuments();
      setState(() {
        _documents = docs;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _uploadDocument() async {
    if (!_pcService.isConnected) {
      _showSnackBar('Not connected to PC. Connect first in settings.', isError: true);
      return;
    }
    
    setState(() => _isUploading = true);
    
    final result = await _documentService.pickAndUpload(
      docType: _selectedDocType,
    );
    
    setState(() => _isUploading = false);
    
    if (result.cancelled) return;
    
    if (result.success) {
      _showSnackBar(
        '✅ ${result.docType}: ${result.message}',
        isError: false,
      );
      await _loadDocuments();
    } else {
      _showSnackBar(
        '❌ ${result.error}',
        isError: true,
      );
    }
  }
  
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _pcService.isConnected;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical Documents'),
        actions: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDocuments,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection status
          Container(
            padding: const EdgeInsets.all(12),
            color: isConnected ? Colors.green.shade50 : Colors.orange.shade50,
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.computer : Icons.warning_amber,
                  color: isConnected ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isConnected 
                      ? 'Connected to PC • Documents stored in AI memory'
                      : 'Not connected to PC • Connect to upload documents',
                    style: TextStyle(
                      color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Doc type filter
          if (isConnected)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('Type: '),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(null, 'All'),
                          ..._docTypes.map((t) => _buildFilterChip(t, _docTypeLabel(t))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Documents list
          Expanded(
            child: _buildDocumentsList(),
          ),
        ],
      ),
      floatingActionButton: isConnected
        ? FloatingActionButton.extended(
            onPressed: _isUploading ? null : _uploadDocument,
            icon: _isUploading 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.upload_file),
            label: Text(_isUploading ? 'Uploading...' : 'Upload Document'),
          )
        : null,
    );
  }
  
  Widget _buildFilterChip(String? docType, String label) {
    final isSelected = _selectedDocType == docType;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedDocType = selected ? docType : null);
        },
      ),
    );
  }
  
  Widget _buildDocumentsList() {
    if (!_pcService.isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Connect to PC to manage documents',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/pc-connect'),
              icon: const Icon(Icons.computer),
              label: const Text('Connect to PC'),
            ),
          ],
        ),
      );
    }
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadDocuments,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    if (_documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No documents yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload lab reports, prescriptions, or medical notes',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            _buildSupportedFormats(),
          ],
        ),
      );
    }
    
    // Filter documents by type
    final filtered = _selectedDocType == null
      ? _documents
      : _documents.where((d) => d.docType == _selectedDocType).toList();
    
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        return _buildDocumentCard(doc);
      },
    );
  }
  
  Widget _buildDocumentCard(StoredDocument doc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _docTypeColor(doc.docType).withOpacity(0.2),
          child: Text(doc.icon, style: const TextStyle(fontSize: 24)),
        ),
        title: Text(
          doc.source,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doc.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _docTypeColor(doc.docType).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _docTypeLabel(doc.docType),
                    style: TextStyle(
                      fontSize: 12,
                      color: _docTypeColor(doc.docType),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(doc.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility),
                  SizedBox(width: 8),
                  Text('View'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'view') {
              _showDocumentDetails(doc);
            } else if (value == 'delete') {
              _confirmDelete(doc);
            }
          },
        ),
      ),
    );
  }
  
  Widget _buildSupportedFormats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'Supported Formats',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildFormatChip('PDF', Icons.picture_as_pdf),
              _buildFormatChip('JPG', Icons.image),
              _buildFormatChip('PNG', Icons.image),
              _buildFormatChip('TXT', Icons.text_snippet),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildFormatChip(String format, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.blue),
          const SizedBox(width: 4),
          Text(format, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
  
  void _showDocumentDetails(StoredDocument doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: _docTypeColor(doc.docType).withOpacity(0.2),
                    child: Text(doc.icon, style: const TextStyle(fontSize: 32)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.source,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _docTypeLabel(doc.docType),
                          style: TextStyle(color: _docTypeColor(doc.docType)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _detailRow('Uploaded', _formatDate(doc.timestamp)),
              _detailRow('Document ID', doc.docId.substring(0, 8)),
              if (doc.tags.isNotEmpty)
                _detailRow('Tags', doc.tags.join(', ')),
              const SizedBox(height: 16),
              const Text(
                'Summary',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(doc.summary),
              ),
              const SizedBox(height: 20),
              const Text(
                '💡 This document is stored in AI memory and will be used to provide context-aware responses.',
                style: TextStyle(
                  color: Colors.blue,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
  
  void _confirmDelete(StoredDocument doc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document?'),
        content: Text('Are you sure you want to delete "${doc.source}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnackBar('Delete not implemented yet', isError: true);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  String _docTypeLabel(String docType) {
    switch (docType) {
      case 'lab_report': return 'Lab Report';
      case 'prescription': return 'Prescription';
      case 'radiology': return 'Radiology';
      case 'notes': return 'Medical Notes';
      default: return 'Document';
    }
  }
  
  Color _docTypeColor(String docType) {
    switch (docType) {
      case 'lab_report': return Colors.purple;
      case 'prescription': return Colors.blue;
      case 'radiology': return Colors.orange;
      case 'notes': return Colors.green;
      default: return Colors.grey;
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
