import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/server_provider.dart';
import '../providers/global_config_provider.dart';
import '../l10n/app_localizations.dart';

/// Screen for adding or editing a server configuration
class ServerConfigScreen extends StatefulWidget {
  final ServerConfig? server;

  const ServerConfigScreen({super.key, this.server});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _profileController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _useAuth = false;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  // Proxy mode - fetch servers from proxy
  bool _isFetchingServers = false;
  List<Map<String, dynamic>> _fetchedServers = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.server?.name ?? '');
    _urlController = TextEditingController(text: widget.server?.url ?? '');
    _profileController = TextEditingController(text: widget.server?.profile ?? 'default');
    _usernameController = TextEditingController(text: widget.server?.username ?? '');
    _passwordController = TextEditingController(text: widget.server?.password ?? '');
    _useAuth = widget.server?.useAuth ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _profileController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final globalConfig = context.watch<GlobalConfigProvider>();
    final isProxyMode = globalConfig.isProxyMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.server == null ? AppLocalizations.of(context).addServer : AppLocalizations.of(context).editServer),
        actions: [
          TextButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(AppLocalizations.of(context).test),
          ),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Test result banner
              if (_testResult != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testSuccess
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _testSuccess ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testSuccess ? Icons.check_circle : Icons.error,
                        color: _testSuccess ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testSuccess ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Mode indicator
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isProxyMode
                      ? Colors.purple.withValues(alpha: 0.05)
                      : Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isProxyMode
                        ? Colors.purple.withValues(alpha: 0.2)
                        : Colors.blue.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isProxyMode ? Icons.hub : Icons.dns,
                      size: 18,
                      color: isProxyMode ? Colors.purple : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isProxyMode
                            ? AppLocalizations.of(context).proxyModeHint
                            : AppLocalizations.of(context).standaloneModeHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: isProxyMode ? Colors.purple[700] : Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Server name
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).serverName,
                  hintText: AppLocalizations.of(context).serverNameHint,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppLocalizations.of(context).enterServerName;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Server URL
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).serverUrl,
                  hintText: 'http://192.168.1.100:3000',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppLocalizations.of(context).enterServerUrl;
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                    return AppLocalizations.of(context).enterValidUrl;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Profile
              TextFormField(
                controller: _profileController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).profile,
                  hintText: 'default',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                  helperText: AppLocalizations.of(context).profileHelper,
                ),
              ),
              const SizedBox(height: 16),
              // Authentication section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lock),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context).useAuth,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          Switch(
                            value: _useAuth,
                            onChanged: (value) => setState(() => _useAuth = value),
                          ),
                        ],
                      ),
                      if (_useAuth) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context).username,
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.account_circle),
                          ),
                          validator: _useAuth
                              ? (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return AppLocalizations.of(context).enterUsername;
                                  }
                                  return null;
                                }
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context).password,
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.password),
                          ),
                          obscureText: true,
                          validator: _useAuth
                              ? (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return AppLocalizations.of(context).enterPassword;
                                  }
                                  return null;
                                }
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Proxy mode: fetch servers from proxy
              if (isProxyMode) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_download),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context).fetchFromProxy,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context).selectProxyServer,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _isFetchingServers ? null : _fetchServersFromProxy,
                          icon: _isFetchingServers
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(AppLocalizations.of(context).refreshServerList),
                        ),
                        if (_fetchedServers.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context).availableServers(_fetchedServers.length),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                ..._fetchedServers.map((s) => ListTile(
                                  dense: true,
                                  title: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13)),
                                  subtitle: Text(s['url'] ?? '', style: const TextStyle(fontSize: 11)),
                                  trailing: Text(
                                    s['enabled'] == true ? AppLocalizations.of(context).enabled : AppLocalizations.of(context).disabled,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: s['enabled'] == true ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _nameController.text = s['name'] ?? '';
                                      _urlController.text = s['url'] ?? '';
                                      _profileController.text = s['profile'] ?? 'default';
                                      _usernameController.text = s['username'] ?? '';
                                      _passwordController.text = s['password'] ?? '';
                                      _useAuth = (s['username'] ?? '').toString().isNotEmpty;
                                    });
                                  },
                                )),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Connection info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context).connectionInfo,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(AppLocalizations.of(context).supportedEndpoints),
                    const SizedBox(height: 4),
                    Text(
                      '  • /health - Health check\n'
                      '  • /api/auth/login - Authentication\n'
                      '  • /api/studio/sessions - Session management\n'
                      '  • /api/studio/chat-run/runs - Chat execution',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (isProxyMode) ...[
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).proxyConnectionInfo,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchServersFromProxy() async {
    final globalConfig = context.read<GlobalConfigProvider>();
    
    setState(() {
      _isFetchingServers = true;
      _fetchedServers = [];
    });

    try {
      final servers = await globalConfig.fetchServersFromProxy();
      setState(() {
        _fetchedServers = servers;
        _isFetchingServers = false;
      });
    } catch (e) {
      setState(() {
        _isFetchingServers = false;
        _testResult = AppLocalizations.of(context).proxyFetchFailed;
        _testSuccess = false;
      });
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final config = ServerConfig(
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      profile: _profileController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      useAuth: _useAuth,
    );

    final provider = context.read<ServerProvider>();
    final health = await provider.checkServerHealth(config);

    setState(() {
      _isTesting = false;
      if (health.healthy) {
        _testSuccess = true;
        _testResult = AppLocalizations.of(context).connectionTestSuccess;
      } else {
        _testSuccess = false;
        _testResult = AppLocalizations.of(context).connectionTestFailed;
      }
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final config = ServerConfig(
      id: widget.server?.id,
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      profile: _profileController.text.trim().isEmpty ? 'default' : _profileController.text.trim(),
      username: _useAuth ? _usernameController.text.trim() : null,
      password: _useAuth ? _passwordController.text.trim() : null,
      useAuth: _useAuth,
      createdAt: widget.server?.createdAt,
    );

    final provider = context.read<ServerProvider>();
    if (widget.server == null) {
      provider.addServer(config);
    } else {
      provider.updateServer(config);
    }

    Navigator.pop(context);
  }
}
