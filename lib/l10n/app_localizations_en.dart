// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Hermes Hive';

  @override
  String get addServer => 'Add Server';

  @override
  String get editServer => 'Edit Server';

  @override
  String get deleteServer => 'Delete Server';

  @override
  String deleteServerConfirm(Object serverName) {
    return 'Are you sure you want to delete \"$serverName\"?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get test => 'Test';

  @override
  String get edit => 'Edit';

  @override
  String get fetchFromProxy => 'Fetch from Proxy';

  @override
  String get selectServerToChat => 'Select a server to start chatting';

  @override
  String get globalConfiguration => 'Global Configuration';

  @override
  String get refreshServerList => 'Refresh Server List';

  @override
  String get supportedEndpoints => 'Supported endpoints:';

  @override
  String get model => 'Model:';

  @override
  String get selectModel => 'Select model';

  @override
  String get clearAllPrompts => 'Clear All Prompts';

  @override
  String get clearAllPromptsConfirm =>
      'Are you sure you want to delete all saved prompts?';

  @override
  String get clear => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get loginRequired => 'Login Required';

  @override
  String loginPrompt(Object serverName) {
    return 'Please enter your credentials to access $serverName';
  }

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get login => 'Login';

  @override
  String get loggingIn => 'Logging in...';

  @override
  String get loginFailed => 'Login failed';

  @override
  String get thinking => 'Thinking...';

  @override
  String get typeMessage => 'Type a message...';

  @override
  String emptyResponses(Object count) {
    return '$count empty responses';
  }

  @override
  String get noSessions => 'No sessions';

  @override
  String get noMessages => 'No messages yet';

  @override
  String get debugLog => 'Debug Log';

  @override
  String get server => 'Server';

  @override
  String get proxy => 'Proxy';

  @override
  String get standalone => 'Standalone';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get chinese => '中文';

  @override
  String get encryptionAlwaysEnabled =>
      'Encryption is always enabled (X25519 + ChaCha20-Poly1305)';

  @override
  String get proxyUrl => 'Proxy URL';

  @override
  String get proxyToken => 'Proxy Token';

  @override
  String get connectionMode => 'Connection Mode';

  @override
  String get hermesProxy => 'Hermes Proxy';

  @override
  String get standaloneMode => 'Standalone Mode';

  @override
  String get serverName => 'Server Name';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get profile => 'Profile';

  @override
  String get useAuth => 'Use Auth';

  @override
  String get connectionTestSuccess => 'Connection test successful';

  @override
  String get connectionTestFailed => 'Connection test failed';

  @override
  String proxyFetchSuccess(Object count) {
    return 'Successfully fetched $count servers';
  }

  @override
  String get proxyFetchFailed => 'Failed to fetch servers from proxy';

  @override
  String get servers => 'Servers';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get send => 'Send';

  @override
  String get prompts => 'Prompts';

  @override
  String get savedPrompts => 'Saved Prompts';

  @override
  String get noPrompts => 'No saved prompts';

  @override
  String get clickToInsert => 'Click to insert';

  @override
  String get noServers => 'No servers configured';

  @override
  String get fetchFromProxyHint => 'Click \"Fetch from Proxy\" to load servers';

  @override
  String get addServerHint => 'Click + to add a Hermes Studio server';

  @override
  String get untitled => 'Untitled';

  @override
  String get proxyModeHint => 'Hermes Proxy Mode — Servers fetched from proxy';

  @override
  String get standaloneModeHint => 'Standalone Mode — Direct connection';

  @override
  String get serverNameHint => 'My Hermes Server';

  @override
  String get enterServerName => 'Please enter a server name';

  @override
  String get enterServerUrl => 'Please enter a server URL';

  @override
  String get enterValidUrl => 'Please enter a valid URL';

  @override
  String get profileHelper => 'Hermes profile to use for this server';

  @override
  String get enterUsername => 'Please enter a username';

  @override
  String get enterPassword => 'Please enter a password';

  @override
  String get selectProxyServer =>
      'Select a server from the proxy\'s server list';

  @override
  String availableServers(Object count) {
    return 'Available Servers ($count)';
  }

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get connectionInfo => 'Connection Info';

  @override
  String get proxyConnectionInfo =>
      'Hermes Proxy: WebSocket with X25519 key exchange\nStandalone: Direct HTTP/WebSocket connection';

  @override
  String get noPromptsHint =>
      'No saved prompts yet.\nUser messages will be auto-saved here.';

  @override
  String get sessionsList => 'Sessions';

  @override
  String get newSession => 'New session';

  @override
  String get startConversation => 'Start a conversation';

  @override
  String typeToBegin(Object serverName) {
    return 'Type a message below to begin chatting with $serverName';
  }

  @override
  String get enterProxyUrl => 'Please enter proxy URL';

  @override
  String get enterValidProxyUrl => 'Please enter a valid URL';

  @override
  String get proxyTokenHint => 'Proxy admin authentication token';

  @override
  String get adminTokenRequired =>
      'Admin token is required for hermes-proxy mode';

  @override
  String get modeDescription => 'Mode Description';

  @override
  String get proxyModeDesc =>
      'Connect through hermes-proxy, fetch server list from proxy';

  @override
  String get standaloneModeDesc =>
      'Directly connect to Hermes Studio servers, manually add servers';

  @override
  String get proxyModeInfo =>
      'Hermes Proxy mode:\n- Traffic encrypted with X25519 + ChaCha20-Poly1305\n- Server list fetched from proxy\n- Auth via proxy admin token';

  @override
  String get standaloneModeInfo =>
      'Standalone mode:\n- Direct HTTP/WebSocket connection\n- Manually add servers\n- Optional per-server auth';

  @override
  String get connectionSuccess => 'Connection successful! Proxy is reachable.';

  @override
  String get authFailed => 'Auth failed: Invalid admin token';

  @override
  String httpFailed(Object statusCode) {
    return 'Failed: HTTP $statusCode';
  }

  @override
  String connectionFailed(Object error) {
    return 'Connection failed: $error';
  }

  @override
  String get eggOfToday => 'Egg of Today';

  @override
  String get openRouterConfig => 'OpenRouter Config';

  @override
  String get refreshAll => 'Refresh All';

  @override
  String get apiUrl => 'API URL';

  @override
  String get apiKey => 'API Key';

  @override
  String get freeModels => 'Free Models';

  @override
  String get fetchModels => 'Fetch Models';

  @override
  String get noFreeModels => 'No free models. Configure API key and fetch.';

  @override
  String selectedCount(Object count) {
    return '$count selected';
  }

  @override
  String get createCombination => 'Create Combination';

  @override
  String get modelCombinations => 'Model Combinations';

  @override
  String get noCombinations =>
      'No combinations yet. Select models and create one.';

  @override
  String get checkAvailability => 'Check Availability';

  @override
  String get combinationName => 'Combination Name';

  @override
  String get combinationNameHint => 'e.g., My Free Stack';

  @override
  String get create => 'Create';

  @override
  String get deleteCombination => 'Delete Combination';

  @override
  String deleteCombinationConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get available => 'Available';

  @override
  String get unavailable => 'Unavailable';
}
