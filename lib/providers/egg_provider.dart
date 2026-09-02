import 'package:flutter/foundation.dart';
import '../models/egg_models.dart';
import '../services/openrouter_service.dart';
import '../services/egg_storage.dart';

/// State management for the "Egg of Today" feature
class EggProvider extends ChangeNotifier {
  final EggStorage _storage = EggStorage();

  // OpenRouter configuration
  OpenRouterConfig _config = OpenRouterConfig();
  OpenRouterConfig get config => _config;

  // Free models fetched from OpenRouter
  List<FreeModel> _freeModels = [];
  List<FreeModel> get freeModels => _freeModels;

  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  // User-defined model combinations
  List<ModelCombination> _combinations = [];
  List<ModelCombination> get combinations => _combinations;

  // Availability cache (modelId -> isAvailable)
  final Map<String, bool> _availability = {};

  /// Get availability status for a model
  bool isModelAvailableCached(String modelId) => _availability[modelId] ?? false;

  /// Check if availability has been checked for a model
  bool hasAvailabilityInfo(String modelId) => _availability.containsKey(modelId);

  /// Initialize - load config and combinations from storage
  Future<void> init() async {
    _config = await _storage.loadOpenRouterConfig();
    _combinations = await _storage.loadCombinations();
    notifyListeners();
  }

  /// Update OpenRouter configuration
  Future<void> updateConfig(OpenRouterConfig config) async {
    _config = config;
    await _storage.saveOpenRouterConfig(config);
    // Clear availability cache when config changes
    _availability.clear();
    notifyListeners();
  }

  /// Fetch free models from OpenRouter
  Future<void> fetchFreeModels() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final service = OpenRouterService(_config);
      _freeModels = await service.fetchFreeModels();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Check availability of models in a combination
  Future<Map<String, bool>> checkCombinationAvailability(
      ModelCombination combination) async {
    if (_config.apiKey.isEmpty) return {};

    final service = OpenRouterService(_config);
    final results =
        await service.checkModelsAvailability(combination.modelIds);

    // Update cache
    _availability.addAll(results);
    notifyListeners();

    return results;
  }

  /// Add a new model combination
  Future<void> addCombination(ModelCombination combination) async {
    _combinations.add(combination);
    await _storage.saveCombinations(_combinations);
    notifyListeners();
  }

  /// Update an existing combination
  Future<void> updateCombination(ModelCombination combination) async {
    final index = _combinations.indexWhere((c) => c.id == combination.id);
    if (index != -1) {
      _combinations[index] = combination;
      await _storage.saveCombinations(_combinations);
      notifyListeners();
    }
  }

  /// Delete a combination
  Future<void> deleteCombination(String id) async {
    _combinations.removeWhere((c) => c.id == id);
    await _storage.saveCombinations(_combinations);
    notifyListeners();
  }

  /// Refresh availability cache
  Future<void> refreshAvailability() async {
    _availability.clear();
    notifyListeners();

    // Check all models from all combinations
    for (final combination in _combinations) {
      await checkCombinationAvailability(combination);
    }
  }
}
