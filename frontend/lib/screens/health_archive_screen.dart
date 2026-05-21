import 'package:flutter/material.dart';
import '../services/health_archive/health_archive.dart';

/// Health Archive Screen
/// 
/// Displays user's extracted medical history
class HealthArchiveScreen extends StatefulWidget {
  const HealthArchiveScreen({super.key});
  
  @override
  State<HealthArchiveScreen> createState() => _HealthArchiveScreenState();
}

class _HealthArchiveScreenState extends State<HealthArchiveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final _archiveService = HealthArchiveService();
  HealthProfile? _profile;
  bool _isLoading = true;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadProfile();
  }
  
  Future<void> _loadProfile() async {
    try {
      await _archiveService.initialize();
      final profile = await _archiveService.getFullProfile();
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
      appBar: AppBar(
        title: const Text('My Health Archive'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.medical_services), text: 'Conditions'),
            Tab(icon: Icon(Icons.medication), text: 'Medications'),
            Tab(icon: Icon(Icons.warning), text: 'Allergies'),
            Tab(icon: Icon(Icons.local_hospital), text: 'Surgeries'),
            Tab(icon: Icon(Icons.family_restroom), text: 'Family'),
            Tab(icon: Icon(Icons.monitor_heart), text: 'Vitals'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _profile == null
                  ? const Center(child: Text('No data'))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildConditionsTab(),
                        _buildMedicationsTab(),
                        _buildAllergiesTab(),
                        _buildSurgeriesTab(),
                        _buildFamilyTab(),
                        _buildVitalsTab(),
                      ],
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadProfile,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.refresh),
      ),
    );
  }
  
  Widget _buildConditionsTab() {
    final conditions = _profile!.conditions;
    
    if (conditions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.medical_services,
        message: 'No conditions recorded',
        hint: 'Tell me about your health conditions during our chat',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: conditions.length,
      itemBuilder: (context, index) {
        final c = conditions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(c.status),
              child: const Icon(Icons.favorite, color: Colors.white),
            ),
            title: Text(
              c.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.onsetYear != null)
                  Text('Since ${c.onsetYear}'),
                Row(
                  children: [
                    _buildChip(c.status.name, _getStatusColor(c.status)),
                    Builder(
                      builder: (context) {
                        final sev = c.severity;
                        if (sev != null && sev != Severity.unknown) {
                          return _buildChip(sev.name, _getSeverityColor(sev));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete('condition', c.id!),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildMedicationsTab() {
    final meds = _profile!.medications;
    
    if (meds.isEmpty) {
      return _buildEmptyState(
        icon: Icons.medication,
        message: 'No medications recorded',
        hint: 'Mention your medications during our chat',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: meds.length,
      itemBuilder: (context, index) {
        final m = meds[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: m.status == MedicationStatus.current
                  ? Colors.green
                  : Colors.grey,
              child: const Icon(Icons.medication, color: Colors.white),
            ),
            title: Text(
              m.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.dosage != null)
                  Text('${m.dosage}${m.dosageUnit ?? ''} - ${m.frequency ?? ''}'),
                if (m.timing != null)
                  Text('⏰ ${m.timing}'),
                if (m.prescribedFor != null)
                  Text('For: ${m.prescribedFor}'),
                _buildChip(m.status.name, 
                  m.status == MedicationStatus.current ? Colors.green : Colors.grey),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete('medication', m.id!),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildAllergiesTab() {
    final allergies = _profile!.allergies;
    
    if (allergies.isEmpty) {
      return _buildEmptyState(
        icon: Icons.warning_amber,
        message: 'No allergies recorded',
        hint: 'Important! Tell me about any allergies',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allergies.length,
      itemBuilder: (context, index) {
        final a = allergies[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: Colors.red.shade50,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.red,
              child: Icon(Icons.warning, color: Colors.white),
            ),
            title: Text(
              a.allergen,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type: ${a.type?.name ?? 'unknown'}'),
                if (a.reaction != null)
                  Text('Reaction: ${a.reaction}'),
                Builder(
                  builder: (context) {
                    final sev = a.severity;
                    if (sev != null && sev != Severity.unknown) {
                      return _buildChip(sev.name, _getSeverityColor(sev));
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete('allergy', a.id!),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildSurgeriesTab() {
    final surgeries = _profile!.surgeries;
    
    if (surgeries.isEmpty) {
      return _buildEmptyState(
        icon: Icons.local_hospital,
        message: 'No surgeries recorded',
        hint: 'Tell me about any past surgeries',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: surgeries.length,
      itemBuilder: (context, index) {
        final s = surgeries[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.purple,
              child: Icon(Icons.cut, color: Colors.white),
            ),
            title: Text(
              s.procedureName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s.year != null)
                  Text('Year: ${s.year}'),
                if (s.outcome != null)
                  Text('Outcome: ${s.outcome}'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete('surgery', s.id!),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildFamilyTab() {
    final family = _profile!.familyHistory;
    
    if (family.isEmpty) {
      return _buildEmptyState(
        icon: Icons.family_restroom,
        message: 'No family history recorded',
        hint: 'Share your family medical history',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: family.length,
      itemBuilder: (context, index) {
        final f = family[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.indigo,
              child: Icon(Icons.people, color: Colors.white),
            ),
            title: Text(
              f.condition,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Relation: ${f.relation.name}'),
                if (f.ageAtDiagnosis != null)
                  Text('Age at diagnosis: ${f.ageAtDiagnosis}'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete('family', f.id!),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildVitalsTab() {
    final vitals = _profile!.vitals;
    
    if (vitals.isEmpty) {
      return _buildEmptyState(
        icon: Icons.monitor_heart,
        message: 'No vitals recorded',
        hint: 'Share your BP, heart rate, weight, etc.',
      );
    }
    
    // Group by type
    final grouped = <VitalType, List<VitalSign>>{};
    for (final v in vitals) {
      grouped.putIfAbsent(v.type, () => []).add(v);
    }
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries.map((entry) {
        final type = entry.key;
        final values = entry.value..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange,
              child: Icon(_getVitalIcon(type), color: Colors.white),
            ),
            title: Text(
              type.name.replaceAll(RegExp('([A-Z])'), ' \$1').trim(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Latest: ${values.first.value}${values.first.unit ?? ''}',
            ),
            children: values.take(5).map((v) => ListTile(
              dense: true,
              title: Text('${v.value}${v.unit ?? ''}'),
              subtitle: Text(_formatDate(v.recordedAt)),
            )).toList(),
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String hint,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: TextStyle(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildChip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
  
  Color _getStatusColor(ConditionStatus status) {
    switch (status) {
      case ConditionStatus.active: return Colors.red;
      case ConditionStatus.resolved: return Colors.green;
      case ConditionStatus.managed: return Colors.orange;
      case ConditionStatus.unknown: return Colors.grey;
    }
  }
  
  Color _getSeverityColor(Severity severity) {
    switch (severity) {
      case Severity.mild: return Colors.yellow.shade700;
      case Severity.moderate: return Colors.orange;
      case Severity.severe: return Colors.deepOrange;
      case Severity.critical: return Colors.red;
      case Severity.unknown: return Colors.grey;
    }
  }
  
  IconData _getVitalIcon(VitalType type) {
    switch (type) {
      case VitalType.bloodPressureSystolic:
      case VitalType.bloodPressureDiastolic:
        return Icons.bloodtype;
      case VitalType.heartRate:
        return Icons.favorite;
      case VitalType.temperature:
        return Icons.thermostat;
      case VitalType.weight:
        return Icons.monitor_weight;
      case VitalType.height:
        return Icons.height;
      case VitalType.bmi:
        return Icons.calculate;
      case VitalType.bloodSugar:
        return Icons.water_drop;
      case VitalType.oxygenSaturation:
        return Icons.air;
      case VitalType.respiratoryRate:
        return Icons.air;
      case VitalType.other:
        return Icons.query_stats;
    }
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
  
  void _confirmDelete(String type, int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteEntry(type, id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _deleteEntry(String type, int id) async {
    try {
      await _archiveService.deleteEntry(type, id);
      _loadProfile(); // Refresh
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
