import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/core/network/api_client.dart';
import 'package:logger/logger.dart';

/// Service for uploading media files
class MediaService {
  final ApiClient _apiClient = ApiClient();
  final Logger _logger = Logger(output: ConsoleOutput());

  /// Upload an image file and return the URL
  Future<String?> uploadImage(File file) async {
    try {
      _logger.i('Uploading image: ${file.path}');

      final mimeType = _getMimeType(file.path);
      final response = await _apiClient.uploadFile(
        ApiConstants.uploadMedia,
        filePath: file.path,
        fieldName: 'file',
        contentType: mimeType,
      );

      final url = response['data']['url'] as String;
      _logger.i('Image uploaded successfully: $url');
      return url;
    } catch (e) {
      _logger.e('Error uploading image: $e');
      return null;
    }
  }

  /// Upload image from bytes (for web)
  Future<String?> uploadImageBytes(Uint8List bytes, String filename) async {
    try {
      _logger.i('Uploading image bytes: $filename');

      final mimeType = _getMimeType(filename);
      final response = await _apiClient.uploadFileBytes(
        ApiConstants.uploadMedia,
        bytes: bytes,
        filename: filename,
        fieldName: 'file',
        contentType: mimeType,
      );

      final url = response['data']['url'] as String;
      _logger.i('Image uploaded successfully: $url');
      return url;
    } catch (e) {
      _logger.e('Error uploading image: $e');
      return null;
    }
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  void dispose() {
    _apiClient.dispose();
  }
}
