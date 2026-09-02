import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/server_provider.dart';
import '../providers/global_config_provider.dart';
import '../providers/debug_logger.dart';
import '../models/models.dart';
import '../l10n/app_localizations.dart';
import 'server_config_screen.dart';
import 'chat_screen.dart';
import 'global_config_screen.dart';
import 'egg_page.dart';
import '../widgets/server_list_sidebar.dart';

/// Main application screen with server list and chat area
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    DebugLogger.instance.info('HomeScreen initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GlobalConfigProvider>().load();
      context.read<ServerProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.egg),
            tooltip: AppLocalizations.of(context).eggOfToday,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EggPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: AppLocalizations.of(context).settings,
            onPressed: () => _navigateToGlobalConfig(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).refreshServerList,
            onPressed: () {
              DebugLogger.instance.info('Refresh all servers');
              context.read<ServerProvider>().checkAllServers();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: AppLocalizations.of(context).addServer,
            onPressed: () => _navigateToAddServer(context),
          ),
          Consumer<DebugLogger>(
            builder: (context, logger, _) {
              return IconButton(
                icon: Icon(
                  Icons.bug_report,
                  color: logger.isVisible ? Colors.orange : null,
                ),
                tooltip: AppLocalizations.of(context).debugLog,
                onPressed: () {
                  logger.isVisible = !logger.isVisible;
                },
              );
            },
          ),
        ],
      ),
      body: Consumer2<ServerProvider, GlobalConfigProvider>(
        builder: (context, serverProvider, globalConfigProvider, _) {
          DebugLogger.instance.info(
            'HomeScreen build',
            'servers=${serverProvider.servers.length} active=${serverProvider.activeServer?.name} loading=${serverProvider.isLoading}',
          );
          if (serverProvider.isLoading && serverProvider.servers.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (serverProvider.servers.isEmpty) {
            return _buildEmptyState(context, globalConfigProvider);
          }

          return Row(
            children: [
              // Server sidebar
              SizedBox(
                width: 280,
                child: ServerListSidebar(
                  servers: serverProvider.servers,
                  activeServer: serverProvider.activeServer,
                  onServerSelected: (server) {
                    DebugLogger.instance.info(
                      'Server clicked',
                      'name=${server.name} url=${server.url} id=${server.id}',
                    );
                    serverProvider.setActiveServer(server);
                  },
                  onAddServer: () => _navigateToAddServer(context),
                  onEditServer: (server) => _navigateToEditServer(context, server),
                  onDeleteServer: (server) => _confirmDeleteServer(context, server),
                ),
              ),
              const VerticalDivider(width: 1),
              // Chat area
              Expanded(
                child: serverProvider.activeServer != null
                    ? ChatScreen(
                        key: ValueKey(serverProvider.activeServer!.id),
                        server: serverProvider.activeServer!,
                      )
                    : Center(child: Text(AppLocalizations.of(context).selectServerToChat)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, GlobalConfigProvider globalConfig) {
    final isProxy = globalConfig.isProxyMode;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).noServers,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isProxy
                ? AppLocalizations.of(context).fetchFromProxyHint
                : AppLocalizations.of(context).addServerHint,
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (isProxy)
            FilledButton.icon(
              onPressed: () {
                // TODO: fetch from proxy
              },
              icon: const Icon(Icons.cloud_download),
              label: Text(AppLocalizations.of(context).fetchFromProxy),
            )
          else
            FilledButton.icon(
              onPressed: () => _navigateToAddServer(context),
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context).addServer),
            ),
        ],
      ),
    );
  }

  void _navigateToAddServer(BuildContext context) {
    DebugLogger.instance.info('Navigate: Add Server');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ServerConfigScreen(),
      ),
    );
  }

  void _navigateToEditServer(BuildContext context, ServerConfig server) {
    DebugLogger.instance.info('Navigate: Edit Server', server.name);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServerConfigScreen(server: server),
      ),
    );
  }

  void _navigateToGlobalConfig(BuildContext context) {
    DebugLogger.instance.info('Navigate: Global Config');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GlobalConfigScreen(),
      ),
    );
  }

  void _confirmDeleteServer(BuildContext context, ServerConfig server) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteServer),
        content: Text(AppLocalizations.of(context).deleteServerConfirm(server.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              DebugLogger.instance.info('Delete server', server.name);
              context.read<ServerProvider>().removeServer(server.id);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );
  }
}
