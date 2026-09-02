import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved user prompt extracted from a conversation
class SavedPrompt {
  final String id;
  final String text;
  final String sessionId;
  final String serverId;
  final String serverName;
  final DateTime createdAt;

  SavedPrompt({
    required this.id,
    required this.text,
    required this.sessionId,
    required this.serverId,
    required this.serverName,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'sessionId': sessionId,
        'serverId': serverId,
        'serverName': serverName,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedPrompt.fromJson(Map<String, dynamic> json) => SavedPrompt(
        id: json['id'] as String,
        text: json['text'] as String,
        sessionId: json['sessionId'] as String,
        serverId: json['serverId'] as String,
        serverName: json['serverName'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Local storage for saved prompts
class PromptStorage {
  static const String _key = 'hermes_hive_saved_prompts';
  static PromptStorage? _instance;
  late SharedPreferences _prefs;
  List<SavedPrompt> _prompts = [];

  PromptStorage._();

  static Future<PromptStorage> getInstance() async {
    if (_instance == null) {
      _instance = PromptStorage._();
      _instance!._prefs = await SharedPreferences.getInstance();
      await _instance!._load();
    }
    return _instance!;
  }

  Future<void> _load() async {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _prompts = list
          .map((e) => SavedPrompt.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _save() async {
    final raw = jsonEncode(_prompts.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, raw);
  }

  List<SavedPrompt> get all => List.unmodifiable(_prompts);

  Future<void> add(SavedPrompt prompt) async {
    _prompts.insert(0, prompt);
    await _save();
  }

  Future<void> remove(String id) async {
    _prompts.removeWhere((p) => p.id == id);
    await _save();
  }

  Future<void> clear() async {
    _prompts.clear();
    await _save();
  }
}
