import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/egg_models.dart';

/// Storage service for ModelCombination objects and OpenRouterConfig
class EggStorage {
  static const _combinationsKey = 'hermes_hive_model_combinations';
  static const _openRouterConfigKey = 'hermes_hive_openrouter_config';

  /// Load saved model combinations from SharedPreferences
  Future<List<ModelCombination>> loadCombinations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_combinationsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => ModelCombination.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save model combinations to SharedPreferences
  Future<void> saveCombinations(List<ModelCombination> combinations) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(combinations.map((e) => e.toJson()).toList());
    await prefs.setString(_combinationsKey, jsonStr);
  }

  /// Load OpenRouter configuration from SharedPreferences
  Future<OpenRouterConfig> loadOpenRouterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_openRouterConfigKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return OpenRouterConfig();
    }

    try {
      return OpenRouterConfig.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return OpenRouterConfig();
    }
  }

  /// Save OpenRouter configuration to SharedPreferences
  Future<void> saveOpenRouterConfig(OpenRouterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(config.toJson());
    await prefs.setString(_openRouterConfigKey, jsonStr);
  }
}
