import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment configuration for the application
/// This allows easy switching between development and production settings
class Environment {
  static const String _currentEnv = String.fromEnvironment(
    'ENV_PROF',
    defaultValue: 'development',
  );

  static bool get isDevelopment => _currentEnv == 'development';
  static bool get isProduction => _currentEnv == 'production';

  /// Base URL for the API
  static String get apiBaseUrl {
    switch (_currentEnv) {
      case 'production':
        return dotenv.env['API_BASE_URL'] ??
            'https://api.example.host'; // Replace with your production URL
      case 'development':
      default:
        // For Android emulator use 10.0.2.2 instead of localhost
        // For iOS simulator use localhost
        // For physical device use your computer's IP address (e.g., 192.168.1.100)
        return 'http://localhost:5000';
    }
  }

  /// WebSocket base URL (derived from API base URL)
  static String get wsBaseUrl => apiBaseUrl;

  /// API timeout duration
  static Duration get apiTimeout => const Duration(seconds: 30);

  /// Enable logging
  static bool get enableLogging => isDevelopment;

  /// Enable detailed error messages
  static bool get enableDetailedErrors => isDevelopment;

  /// Configuration info
  static Map<String, dynamic> get config => {
    'environment': _currentEnv,
    'apiBaseUrl': apiBaseUrl,
    'wsBaseUrl': wsBaseUrl,
    'isDevelopment': isDevelopment,
    'isProduction': isProduction,
  };

  /// Print current configuration
  static void printConfig() {
    if (enableLogging) {
      print('=== Environment Configuration ===');
      config.forEach((key, value) {
        print('$key: $value');
      });
      print('================================');
    }
  }
}

/// Platform-specific URL helpers
class PlatformUrls {
  /// Get the correct localhost URL based on platform
  /// - Android Emulator: 10.0.2.2
  /// - iOS Simulator: localhost or 127.0.0.1
  /// - Physical Device: Your computer's local IP
  static String getLocalhost({int port = 5000, String? deviceIp}) {
    if (deviceIp != null) {
      return 'http://$deviceIp:$port';
    }
    // Default to localhost, user can override in api_constants.dart
    return 'http://localhost:$port';
  }

  /// Get Android emulator localhost
  static String androidEmulatorUrl({int port = 5000}) {
    return 'http://10.0.2.2:$port';
  }

  /// Get iOS simulator localhost
  static String iosSimulatorUrl({int port = 5000}) {
    return 'http://localhost:$port';
  }
}
