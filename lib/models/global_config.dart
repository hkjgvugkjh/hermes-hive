/// Global connection mode for hermes-hive
enum ConnectionMode {
  /// Connect through hermes-proxy (server list from proxy admin API)
  hermesProxy('Hermes Proxy'),
  
  /// Connect directly to Hermes Studio servers (manual configuration)
  standalone('Standalone');

  const ConnectionMode(this.label);
  final String label;
}

/// Global configuration for the application
class GlobalConfig {
  ConnectionMode mode;
  
  // Hermes-proxy mode settings
  String proxyUrl;       // e.g. https://proxy.example.com:8080
  String proxyAuthToken; // Admin token for proxy
  
  GlobalConfig({
    this.mode = ConnectionMode.standalone,
    this.proxyUrl = '',
    this.proxyAuthToken = '',
  });

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'proxyUrl': proxyUrl,
        'proxyAuthToken': proxyAuthToken,
      };

  factory GlobalConfig.fromJson(Map<String, dynamic> json) => GlobalConfig(
        mode: ConnectionMode.values.firstWhere(
          (e) => e.name == json['mode'],
          orElse: () => ConnectionMode.standalone,
        ),
        proxyUrl: json['proxyUrl'] as String? ?? '',
        proxyAuthToken: json['proxyAuthToken'] as String? ?? '',
      );

  GlobalConfig copyWith({
    ConnectionMode? mode,
    String? proxyUrl,
    String? proxyAuthToken,
  }) =>
      GlobalConfig(
        mode: mode ?? this.mode,
        proxyUrl: proxyUrl ?? this.proxyUrl,
        proxyAuthToken: proxyAuthToken ?? this.proxyAuthToken,
      );

  /// Build WebSocket URL for hermes-proxy (always encrypted with WSS)
  String get proxyWsUrl {
    if (mode != ConnectionMode.hermesProxy) return '';
    final uri = Uri.parse(proxyUrl);
    return 'wss://${uri.host}:${uri.port}/ws';
  }

  /// Get admin HTTP URL from proxy URL (always HTTPS)
  String get proxyAdminUrl {
    if (mode != ConnectionMode.hermesProxy) return '';
    final uri = Uri.parse(proxyUrl);
    return 'https://${uri.host}:${uri.port}';
  }
}
