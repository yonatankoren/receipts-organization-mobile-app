/// Backend API service.
/// Sends receipt images to the backend for OCR + LLM parsing.
/// The backend handles all secrets (Cloud Vision key, LLM API key).

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

class BackendService {
  static final BackendService instance = BackendService._();
  BackendService._();

  static const String _prefKeyBackendUrl = 'backend_url';

  Future<String> getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyBackendUrl) ?? AppConstants.defaultBackendUrl;
  }

  Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyBackendUrl, url);
  }

  /// Send a receipt image to the backend for processing (OCR + LLM parse).
  /// Returns the parsed receipt data as a Map.
  ///
  /// Throws on network error or non-200 response.
  Future<Map<String, dynamic>> processReceipt({
    required String imagePath,
    required String receiptId,
    String locale = 'he-IL',
    String currencyDefault = 'ILS',
  }) async {
    final backendUrl = await getBackendUrl();
    final uri = Uri.parse('$backendUrl/processReceipt');

    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw Exception('Image file not found: $imagePath');
    }

    // Get Google access token for backend authentication
    final accessToken = await AuthService.instance.getAccessToken();
    if (accessToken == null) {
      throw Exception('Not authenticated — please sign in first');
    }

    // Build multipart request
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['receipt_id'] = receiptId
      ..fields['locale_hint'] = locale
      ..fields['currency_default'] = currencyDefault
      ..fields['timezone'] = AppConstants.defaultTimezone
      ..files.add(
        await http.MultipartFile.fromPath(
          'image',
          imagePath,
          filename: '$receiptId.jpg',
        ),
      );

    debugPrint('Backend: sending receipt $receiptId to $uri');

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw Exception('Backend request timed out');
      },
    );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Backend returned ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('Backend: got response for $receiptId');
    return data;
  }

  /// Health check
  Future<bool> isHealthy() async {
    try {
      final backendUrl = await getBackendUrl();
      final response = await http.get(
        Uri.parse('$backendUrl/health'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

