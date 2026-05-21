/// Digital Health Archive
/// 
/// Automatic medical history extraction from conversations
/// with proper temporal reasoning.
/// 
/// Example:
/// ```dart
/// // Initialize
/// final archive = HealthArchiveService();
/// await archive.initialize();
/// 
/// // Use with chat
/// final chat = HealthAwareChat(llmService, archive);
/// final response = await chat.chat("I've had diabetes for 10 years");
/// // ↑ Automatically extracts: Condition(name: "Diabetes", onsetYear: 2015)
/// 
/// // View profile
/// final profile = await archive.getFullProfile();
/// print(profile.conditionsSummary);
/// ```

library health_archive;

export 'database.dart' show HealthArchiveDatabase;
export 'models.dart';
export 'health_archive_service.dart' show HealthArchiveService;
export 'medical_extractor.dart' show MedicalExtractor, ExtractionResult;
export 'health_aware_chat.dart' show HealthAwareChat;
export 'health_context_builder.dart';
export 'symptom_extractor.dart';
