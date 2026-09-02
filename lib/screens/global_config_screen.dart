import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/global_config_provider.dart';
import '../models/global_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';

/// Screen for configuring global connection mode
class GlobalConfigScreen extends StatefulWidget {
  const GlobalConfigScreen({super.key});

  @override
  State<GlobalConfigScreen> createState() => _GlobalConfigScreenState();
}

class _GlobalConfigScreenState extends State<GlobalConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _proxyUrlController;
  late TextEditingController _proxyAuthTokenController;
  ConnectionMode _mode = ConnectionMode.standalone;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<GlobalConfigProvider>().config;
    _mode = config.mode;
    _proxyUrlController = TextEditingController(text: config.proxyUrl);
    _proxyAuthTokenController = TextEditingController(text: config.proxyAuthToken);
  }

  @override
  void dispose() {
    _proxyUrlController.dispose();
    _proxyAuthTokenController.dispose();
    super.dispose();
  }

  String _getModeLabel(ConnectionMode mode) {
    switch (mode) {
      case ConnectionMode.hermesProxy:
        return AppLocalizations.of(context).hermesProxy;
      case ConnectionMode.standalone:
        return AppLocalizations.of(context).standaloneMode;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).globalConfiguration),
        actions: [
          TextButton.icon(
            onPressed: _isTesting ? null : _testProxyConnection,
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
              // Connection mode selector
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.hub),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context).connectionMode,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...ConnectionMode.values.map((mode) {
                        return RadioListTile<ConnectionMode>(
                          title: Text(_getModeLabel(mode)),
                          subtitle: Text(_getModeDescription(mode)),
                          value: mode,
                          groupValue: _mode,
                          onChanged: (value) {
                            setState(() {
                              _mode = value ?? ConnectionMode.standalone;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Hermes Proxy settings
              if (_mode == ConnectionMode.hermesProxy) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.router),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context).hermesProxy,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _proxyUrlController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context).proxyUrl,
                            hintText: 'https://proxy.example.com:8080',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.link),
                          ),
                          keyboardType: TextInputType.url,
                          validator: (value) {
                            if (_mode == ConnectionMode.hermesProxy) {
                              if (value == null || value.trim().isEmpty) {
                                return AppLocalizations.of(context).enterProxyUrl;
                              }
                              final uri = Uri.tryParse(value.trim());
                              if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                                return AppLocalizations.of(context).enterValidProxyUrl;
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _proxyAuthTokenController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context).proxyToken,
                            hintText: AppLocalizations.of(context).proxyTokenHint,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.key),
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (_mode == ConnectionMode.hermesProxy &&
                                (value == null || value.trim().isEmpty)) {
                              return AppLocalizations.of(context).adminTokenRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock, size: 16, color: Colors.green[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context).encryptionAlwaysEnabled,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Language selector
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.language),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context).language,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButton<Locale>(
                        value: context.watch<LocaleProvider>().locale,
                        isExpanded: true,
                        items: [
                          DropdownMenuItem<Locale>(
                            value: const Locale('zh', 'CN'),
                            child: Text(AppLocalizations.of(context).chinese),
                          ),
                          DropdownMenuItem<Locale>(
                            value: const Locale('en', 'US'),
                            child: Text(AppLocalizations.of(context).english),
                          ),
                        ],
                        onChanged: (locale) {
                          if (locale != null) {
                            context.read<LocaleProvider>().setLocale(locale);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Info text
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
                          AppLocalizations.of(context).modeDescription,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getDetailedDescription(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getModeDescription(ConnectionMode mode) {
    switch (mode) {
      case ConnectionMode.hermesProxy:
        return AppLocalizations.of(context).proxyModeDesc;
      case ConnectionMode.standalone:
        return AppLocalizations.of(context).standaloneModeDesc;
    }
  }

  String _getDetailedDescription() {
    switch (_mode) {
      case ConnectionMode.hermesProxy:
        return AppLocalizations.of(context).proxyModeInfo;
      case ConnectionMode.standalone:
        return AppLocalizations.of(context).standaloneModeInfo;
    }
  }

  Future<void> _testProxyConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final proxyUrl = _proxyUrlController.text.trim();
      final uri = Uri.parse(proxyUrl);

      // Simple HTTP check to admin API (always HTTPS)
      final adminUrl = 'https://${uri.host}:${uri.port}';

      final response = await http.get(
        Uri.parse('$adminUrl/api/config'),
        headers: _proxyAuthTokenController.text.trim().isNotEmpty
            ? {'Authorization': 'Bearer ${_proxyAuthTokenController.text.trim()}'}
            : {},
      ).timeout(const Duration(seconds: 10));

      setState(() {
        _isTesting = false;
        if (response.statusCode == 200) {
          _testSuccess = true;
          _testResult = AppLocalizations.of(context).connectionSuccess;
        } else if (response.statusCode == 401) {
          _testSuccess = false;
          _testResult = AppLocalizations.of(context).authFailed;
        } else {
          _testSuccess = false;
          _testResult = AppLocalizations.of(context).httpFailed(response.statusCode);
        }
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = AppLocalizations.of(context).connectionFailed(e.toString());
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<GlobalConfigProvider>();
    provider.updateConfig(GlobalConfig(
      mode: _mode,
      proxyUrl: _proxyUrlController.text.trim(),
      proxyAuthToken: _proxyAuthTokenController.text.trim(),
    ));

    Navigator.pop(context);
  }
}