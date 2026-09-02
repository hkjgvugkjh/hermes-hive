// Data models for the "Egg of Today" (今天的鸡蛋) feature
// Manages free models from OpenRouter and user-defined model combinations.
library;

/// Configuration for OpenRouter API access
class OpenRouterConfig {
  final String apiUrl;
  final String apiKey;

  OpenRouterConfig({
    this.apiUrl = 'https://openrouter.ai/api/v1',
    this.apiKey = '',
  });

  Map<String, dynamic> toJson() => {
        'apiUrl': apiUrl,
        'apiKey': apiKey,
      };

  factory OpenRouterConfig.fromJson(Map<String, dynamic> json) =>
      OpenRouterConfig(
        apiUrl: json['apiUrl'] as String? ?? 'https://openrouter.ai/api/v1',
        apiKey: json['apiKey'] as String? ?? '',
      );
}

/// A free model from OpenRouter
class FreeModel {
  final String id;
  final String name;
  final String provider;
  final String description;
  final int contextLength;
  final Map<String, dynamic> pricing;

  FreeModel({
    required this.id,
    required this.name,
    required this.provider,
    this.description = '',
    this.contextLength = 0,
    this.pricing = const {},
  });

  factory FreeModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final parts = id.split('/');
    return FreeModel(
      id: id,
      name: json['name'] as String? ?? id,
      provider: parts.isNotEmpty ? parts[0] : '',
      description: json['description'] as String? ?? '',
      contextLength: (json['context_length'] as num?)?.toInt() ?? 0,
      pricing: json['pricing'] as Map<String, dynamic>? ?? {},
    );
  }

  bool get isFree {
    final p = pricing;
    return (p['prompt'] == '0' || p['prompt'] == 0) &&
        (p['completion'] == '0' || p['completion'] == 0);
  }
}

/// A user-defined combination of free models
class ModelCombination {
  final String id;
  final String name;
  final List<String> modelIds;
  final DateTime createdAt;

  ModelCombination({
    required this.id,
    required this.name,
    required this.modelIds,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'modelIds': modelIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ModelCombination.fromJson(Map<String, dynamic> json) =>
      ModelCombination(
        id: json['id'] as String,
        name: json['name'] as String,
        modelIds: (json['modelIds'] as List).cast<String>(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
