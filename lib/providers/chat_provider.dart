import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../providers/server_provider.dart';
import '../providers/global_config_provider.dart';
import '../providers/debug_logger.dart';
import '../providers/prompt_provider.dart';
import '../services/prompt_storage.dart';

/// View mode for the session list
enum SessionViewMode {
  all,
  recent,
}

/// Chat state provider for managing conversations
class ChatProvider extends ChangeNotifier {
  final ServerProvider _serverProvider;
  final GlobalConfigProvider _globalConfigProvider;
  PromptProvider? _promptProvider;
  final Set<String> _savedPromptTexts = {};
  
  List<HermesSession> _sessions = [];
  List<ChatMessage> _currentMessages = [];
  String? _currentSessionId;
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  bool _needsLogin = false;
  bool _isLoggedIn = false;
  List<ModelGroup> _modelGroups = [];
  String? _selectedModel;
  String? _selectedProvider;
  bool _isLoadingModels = false;
  
  // Session view mode
  SessionViewMode _sessionViewMode = SessionViewMode.all;
  final Map<String, List<HermesSession>> _serverSessionsCache = {};
  final Map<String, DateTime> _sessionActivity = {}; // sessionId -> last activity
  
  // Auto-continue mode state
  bool _autoContinueEnabled = false;
  int _autoContinueDoneCount = 0;
  final String _autoContinuePrompt = '完成后回复OK，全部完成回复DONE';
  final String _autoContinueFollowUp = '继续，完成后回复OK，全部完成回复DONE';

  ChatProvider(this._serverProvider, this._globalConfigProvider) {
    _serverProvider.addListener(_onServerProviderChange);
  }

  void setPromptProvider(PromptProvider provider) {
    _promptProvider = provider;
  }

