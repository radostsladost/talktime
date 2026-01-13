// features/auth/data/user_service.dart

import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:talktime/core/network/api_client.dart'; // or however you make HTTP calls

class ProfileService {
  final ApiClient _apiClient = ApiClient();

  Future<User> getCurrentUser() async {
    // e.g., GET /api/users/me
    final response = await _apiClient.get(ApiConstants.updateProfile);
    return User.fromJson(response);
  }

  Future<User> updateUser({
    String? username,
    String? email,
    String? description,
    String? password,
    String? newPassword,
  }) async {
    // e.g., PATCH /api/users/me
    final response = await _apiClient.put(
      ApiConstants.updateProfile,
      body: {
        'username': username,
        'email': email,
        'description': description,
        'password': password,
        'newPassword': newPassword,
      },
    );
    return User.fromJson(response);
  }

  Future<String?> uploadAvatar(String imagePath) async {
    // Simulate upload → returns URL
    // In real app: use multipart/form-data upload
    await Future.delayed(const Duration(seconds: 1)); // simulate network
    return null; // mock URL
  }
}
