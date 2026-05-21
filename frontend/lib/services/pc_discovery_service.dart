import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

/// PC Discovery Service
/// 
/// Automatically finds Med Assist App backend running on local network.
/// No need to manually enter IP address!
/// 
/// Methods:
/// 1. UDP Broadcast - Scans local network for backend
/// 2. Saved IP - Tries last known IP first
/// 3. Common IPs - Tries common local IPs
class PCDiscoveryService {
  static const int defaultPort = 8000;
  static const Duration scanTimeout = Duration(seconds: 5);  // Increased for hotspot
  
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),  // Increased for hotspot
    receiveTimeout: const Duration(seconds: 5),
    validateStatus: (status) => status != null && status < 500,
  ));
  
  /// Discovered servers
  final List<DiscoveredServer> _discoveredServers = [];
  List<DiscoveredServer> get discoveredServers => List.from(_discoveredServers);
  
  /// Stream for discovery progress
  final _progressController = StreamController<DiscoveryProgress>.broadcast();
  Stream<DiscoveryProgress> get progressStream => _progressController.stream;
  
  /// Auto-discover PC on local network
  /// 
  /// Scans common IP ranges and checks for Med Assist App backend
  Future<List<DiscoveredServer>> discoverServers({
    String? lastKnownIP,
    int port = defaultPort,
  }) async {
    _discoveredServers.clear();
    
    // Step 1: Try last known IP first (fastest)
    if (lastKnownIP != null) {
      _progressController.add(DiscoveryProgress(
        status: 'Trying last known IP: $lastKnownIP',
        progress: 0.05,
      ));
      
      final server = await _checkServer(lastKnownIP, port);
      if (server != null) {
        _discoveredServers.add(server);
        _progressController.add(DiscoveryProgress(
          status: 'Found server at $lastKnownIP!',
          progress: 1.0,
          found: true,
        ));
        return _discoveredServers;
      }
    }
    
    // Step 2: Get local IP and scan subnet
    _progressController.add(DiscoveryProgress(
      status: 'Scanning local network...',
      progress: 0.1,
    ));
    
    final localIPs = await _getLocalIPs();
    
    // Also try common hotspot subnets directly
    final subnetsToScan = <String>{};
    
    for (final localIP in localIPs) {
      final parts = localIP.split('.');
      if (parts.length == 4) {
        subnetsToScan.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }
    
    // Always include mobile hotspot subnets (your PC connects to phone hotspot)
    subnetsToScan.add('192.168.43');  // Android hotspot (common)
    subnetsToScan.add('172.20.10');   // iPhone hotspot
    subnetsToScan.add('10.103.198');  // Your specific hotspot subnet!
    
    for (final subnet in subnetsToScan) {
      // For hotspot networks, scan more IPs (PC could be .2 to .50)
      final isHotspot = subnet == '192.168.43' || 
                        subnet == '172.20.10' || 
                        subnet.startsWith('10.');  // 10.x.x.x hotspots
      
      // Scan common host IPs in parallel
      final futures = <Future<DiscoveredServer?>>[];
      
      // Hotspot: scan .1 to .30 (PC usually gets low numbers)
      // Router: scan common IPs
      final hostsToScan = isHotspot 
          ? List.generate(30, (i) => i + 1)  // 1-30 for hotspot
          : [1, 2, 100, 101, 102, 103, 104, 105, 50, 51, ...List.generate(20, (i) => i + 1)];
      
      for (final host in hostsToScan.toSet()) {
        final ip = '$subnet.$host';
        futures.add(_checkServer(ip, port));
      }
      
      int checked = 0;
      for (final future in futures) {
        final server = await future;
        checked++;
        
        _progressController.add(DiscoveryProgress(
          status: 'Scanning $subnet.x ($checked/${futures.length})',
          progress: 0.1 + (0.8 * checked / futures.length / subnetsToScan.length),
        ));
        
        if (server != null && !_discoveredServers.any((s) => s.ip == server.ip)) {
          _discoveredServers.add(server);
        }
      }
    }
    
    _progressController.add(DiscoveryProgress(
      status: _discoveredServers.isEmpty 
          ? 'No servers found' 
          : 'Found ${_discoveredServers.length} server(s)',
      progress: 1.0,
      found: _discoveredServers.isNotEmpty,
    ));
    
    return _discoveredServers;
  }
  
  /// Quick scan - prioritize hotspot IPs, then common router IPs
  Future<DiscoveredServer?> quickScan({int port = defaultPort}) async {
    // First: Try Android hotspot subnet (most likely for your setup!)
    for (final host in [2, 3, 4, 5, 6, 7, 8, 9, 10, 1]) {
      final server = await _checkServer('192.168.43.$host', port);
      if (server != null) return server;
    }
    
    // Second: Try 10.x subnet (some hotspots use this - like yours!)
    for (final host in [78, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      final server = await _checkServer('10.103.198.$host', port);
      if (server != null) return server;
    }
    
    // Third: Try iPhone hotspot subnet
    for (final host in [2, 3, 4, 5, 1]) {
      final server = await _checkServer('172.20.10.$host', port);
      if (server != null) return server;
    }
    
    // Fourth: Try from actual network interfaces
    final localIPs = await _getLocalIPs();
    
    for (final localIP in localIPs) {
      final parts = localIP.split('.');
      if (parts.length != 4) continue;
      
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      
      // Check most common IPs first
      for (final host in [1, 2, 100, 101, 102, 50]) {
        final server = await _checkServer('$subnet.$host', port);
        if (server != null) return server;
      }
    }
    
    return null;
  }
  
  /// Check if a specific IP has Med Assist App backend
  Future<DiscoveredServer?> _checkServer(String ip, int port) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/health',
        options: Options(
          sendTimeout: scanTimeout,
          receiveTimeout: scanTimeout,
        ),
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        
        return DiscoveredServer(
          ip: ip,
          port: port,
          modelReady: data['model_ready'] == true,
          gpuEnabled: data['gpu_enabled'] == true,
          gpuName: data['gpu_name'] ?? 'Unknown',
          version: data['version'] ?? 'Unknown',
        );
      }
    } catch (_) {
      // Server not found at this IP
    }
    
    return null;
  }
  
  /// Get local IP addresses
  /// Handles both WiFi router and mobile hotspot scenarios
  Future<List<String>> _getLocalIPs() async {
    final ips = <String>[];
    
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            final ip = addr.address;
            // Include: 192.168.x.x (routers), 172.x.x.x (some hotspots), 10.x.x.x (enterprise)
            if (ip.startsWith('192.168') || 
                ip.startsWith('172.') || 
                ip.startsWith('10.')) {
              ips.add(ip);
            }
          }
        }
      }
    } catch (_) {}
    
    // Fallback: Add common hotspot and router subnets
    if (ips.isEmpty) {
      ips.addAll([
        '192.168.43.1',   // Android hotspot gateway (most common!)
        '172.20.10.1',    // iPhone hotspot gateway
        '192.168.1.1',    // Common router
        '192.168.0.1',    // Common router
      ]);
    }
    
    return ips;
  }
  
  /// Check if we're running as mobile hotspot
  /// If phone is hotspot, connected PC will have IPs like 192.168.43.x
  bool _isMobileHotspotNetwork(String localIP) {
    return localIP.startsWith('192.168.43') ||  // Android hotspot
           localIP.startsWith('172.20.10');     // iPhone hotspot
  }
  
  void dispose() {
    _progressController.close();
    _dio.close();
  }
}

/// Discovered server information
class DiscoveredServer {
  final String ip;
  final int port;
  final bool modelReady;
  final bool gpuEnabled;
  final String gpuName;
  final String version;
  
  DiscoveredServer({
    required this.ip,
    required this.port,
    required this.modelReady,
    required this.gpuEnabled,
    required this.gpuName,
    required this.version,
  });
  
  String get url => 'http://$ip:$port';
  
  String get displayName => gpuEnabled 
      ? '🖥️ $ip (GPU: $gpuName)' 
      : '💻 $ip (CPU)';
  
  @override
  String toString() => 'Server($ip:$port, GPU: $gpuEnabled)';
}

/// Discovery progress update
class DiscoveryProgress {
  final String status;
  final double progress;
  final bool found;
  
  DiscoveryProgress({
    required this.status,
    required this.progress,
    this.found = false,
  });
}
