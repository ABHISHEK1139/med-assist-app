/// API and configuration constants
class AppConstants {
  AppConstants._();
  
  // API Configuration
  // Use your PC's network IP for phone testing
  // Change back to 'http://127.0.0.1:8000' for desktop-only use
  static const String defaultApiBaseUrl = 'http://10.0.2.2:8000';
  static const Duration apiTimeout = Duration(seconds: 60);
  static const Duration longRequestTimeout = Duration(minutes: 5);
  
  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 350);
  static const Duration longAnimation = Duration(milliseconds: 500);
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double borderRadius = 12.0;
  static const double cardRadius = 16.0;
  
  // Message limits
  static const int maxMessageLength = 4000;
  static const int maxFileUploadMB = 10;
  
  // Document types
  static const List<String> supportedDocTypes = [
    'lab_report',
    'prescription',
    'radiology',
    'notes',
    'general',
  ];
  
  static const Map<String, String> docTypeLabels = {
    'lab_report': 'Lab Report',
    'prescription': 'Prescription',
    'radiology': 'X-Ray / Imaging',
    'notes': 'Medical Notes',
    'general': 'General Document',
  };
  
  // File extensions
  static const List<String> allowedFileExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'txt',
    'doc',
    'docx',
  ];
}