  void _saveUserPrompts(List<ChatMessage> messages) {
    if (_promptProvider == null) return;
    final server = _serverProvider.activeServer;
    if (server == null) return;

    for (final msg in messages) {
      if (msg.role == 'user' && msg.content.trim().isNotEmpty) {
        final text = msg.content.trim();
        final key = '${server.id}:$text';
        if (!_savedPromptTexts.contains(key)) {
          _savedPromptTexts.add(key);
          _promptProvider!.addPrompt(SavedPrompt(
            id: DateTime.now().millisecondsSinceEpoch.toString() + text.hashCode.toString(),
            text: text,
            sessionId: _currentSessionId ?? '',
            serverId: server.id,
            serverName: server.name,
            createdAt: DateTime.now(),
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    _serverProvider.removeListener(_onServerProviderChange);
    super.dispose();
  }

  void _onServerProviderChange() {
    final currentId = _serverProvider.activeServer?.id;
    if (currentId != null) {
      _needsLogin = false;
      _isLoggedIn = false;
      DebugLogger.instance.info(
        'Server changed',
        'newServer=${_serverProvider.activeServer?.name} id=$currentId',
      );
      loadSessions();
    }
  }

  List<HermesSession> get sessions => _sessions;
  List<ChatMessage> get currentMessages => _currentMessages;
  String? get currentSessionId => _currentSessionId;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  bool get needsLogin => _needsLogin;
  bool get isLoggedIn => _isLoggedIn;
  List<ModelGroup> get modelGroups => _modelGroups;
  String? get selectedModel => _selectedModel;
  String? get selectedProvider => _selectedProvider;
  bool get isLoadingModels => _isLoadingModels;
  SessionViewMode get sessionViewMode => _sessionViewMode;
  
  // Auto-continue getters
  bool get autoContinueEnabled => _autoContinueEnabled;
  int get autoContinueDoneCount => _autoContinueDoneCount;
  String get autoContinuePrompt => _autoContinuePrompt;
  String get autoContinueFollowUp => _autoContinueFollowUp;

  /// Get sessions to display based on current view mode
  List<HermesSession> get displaySessions {
    final server = _serverProvider.activeServer;
    if (server == null) return [];
    
    if (_sessionViewMode == SessionViewMode.recent) {
      return getRecentSessions(server.id);
    }
    return _sessions;
  }

  /// Get recent sessions across all servers
  List<HermesSession> getRecentSessions([String? forServerId]) {
    final allSessions = <HermesSession>[];
    
    for (final entry in _serverSessionsCache.entries) {
      final serverId = entry.key;
      final sessions = entry.value;
      final server = _serverProvider.servers.firstWhere(
        (s) => s.id == serverId,
        orElse: () => ServerConfig(id: '', name: 'Unknown', url: ''),
      );
      
      for (final session in sessions) {
        // Only include sessions with recent activity (last 24 hours or manually tracked)
        final lastActivity = _sessionActivity[session.id] ?? session.updatedAt;
        if (lastActivity != null) {
          final age = DateTime.now().difference(lastActivity);
          if (age.inHours < 24) {
            allSessions.add(session.copyWith(
              serverId: serverId,
              serverName: server.name,
              status: _getSessionStatus(session),
            ));
          }
        }
      }
    }
    
    // Sort by most recent first
    allSessions.sort((a, b) {
      final aTime = _sessionActivity[a.id] ?? a.updatedAt ?? DateTime(1970);
      final bTime = _sessionActivity[b.id] ?? b.updatedAt ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    
    return allSessions;
  }

  /// Determine session status based on recent messages
  SessionStatus _getSessionStatus(HermesSession session) {
    // If we have current messages for this session, check the last message
    if (_currentSessionId == session.id && _currentMessages.isNotEmpty) {
      final lastMsg = _currentMessages.last;
      if (lastMsg.role == 'assistant') {
        if (lastMsg.content.contains('DONE')) {
          return SessionStatus.completed;
        }
        return SessionStatus.inProgress;
      }
    }
    
    // Default: check if session has recent activity
    final lastActivity = _sessionActivity[session.id] ?? session.updatedAt;
    if (lastActivity != null) {
      final age = DateTime.now().difference(lastActivity);
      if (age.inMinutes < 5) {
        return SessionStatus.inProgress;
      }
    }
    
    return SessionStatus.unknown;
  }

  /// Toggle session view mode
  void toggleSessionViewMode() {
    _sessionViewMode = _sessionViewMode == SessionViewMode.all 
        ? SessionViewMode.recent 
        : SessionViewMode.all;
    notifyListeners();
  }

  /// Set session view mode
  void setSessionViewMode(SessionViewMode mode) {
    _sessionViewMode = mode;
    notifyListeners();
  }

  /// Load sessions from the active server (always fetch from remote)
  Future<void> loadSessions() async {
    final server = _serverProvider.activeServer;
    if (server == null) {
      DebugLogger.instance.warn('loadSessions: no active server');
      return;
    }

    DebugLogger.instance.info('Loading sessions', 'server=${server.name} url=${server.url}');
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_globalConfigProvider.isProxyMode) {
        DebugLogger.instance.info('Proxy mode: connecting to proxy');
        final proxyClient = _serverProvider.getProxyClient(server);
        if (proxyClient != null) {
          await proxyClient.connect();
          DebugLogger.instance.success('Proxy connected');
          final result = await proxyClient.sendRequest(
            serverId: _globalConfigProvider.config.proxyUrl,
            method: 'GET',
            path: '/api/studio/sessions?limit=50',
          );
          DebugLogger.instance.info('Proxy response', 'status=${result['status_code']}');
          if (result['status_code'] == 200) {
            final body = result['body'] as Map<String, dynamic>;
            final sessions = (body['sessions'] as List? ?? body as List? ?? [])
                .map((s) => HermesSession.fromJson(s as Map<String, dynamic>))
                .toList();
            _sessions = sessions;
            _serverSessionsCache[server.id] = sessions;
            _isLoggedIn = true;
            DebugLogger.instance.success('Loaded ${sessions.length} sessions via proxy');
          } else if (result['status_code'] == 401) {
            _error = 'Authentication failed: proxy admin token invalid';
            _needsLogin = true;
            DebugLogger.instance.error('Proxy auth failed', 'status=401');
          }
        }
      } else {
        // Direct mode: auto-detect auth and login
        DebugLogger.instance.info('Direct mode: ensureLoggedIn', 'server=${server.name}');
        final client = _serverProvider.getClient(server);
        final loginResult = await client.ensureLoggedIn();
        if (!loginResult) {
          _needsLogin = true;
          _error = 'Login required: please enter username/password';
          DebugLogger.instance.warn('Login required', server.name);
          _isLoading = false;
          notifyListeners();
          return;
        }
        _isLoggedIn = true;
        DebugLogger.instance.success('Login successful');
        
        _sessions = await client.listSessions();
        _serverSessionsCache[server.id] = _sessions;
        DebugLogger.instance.success('Loaded ${_sessions.length} sessions');
      }
    } catch (e) {
      _error = 'Failed to load sessions: $e';
      DebugLogger.instance.error('loadSessions failed', e.toString());
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh sessions from remote (can be called manually)
  Future<void> refreshSessions() async {
    final server = _serverProvider.activeServer;
    if (server == null) return;
    
    // Don't show loading indicator for background refresh
    try {
      if (_globalConfigProvider.isProxyMode) {
        final proxyClient = _serverProvider.getProxyClient(server);
        if (proxyClient != null) {
          await proxyClient.connect();
          final result = await proxyClient.sendRequest(
            serverId: _globalConfigProvider.config.proxyUrl,
            method: 'GET',
            path: '/api/studio/sessions?limit=50',
          );
          if (result['status_code'] == 200) {
            final body = result['body'] as Map<String, dynamic>;
            final sessions = (body['sessions'] as List? ?? body as List? ?? [])
                .map((s) => HermesSession.fromJson(s as Map<String, dynamic>))
                .toList();
            _sessions = sessions;
            _serverSessionsCache[server.id] = sessions;
            DebugLogger.instance.success('Refreshed ${sessions.length} sessions via proxy');
          }
        }
      } else {
        final client = _serverProvider.getClient(server);
        if (_isLoggedIn) {
          _sessions = await client.listSessions();
          _serverSessionsCache[server.id] = _sessions;
          DebugLogger.instance.success('Refreshed ${_sessions.length} sessions');
        }
      }
    } catch (e) {
      DebugLogger.instance.error('refreshSessions failed', e.toString());
    }
    notifyListeners();
  }

  /// Retry login with updated credentials
  Future<bool> retryLogin(String username, String password) async {
    final server = _serverProvider.activeServer;
    if (server == null) return false;

    final updatedServer = server.copyWith(
      username: username,
      password: password,
      useAuth: true,
    );
    await _serverProvider.updateServer(updatedServer);
    
    _needsLogin = false;
    _error = null;
    
    final loginResult = await _serverProvider.loginServer(updatedServer);
    if (loginResult) {
      _isLoggedIn = true;
      DebugLogger.instance.success('Retry login successful');
      await loadSessions();
      return true;
    } else {
      _error = 'Login failed: check username/password';
      DebugLogger.instance.error('Retry login failed', updatedServer.name);
      return false;
    }
  }

  /// Select a session and load its messages
  Future<void> selectSession(String sessionId) async {
    final server = _serverProvider.activeServer;
    if (server == null) return;

    DebugLogger.instance.info('selectSession: sessionId=$sessionId');
    _currentSessionId = sessionId;
    _currentMessages = [];
    _isLoading = true;
    notifyListeners();

    try {
      if (_globalConfigProvider.isProxyMode) {
        final proxyClient = _serverProvider.getProxyClient(server);
        if (proxyClient != null) {
          await proxyClient.connect();
          final result = await proxyClient.sendRequest(
            serverId: _globalConfigProvider.config.proxyUrl,
            method: 'GET',
            path: '/api/studio/sessions/$sessionId',
          );
          DebugLogger.instance.info('selectSession: proxy response status=${result['status_code']}');
          if (result['status_code'] == 200) {
            final body = result['body'] as Map<String, dynamic>;
            final messages = <ChatMessage>[];
            final msgs = body['messages'] as List? ?? [];
            for (final m in msgs) {
              messages.add(ChatMessage(
                role: m['role'] as String? ?? 'unknown',
                content: m['content'] as String? ?? '',
                timestamp: m['timestamp'] != null
                    ? DateTime.tryParse(m['timestamp'] as String) ?? DateTime.now()
                    : DateTime.now(),
              ));
            }
            _currentMessages = messages;
            _saveUserPrompts(messages);
            DebugLogger.instance.success('selectSession: loaded ${messages.length} messages via proxy');
          }
        }
      } else {
        final client = _serverProvider.getClient(server);
        _currentMessages = await client.getSessionMessages(sessionId);
        _saveUserPrompts(_currentMessages);
        DebugLogger.instance.success('selectSession: loaded ${_currentMessages.length} messages');
      }
    } catch (e) {
      _error = 'Failed to load messages: $e';
      DebugLogger.instance.error('selectSession failed: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Send a message with optional model/provider and auto-continue logic
  Future<void> sendMessage(String input, {String? model, String? provider}) async {
    final server = _serverProvider.activeServer;
    if (server == null || input.trim().isEmpty) return;

    _isSending = true;
    _error = null;
    notifyListeners();

    // Append auto-continue suffix if enabled
    String finalInput = input.trim();
    if (_autoContinueEnabled) {
      finalInput = '$finalInput\n$_autoContinuePrompt';
    }

    // Add user message immediately
    final userMessage = ChatMessage(role: 'user', content: input.trim());
    _currentMessages.add(userMessage);
    _saveUserPrompts([userMessage]);
    notifyListeners();

    try {
      String content = '';
      String? newSessionId;
      
      if (_globalConfigProvider.isProxyMode) {
        final proxyClient = _serverProvider.getProxyClient(server);
        if (proxyClient != null) {
          await proxyClient.connect();
          final body = {
            'input': finalInput,
            'profile': server.profile,
            if (_currentSessionId != null) 'session_id': _currentSessionId,
            if (model != null) 'model': model,
            if (provider != null) 'provider': provider,
          };
          final result = await proxyClient.sendRequest(
            serverId: _globalConfigProvider.config.proxyUrl,
            method: 'POST',
            path: '/api/studio/chat-run/runs',
            headers: {'Content-Type': 'application/json'},
            body: body.toString().codeUnits,
          );
          if (result['status_code'] == 200) {
            final respBody = result['body'] as Map<String, dynamic>;
            content = respBody['output'] as String? ?? respBody['content'] as String? ?? '';
            newSessionId = respBody['session_id'] as String?;
          } else {
            content = 'Error: HTTP ${result['status_code']}';
          }
        }
      } else {
        final client = _serverProvider.getClient(server);
        final result = await client.runChat(
          input: finalInput,
          sessionId: _currentSessionId,
          model: model,
          provider: provider,
        );
        content = result.content;
        newSessionId = result.sessionId;
      }

      _currentMessages.add(ChatMessage(
        role: 'assistant',
        content: content,
      ));
      
      // Track session activity
      if (_currentSessionId != null) {
        _sessionActivity[_currentSessionId!] = DateTime.now();
      }
      
      // Update session ID if this was a new session
      if (_currentSessionId == null && newSessionId != null) {
        _currentSessionId = newSessionId;
      }
      // Reload sessions list to show new session
      await loadSessions();

      // Auto-continue logic: check response for OK/DONE
      if (_autoContinueEnabled) {
        _handleAutoContinueResponse(content);
      }
    } catch (e) {
      _currentMessages.add(ChatMessage(
        role: 'assistant',
        content: 'Error: $e',
        isError: true,
      ));
      _error = e.toString();
    }

    _isSending = false;
    notifyListeners();
  }

  /// Handle auto-continue response detection
  void _handleAutoContinueResponse(String content) {
    final trimmed = content.trim();
    
    // Check for DONE first (takes priority)
    if (trimmed.contains('DONE')) {
      _autoContinueDoneCount++;
      DebugLogger.instance.info('Auto-continue', 'DONE detected ($_autoContinueDoneCount/3)');
      
      if (_autoContinueDoneCount >= 3) {
        // 3 consecutive DONEs - exit auto-continue mode
        DebugLogger.instance.success('Auto-continue: 3 DONEs received, exiting mode');
        _autoContinueEnabled = false;
        _autoContinueDoneCount = 0;
        return;
      }
    } else if (trimmed.contains('OK')) {
      // OK resets DONE count (intermediate response)
      _autoContinueDoneCount = 0;
      DebugLogger.instance.info('Auto-continue', 'OK detected, resetting DONE count');
    }
    
    // If auto-continue still enabled and we got OK (or non-DONE response), send follow-up
    if (_autoContinueEnabled && !trimmed.contains('DONE')) {
      DebugLogger.instance.info('Auto-continue', 'Sending follow-up message');
      // Use a small delay to avoid overwhelming the server
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_autoContinueEnabled) {
          sendMessage(_autoContinueFollowUp);
        }
      });
    }
  }

  /// Start a new chat session
  void newSession() {
    _currentSessionId = null;
    _currentMessages = [];
    _error = null;
    notifyListeners();
  }

  /// Load available model groups from the server
  Future<void> loadModelGroups() async {
    final server = _serverProvider.activeServer;
    if (server == null) return;

    _isLoadingModels = true;
    notifyListeners();

    try {
      final client = _serverProvider.getClient(server);
      final groups = await client.fetchModelGroups();
      _modelGroups = groups;
      if (groups.isNotEmpty && _selectedModel == null) {
        // Auto-select first model from first group
        final firstGroup = groups.first;
        if (firstGroup.models.isNotEmpty) {
          _selectedModel = firstGroup.models.first.id;
          _selectedProvider = firstGroup.providerKey;
        }
      }
      DebugLogger.instance.success('Loaded ${groups.length} model groups');
    } catch (e) {
      DebugLogger.instance.error('Failed to load model groups', e.toString());
    }

    _isLoadingModels = false;
    notifyListeners();
  }

  /// Set selected model
  void selectModel(String modelId, String providerKey) {
    _selectedModel = modelId;
    _selectedProvider = providerKey;
    notifyListeners();
  }

  /// Delete a session
  Future<void> deleteSession(String sessionId) async {
    final server = _serverProvider.activeServer;
    if (server == null) return;

    if (_globalConfigProvider.isProxyMode) {
      final proxyClient = _serverProvider.getProxyClient(server);
      if (proxyClient != null) {
        await proxyClient.connect();
        await proxyClient.sendRequest(
          serverId: _globalConfigProvider.config.proxyUrl,
          method: 'DELETE',
          path: '/api/studio/sessions/$sessionId',
        );
      }
    } else {
      final client = _serverProvider.getClient(server);
      await client.deleteSession(sessionId);
    }

    if (_currentSessionId == sessionId) {
      newSession();
    }
    await loadSessions();
  }

  /// Rename a session
  Future<void> renameSession(String sessionId, String title) async {
    final server = _serverProvider.activeServer;
    if (server == null) return;

    if (_globalConfigProvider.isProxyMode) {
      final proxyClient = _serverProvider.getProxyClient(server);
      if (proxyClient != null) {
        await proxyClient.connect();
        await proxyClient.sendRequest(
          serverId: _globalConfigProvider.config.proxyUrl,
          method: 'POST',
          path: '/api/studio/sessions/$sessionId/rename',
          headers: {'Content-Type': 'application/json'},
          body: {'title': title}.toString().codeUnits,
        );
      }
    } else {
      final client = _serverProvider.getClient(server);
      await client.renameSession(sessionId, title);
    }
    await loadSessions();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Toggle auto-continue mode
  void toggleAutoContinue() {
    _autoContinueEnabled = !_autoContinueEnabled;
    _autoContinueDoneCount = 0;
    notifyListeners();
  }

  /// Disable auto-continue mode
  void disableAutoContinue() {
    _autoContinueEnabled = false;
    _autoContinueDoneCount = 0;
    notifyListeners();
  }
}
