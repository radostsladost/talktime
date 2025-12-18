import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/shared/models/user.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  /// Login