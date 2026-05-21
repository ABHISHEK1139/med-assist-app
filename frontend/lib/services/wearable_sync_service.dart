import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

class WearableSyncService {
  final Health _health = Health();
  
  bool _isAuthorized = false;
  
  // Define the types of data we want to read
  final List<HealthDataType> _dataTypes = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_ASLEEP,
  ];

  /// Initialize and request permissions
  Future<bool> requestPermissions() async {
    try {
      // First, check basic permissions
      final activityPermission = await Permission.activityRecognition.request();
      if (!activityPermission.isGranted) {
        return false;
      }
      
      // Request permissions from Health Connect / Google Fit / Apple Health
      _isAuthorized = await _health.requestAuthorization(_dataTypes);
      
      return _isAuthorized;
    } catch (e) {
      print('Error requesting wearable permissions: $e');
      return false;
    }
  }

  /// Check if we have permissions
  bool get isAuthorized => _isAuthorized;

  /// Fetch today's health metrics
  Future<Map<String, dynamic>> fetchTodayMetrics() async {
    if (!_isAuthorized) {
      final granted = await requestPermissions();
      if (!granted) return {};
    }

    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    // For sleep, we need to look back to yesterday evening
    final yesterdayEvening = midnight.subtract(const Duration(hours: 6));

    Map<String, dynamic> metrics = {};

    try {
      // 1. Fetch Steps
      int? steps = await _health.getTotalStepsInInterval(midnight, now);
      if (steps != null) {
        metrics['steps_today'] = steps;
      }

      // 2. Fetch Heart Rate
      List<HealthDataPoint> hrData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: midnight,
        endTime: now,
      );
      
      if (hrData.isNotEmpty) {
        // Calculate average heart rate
        double sum = 0;
        int count = 0;
        for (var data in hrData) {
          try {
             // Handle numeric values
             if (data.value is NumericHealthValue) {
               sum += (data.value as NumericHealthValue).numericValue.toDouble();
               count++;
             }
          } catch(e) {}
        }
        if (count > 0) {
          metrics['avg_heart_rate'] = (sum / count).round();
        }
      }

      // 3. Fetch Sleep
      List<HealthDataPoint> sleepData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_ASLEEP],
        startTime: yesterdayEvening,
        endTime: now,
      );
      
      if (sleepData.isNotEmpty) {
        // Calculate total sleep duration
        int totalSleepMinutes = 0;
        for (var data in sleepData) {
          final start = data.dateFrom;
          final end = data.dateTo;
          totalSleepMinutes += end.difference(start).inMinutes;
        }
        
        metrics['sleep_hours_last_night'] = (totalSleepMinutes / 60).toStringAsFixed(1);
      }

      return metrics;
    } catch (e) {
      print('Error fetching wearable data: $e');
      return metrics; // Return whatever we managed to fetch
    }
  }
}
