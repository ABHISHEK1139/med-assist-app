import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/med_assist_service.dart';
import '../services/pc_discovery_service.dart';
import '../core/theme/app_theme.dart';

/// PC Connection Screen
/// 
/// Connects phone to PC running the AI backend.
/// Features:
/// - Auto-discovery: Scans network to find PC automatically
/// - Remembers last IP: Auto-connects on next launch
/// - Manual entry: Fallback if auto-discovery fails
class PCConnectionScreen extends StatefulWidget {
  final VoidCallback onConnected;
  final VoidCallback? onSkip;
  
  const PCConnectionScreen({
    super.key,
    required this.onConnected,
    this.onSkip,
  });
  
  @override
  State<PCConnectionScreen> createState() => _PCConnectionScreenState();
}

class _PCConnectionScreenState extends State<PCConnectionScreen>
    with TickerProviderStateMixin {
  final MedAssistAppService _MedAssistAppService = MedAssistAppService();
  final PCDiscoveryService _discoveryService = PCDiscoveryService();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8000');
  
  late AnimationController _pulseController;
  StreamSubscription? _discoverySubscription;
  
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isScanning = false;
  double _scanProgress = 0;
  String _statusMessage = 'Searching for your PC...';
  String? _errorMessage;
  String? _savedIP;
  List<DiscoveredServer> _discoveredServers = [];
  
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _initializeService();
    _startAutoDiscovery();
  }
  
  Future<void> _startAutoDiscovery() async {
    // Load saved IP first
    final prefs = await SharedPreferences.getInstance();
    final savedIP = prefs.getString('pc_ip_address');
    
    setState(() {
      _savedIP = savedIP;
      if (savedIP != null) _ipController.text = savedIP;
      _isScanning = true;
    });
    
    // Listen to discovery progress
    _discoverySubscription = _discoveryService.progressStream.listen((progress) {
      setState(() {
        _statusMessage = progress.status;
        _scanProgress = progress.progress;
      });
    });
    
    // Start discovery
    final servers = await _discoveryService.discoverServers(
      lastKnownIP: savedIP,
    );
    
    setState(() {
      _isScanning = false;
      _discoveredServers = servers;
    });
    
    // Auto-connect if found one server
    if (servers.length == 1) {
      _connectToServer(servers.first);
    } else if (servers.isEmpty) {
      setState(() {
        _statusMessage = 'No PC found. Enter IP manually or tap Scan.';
      });
    } else {
      setState(() {
        _statusMessage = 'Found ${servers.length} PCs. Select one:';
      });
    }
  }
  
  Future<void> _connectToServer(DiscoveredServer server) async {
    _ipController.text = server.ip;
    _portController.text = server.port.toString();
    await _connectToPC();
  }
  
  Future<void> _loadSavedIP() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIP = prefs.getString('pc_ip_address');
    if (savedIP != null && savedIP.isNotEmpty) {
      setState(() {
        _savedIP = savedIP;
        _ipController.text = savedIP;
      });
    }
  }
  
  Future<void> _saveIP(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pc_ip_address', ip);
  }
  
  Future<void> _initializeService() async {
    await _MedAssistAppService.initialize();
  }
  
  Future<void> _connectToPC() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8000;
    
    if (ip.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your PC\'s IP address';
      });
      return;
    }
    
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _statusMessage = 'Connecting to $ip:$port...';
    });
    
    try {
      final connected = await _MedAssistAppService.connectToPC(ip, port: port);
      
      if (connected) {
        await _saveIP(ip);
        setState(() {
          _isConnecting = false;
          _isConnected = true;
          _statusMessage = '✅ Connected to PC!';
        });
        
        // Wait a moment then proceed
        await Future.delayed(const Duration(milliseconds: 800));
        widget.onConnected();
      } else {
        setState(() {
          _isConnecting = false;
          _errorMessage = _MedAssistAppService.error ?? 'Failed to connect';
          _statusMessage = 'Connection failed';
        });
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = e.toString();
        _statusMessage = 'Connection error';
      });
    }
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _discoverySubscription?.cancel();
    _discoveryService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              
              // Icon
              _buildIcon(),
              
              const SizedBox(height: 32),
              
              // Title
              Text(
                'Connect to PC',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
                ),
              ).animate().fadeIn(duration: 500.ms),
              
              const SizedBox(height: 12),
              
              // Subtitle
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
              
              const SizedBox(height: 32),
              
              // Scanning progress
              if (_isScanning) _buildScanningIndicator(),
              
              // Discovered servers list
              if (_discoveredServers.isNotEmpty && !_isConnected) 
                _buildDiscoveredServersList(),
              
              // Connection form
              if (!_isConnected && !_isScanning) _buildConnectionForm(),
              
              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Help text
              _buildHelpCard(),
              
              const Spacer(),
              
              // Skip button
              if (widget.onSkip != null && !_isConnecting)
                TextButton(
                  onPressed: widget.onSkip,
                  child: const Text('Skip for now'),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildScanningIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: _scanProgress > 0 ? _scanProgress : null,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Scanning network...',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _scanProgress > 0 ? _scanProgress : null,
              backgroundColor: isDark ? AppTheme.darkBorder : Colors.grey.shade300,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
  
  Widget _buildDiscoveredServersList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '🖥️ Found ${_discoveredServers.length} PC(s):',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
              ),
            ),
          ),
          ..._discoveredServers.map((server) => _buildServerCard(server)),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _isScanning ? null : _startAutoDiscovery,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Scan again'),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
  
  Widget _buildServerCard(DiscoveredServer server) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: server.modelReady 
              ? AppTheme.primary.withOpacity(0.5)
              : isDark ? AppTheme.darkBorder : Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        onTap: () => _connectToServer(server),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: server.gpuEnabled 
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  server.gpuEnabled ? Icons.memory : Icons.computer,
                  color: server.gpuEnabled ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.ip,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      server.gpuEnabled 
                          ? '🚀 GPU: ${server.gpuName}'
                          : '💻 CPU Mode',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: server.modelReady 
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  server.modelReady ? 'Ready' : 'Loading...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: server.modelReady ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildIcon() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                _isConnected 
                    ? Colors.green.withOpacity(0.3)
                    : _isScanning
                        ? Colors.blue.withOpacity(0.3)
                        : AppTheme.primary.withOpacity(0.3),
                _isConnected
                    ? Colors.green.withOpacity(0.1)
                    : _isScanning
                        ? Colors.blue.withOpacity(0.1)
                        : AppTheme.primary.withOpacity(0.1),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: (_isConnected ? Colors.green : _isScanning ? Colors.blue : AppTheme.primary)
                    .withOpacity(0.3 * _pulseController.value),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Icon(
            _isConnected 
                ? Icons.check_circle
                : _isScanning
                    ? Icons.radar
                    : _isConnecting 
                        ? Icons.sync 
                        : Icons.computer,
            size: 60,
            color: _isConnected ? Colors.green : _isScanning ? Colors.blue : AppTheme.primary,
          ),
        );
      },
    ).animate().scale(duration: 500.ms, curve: Curves.easeOut);
  }
  
  Widget _buildConnectionForm() {
    return Column(
      children: [
        // IP Address field
        TextField(
          controller: _ipController,
          keyboardType: TextInputType.number,
          enabled: !_isConnecting,
          decoration: InputDecoration(
            labelText: 'PC IP Address',
            hintText: '192.168.1.100',
            prefixIcon: const Icon(Icons.computer),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark 
                ? AppTheme.darkCard 
                : AppTheme.lightCard,
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Port field
        TextField(
          controller: _portController,
          keyboardType: TextInputType.number,
          enabled: !_isConnecting,
          decoration: InputDecoration(
            labelText: 'Port',
            hintText: '8000',
            prefixIcon: const Icon(Icons.settings_ethernet),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark 
                ? AppTheme.darkCard 
                : AppTheme.lightCard,
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Connect button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isConnecting ? null : _connectToPC,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isConnecting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi),
                      SizedBox(width: 8),
                      Text('Connect to PC'),
                    ],
                  ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms, duration: 500.ms);
  }
  
  Widget _buildHelpCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondaryColor = isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'How to connect',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStep('1', 'Start backend on your laptop'),
          Text(
            '   cd backend && python main.py --host 0.0.0.0',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          _buildStep('2', 'Find your PC\'s IP address'),
          Text(
            '   Run ipconfig, look for IPv4 Address',
            style: TextStyle(
              fontSize: 12,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          _buildStep('3', 'Enter IP above and connect'),
          const SizedBox(height: 8),
          Text(
            '⚠️ Phone and PC must be on the same WiFi network',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.orange[700],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 500.ms, duration: 500.ms);
  }
  
  Widget _buildStep(String number, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
          ),
        ),
      ],
    );
  }
}
