import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/health_archive/health_archive.dart';
import '../../../services/health_archive/health_context_builder.dart';

/// Digital Health Archive - LOCAL DATA
/// 
/// Shows health data stored on the PHONE (not from PC backend).
/// All data is extracted from your conversations and stored locally.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final _archiveService = HealthArchiveService();
  late HealthContextBuilder _contextBuilder;
  
  List<ActiveSymptom> _symptoms = [];
  List<Condition> _conditions = [];
  List<Medication> _medications = [];
  List<Allergy> _allergies = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    try {
      setState(() => _isLoading = true);
      
      // Initialize services
      await _archiveService.initialize();
      _contextBuilder = HealthContextBuilder(_archiveService);
      await _contextBuilder.initialize();
      
      // Load local data from phone's SQLite database
      final symptoms = await _contextBuilder.getActiveSymptoms();
      final conditions = await _archiveService.getConditions();
      final medications = await _archiveService.getMedications();
      final allergies = await _archiveService.getAllergies();
      
      setState(() {
        _symptoms = symptoms;
        _conditions = conditions;
        _medications = medications;
        _allergies = allergies;
        _isLoading = false;
      });
      
      print('📱 Loaded local health data:');
      print('   - ${symptoms.length} active symptoms');
      print('   - ${conditions.length} conditions');
      print('   - ${medications.length} medications');
      print('   - ${allergies.length} allergies');
      
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      print('❌ Failed to load health data: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Digital Health Archive'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLocalData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Timeline'),
            Tab(text: 'Medication'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildTimelineTab(),
                    _buildMedicationsTab(),
                  ],
                ),
    );
  }
  
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
          const SizedBox(height: 16),
          Text('Failed to load profile', style: TextStyle(color: AppTheme.textSecondaryDark)),
          const SizedBox(height: 8),
          Text(_error ?? '', style: const TextStyle(color: Colors.red, fontSize: 12)),
          const SizedBox(height: 16),
          TextButton(onPressed: _loadLocalData, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    // Combine symptoms and conditions for "Active Conditions"
    final activeIssues = <_HealthItem>[
      ..._symptoms.map((s) => _HealthItem(
        name: s.name,
        category: 'Symptom',
        status: 'Active',
        severity: s.severity.name,
        onsetDate: s.onsetDate,
        notes: s.notes,
      )),
      ..._conditions.where((c) => c.status == ConditionStatus.active).map((c) => _HealthItem(
        name: c.name,
        category: 'Condition',
        status: c.status.name,
        severity: c.severity?.name,
        onsetDate: c.onsetDate,
        notes: c.notes,
      )),
    ];
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Data source indicator
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.phone_android, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '📱 Data stored locally on your phone',
                  style: TextStyle(color: Colors.blue, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        
        _buildSectionHeader('ACTIVE CONDITIONS'),
        if (activeIssues.isEmpty) 
          _buildEmptyState('No active conditions recorded yet.\n\nTell me about your symptoms in chat!')
        else
          ...activeIssues.map((item) => _buildHealthCard(item, Icons.medical_services_outlined)),

        const SizedBox(height: 24),
        _buildSectionHeader('ALLERGIES & ALERTS'),
        if (_allergies.isEmpty) 
          _buildEmptyState('No allergies recorded.')
        else
          ..._allergies.map((a) => _buildHealthCard(
            _HealthItem(name: a.allergen, category: 'Allergy', status: 'Active', severity: a.severity?.name ?? 'Unknown'),
            Icons.warning_amber_rounded,
            color: AppTheme.error,
          )),
        
        const SizedBox(height: 24),
        _buildSectionHeader('LIFESTYLE'),
        _buildEmptyState('No lifestyle info recorded.'),
      ],
    ).animate().fadeIn();
  }
  
  Widget _buildTimelineTab() {
    // Combine all items with dates
    final timelineItems = <_TimelineItem>[];
    
    for (final s in _symptoms) {
      timelineItems.add(_TimelineItem(
        name: s.name,
        category: 'Symptom',
        date: s.onsetDate,
        status: 'Active',
        notes: s.notes,
        severity: s.severity.name,
      ));
    }
    
    for (final c in _conditions) {
      timelineItems.add(_TimelineItem(
        name: c.name,
        category: 'Condition',
        date: c.onsetDate ?? (c.onsetYear != null ? DateTime(c.onsetYear!) : null),
        status: c.status.name,
        notes: c.notes,
        severity: c.severity?.name,
      ));
    }
    
    for (final m in _medications) {
      if (m.startDate != null) {
        timelineItems.add(_TimelineItem(
          name: m.name,
          category: 'Medication',
          date: m.startDate,
          status: m.status.name,
          notes: '${m.dosage ?? ''} ${m.frequency ?? ''}'.trim(),
        ));
      }
    }
    
    // Sort by date (newest first)
    timelineItems.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return b.date!.compareTo(a.date!);
    });
    
    if (timelineItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'Your health timeline is empty',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chat with Med Assist App about your symptoms\nand conditions to build your timeline!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: timelineItems.length,
      itemBuilder: (context, index) {
        final item = timelineItems[index];
        final color = _getCategoryColor(item.category);
        
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline line
            Column(
              children: [
                Container(
                  width: 12, 
                  height: 12, 
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                if (index < timelineItems.length - 1)
                  Container(width: 2, height: 60, color: color.withOpacity(0.3)),
              ],
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.date != null 
                        ? '${item.date!.day}/${item.date!.month}/${item.date!.year}'
                        : 'Date unknown',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(item.category, style: TextStyle(color: color, fontSize: 10)),
                              ),
                              const SizedBox(width: 8),
                              if (item.severity != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getSeverityColor(item.severity!).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(item.severity!, style: TextStyle(color: _getSeverityColor(item.severity!), fontSize: 10)),
                                ),
                            ],
                          ),
                          if (item.notes != null && item.notes!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('"${item.notes}"', style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 12)),
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ).animate().fadeIn();
  }

  Widget _buildMedicationsTab() {
    final active = _medications.where((m) => m.status == MedicationStatus.current).toList();
    final past = _medications.where((m) => m.status != MedicationStatus.current).toList();
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('CURRENT MEDICATIONS'),
        if (active.isEmpty) 
          _buildEmptyState('No current medications recorded.')
        else
          ...active.map((m) => _buildMedicationCard(m)),

        const SizedBox(height: 24),
        _buildSectionHeader('PAST MEDICATIONS'),
        if (past.isEmpty) 
          _buildEmptyState('No past medications.')
        else
          ...past.map((m) => _buildMedicationCard(m, isPast: true)),
      ],
    ).animate().fadeIn();
  }
  
  Widget _buildMedicationCard(Medication med, {bool isPast = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (isPast ? Colors.grey : Colors.blue).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isPast ? Colors.grey : Colors.blue).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.medication, color: isPast ? Colors.grey : Colors.blue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  med.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                ),
                if (med.dosage != null || med.frequency != null)
                  Text(
                    '${med.dosage ?? ''} ${med.frequency ?? ''}'.trim(),
                    style: TextStyle(color: AppTheme.textSecondaryDark, fontSize: 12),
                  ),
                if (med.prescribedFor != null)
                  Text(
                    'For: ${med.prescribedFor}',
                    style: TextStyle(color: Colors.blue.shade200, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: AppTheme.textSecondaryDark, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildHealthCard(_HealthItem item, IconData icon, {Color? color}) {
    final themeColor = color ?? _getCategoryColor(item.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: themeColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(item.category, style: TextStyle(color: themeColor, fontSize: 10)),
                    ),
                    if (item.severity != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getSeverityColor(item.severity!).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(item.severity!, style: TextStyle(color: _getSeverityColor(item.severity!), fontSize: 10)),
                      ),
                    ],
                  ],
                ),
                if (item.onsetDate != null)
                  Text(
                    'Since ${item.onsetDate!.day}/${item.onsetDate!.month}/${item.onsetDate!.year}',
                    style: TextStyle(color: AppTheme.textSecondaryDark, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (item.status == 'Active' || item.status == 'active')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Active', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
  
  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'symptom': return Colors.orange;
      case 'condition': return AppTheme.primary;
      case 'medication': return Colors.blue;
      case 'allergy': return Colors.red;
      default: return Colors.grey;
    }
  }
  
  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'mild': return Colors.green;
      case 'moderate': return Colors.orange;
      case 'severe': return Colors.red;
      case 'critical': return Colors.purple;
      default: return Colors.grey;
    }
  }
}

/// Helper class for health items
class _HealthItem {
  final String name;
  final String category;
  final String status;
  final String? severity;
  final DateTime? onsetDate;
  final String? notes;
  
  _HealthItem({
    required this.name,
    required this.category,
    required this.status,
    this.severity,
    this.onsetDate,
    this.notes,
  });
}

/// Helper class for timeline
class _TimelineItem {
  final String name;
  final String category;
  final DateTime? date;
  final String status;
  final String? notes;
  final String? severity;
  
  _TimelineItem({
    required this.name,
    required this.category,
    this.date,
    required this.status,
    this.notes,
    this.severity,
  });
}
