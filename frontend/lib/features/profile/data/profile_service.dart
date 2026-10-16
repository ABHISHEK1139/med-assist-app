import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';

/// Profile Service - client for the backend /profile endpoints.
///
/// Mirrors [AIService]: a thin Dio wrapper around the Python backend's
/// patient-profile routes (GET /profile, POST /profile).
class ProfileService {
  final Dio _dio;
  final String baseUrl;

  ProfileService({
    required this.baseUrl,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: AppConstants.apiTimeout,
      receiveTimeout: AppConstants.apiTimeout,
      headers: {
        'Content-Type': 'application/json',
      },
    );
  }

  /// Fetch the full digital health profile from the backend.
  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get('/profile');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Update the profile with the given fields.
  Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> profileData) async {
    final response = await _dio.post('/profile', data: profileData);
    return Map<String, dynamic>.from(response.data as Map);
  }
}
