import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/egg_models.dart';

/// Service for fetching free models from OpenRouter API
class OpenRouterService {
  final OpenRouterConfig config;

  OpenRouterService(this.config);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (config.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${config.apiKey}',
      };

  /// Fetch all free models from OpenRouter
  Future<List<FreeModel>> fetchFreeModels() async {
    try {
      final response = await http
          .get(
            Uri.parse('${config.apiUrl}/models'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List? ?? [])
            .map((m) => FreeModel.fromJson(m as Map<String, dynamic>))
            .where((m) => m.isFree)
            .toList();
        return models;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Check if a specific model ID is available on OpenRouter
  Future<bool> isModelAvailable(String modelId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${config.apiUrl}/models/$modelId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Check multiple models availability at once
  /// Returns a map of modelId -> isAvailable
  Future<Map<String, bool>> checkModelsAvailability(
      List<String> modelIds) async {
    final results = <String, bool>{};
    // Check in parallel batches of 5
    for (var i = 0; i < modelIds.length; i += 5) {
      final batch = modelIds.skip(i).take(5).toList();
      final futures = batch.map((id) async {
        final available = await isModelAvailable(id);
        results[id] = available;
      });
      await Future.wait(futures);
    }
    return results;
  }
}
