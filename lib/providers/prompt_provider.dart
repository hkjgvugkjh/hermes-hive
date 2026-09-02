import 'package:flutter/foundation.dart';
import '../services/prompt_storage.dart';

class PromptProvider extends ChangeNotifier {
  PromptStorage? _storage;
  List<SavedPrompt> _prompts = [];
  bool _initialized = false;

  List<SavedPrompt> get prompts => List.unmodifiable(_prompts);
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _storage = await PromptStorage.getInstance();
    _prompts = _storage!.all;
    _initialized = true;
    notifyListeners();
  }

  Future<void> addPrompt(SavedPrompt prompt) async {
    await _storage?.add(prompt);
    _prompts = _storage!.all;
    notifyListeners();
  }

  Future<void> deletePrompt(String id) async {
    await _storage?.remove(id);
    _prompts = _storage!.all;
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _storage?.clear();
    _prompts = [];
    notifyListeners();
  }
}
