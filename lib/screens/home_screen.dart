import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/server_provider.dart';
import '../providers/global_config_provider.dart';
import '../providers/debug_logger.dart';
import '../models/models.dart';
import '../l10n/app_localizations.dart';
import 'server_config_screen.dart';
import 'global_config_screen.dart';
import 'egg_page.dart';
import 'pipeline_screen.dart';
import 'version_control_screen.dart';
import 'dashboard_screen.dart';
import 'sessions_tab.dart';
import 'files_tab.dart';
import 'terminal_tab.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _sidebarExpanded = true;
  int _selectedTab = 0;
  late AnimationController _animationController;
  late Animation<double> _sidebarAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _sidebarAnimation = Tween<double>(begin: 280, end: 48).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    if (_sidebarExpanded) {
      _animationController.value = 0;
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GlobalConfigProvider>().load();
      context.read<ServerProvider>().load().then((_) {
        // Auto-refresh server health after loading
        context.read<ServerProvider>().checkAllServers();
      });
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarExpanded = !_sidebarExpanded;
      if (_sidebarExpanded) {
        _animationController.reverse();
      } else {
        _animationController.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Consumer2<ServerProvider, GlobalConfigProvider>(
        builder: (context, serverProvider, globalConfigProvider, _) {
          if (serverProvider.isLoading && serverProvider.servers.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (serverProvider.servers.isEmpty) {
            return _buildEmptyState(context, globalConfigProvider);
          }

          return Row(
            children: [
              // Animated sidebar
              AnimatedBuilder(
                animation: _sidebarAnimation,
                builder: (context, child) {
                  return SizedBox(
                    width: _sidebarAnimation.value,
                    child: _buildSidebar(serverProvider),
                  );
                },
              ),
              const VerticalDivider(width: 1),
              // Main content with tabs
              Expanded(
                child: Column(
                  children: [
                    _buildTabBar(),
                    Expanded(
                      child: serverProvider.activeServer != null
                          ? IndexedStack(
                              index: _selectedTab,
                              children: [
                                SessionsTab(server: serverProvider.activeServer!),
                                FilesTab(server: serverProvider.activeServer!),
                                TerminalTab(server: serverProvider.activeServer!),
                              ],
                            )
                          : Center(child: Text(AppLocalizations.of(context).selectServerToChat)),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(AppLocalizations.of(context).appTitle),
      actions: [
        IconButton(
          icon: const Icon(Icons.account_tree),
          tooltip: '协同工作',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PipelineScreen())),
        ),
        IconButton(
          icon: const Icon(Icons.dashboard),
          tooltip: '仪表板',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
        IconButton(
          icon: const Icon(Icons.source),
          tooltip: '版本控制',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VersionControlScreen())),
        ),
        IconButton(
          icon: const Icon(Icons.egg),
          tooltip: AppLocalizations.of(context).eggOfToday,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EggPage())),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: AppLocalizations.of(context).settings,
          onPressed: () => _navigateToGlobalConfig(context),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: AppLocalizations.of(context).refreshServerList,
          onPressed: () => context.read<ServerProvider>().checkAllServers(),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: AppLocalizations.of(context).addServer,
          onPressed: () => _navigateToAddServer(context),
        ),
        Consumer<DebugLogger>(
          builder: (context, logger, _) {
            return IconButton(
              icon: Icon(Icons.bug_report, color: logger.isVisible ? Colors.orange : null),
              tooltip: AppLocalizations.of(context).debugLog,
              onPressed: () => logger.isVisible = !logger.isVisible,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSidebar(ServerProvider serverProvider) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        children: [
          // Toggle button
          SizedBox(
            height: 40,
            child: _sidebarExpanded
                ? Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.dns, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('服务器', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 18),
                        onPressed: _toggleSidebar,
                        tooltip: '收起',
                      ),
                    ],
                  )
                : Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18),
                      onPressed: _toggleSidebar,
                      tooltip: '展开',
                    ),
                  ),
          ),
          const Divider(height: 1),
          // Server list
          Expanded(
            child: ListView.builder(
              itemCount: serverProvider.servers.length,
              itemBuilder: (context, index) {
                final server = serverProvider.servers[index];
                final isActive = serverProvider.activeServer?.id == server.id;
                return _buildServerTile(server, isActive, serverProvider);
              },
            ),
          ),
          if (_sidebarExpanded)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _navigateToAddServer(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServerTile(ServerConfig server, bool isActive, ServerProvider serverProvider) {
    if (_sidebarExpanded) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(
            server.isOnline ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: server.isOnline ? Colors.green : Colors.grey,
          ),
          title: Text(server.name, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, fontSize: 13), overflow: TextOverflow.ellipsis),
          subtitle: Text(server.url, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          onTap: () => serverProvider.setActiveServer(server),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16),
            padding: EdgeInsets.zero,
            onSelected: (value) {
              if (value == 'edit') {
                _navigateToEditServer(context, server);
              } else if (value == 'delete') {
                _confirmDeleteServer(context, server);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'edit', child: Text(AppLocalizations.of(context).edit)),
              PopupMenuItem(value: 'delete', child: Text(AppLocalizations.of(context).delete, style: const TextStyle(color: Colors.red))),
            ],
          ),
        ),
      );
    } else {
      return Tooltip(
        message: '${server.name}\n${server.url}',
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => serverProvider.setActiveServer(server),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActive ? Theme.of(context).colorScheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: server.isOnline ? Colors.green : Colors.grey.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  server.name.isNotEmpty ? server.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isActive ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          _buildTabButton(0, Icons.chat, '会话'),
          _buildTabButton(1, Icons.folder, '文件'),
          _buildTabButton(2, Icons.terminal, '终端'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isSelected ? Theme.of(context).colorScheme.primary : null),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ],
        ),
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
          Text(AppLocalizations.of(context).noServers, style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(isProxy ? AppLocalizations.of(context).fetchFromProxyHint : AppLocalizations.of(context).addServerHint, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          const SizedBox(height: 24),
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ServerConfigScreen()));
  }

  void _navigateToEditServer(BuildContext context, ServerConfig server) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ServerConfigScreen(server: server)));
  }

  void _navigateToGlobalConfig(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalConfigScreen()));
  }

  /// Opens the bookshelf for the currently active server.
  ///
  /// Picks the transport to match the global connection mode: through
  /// hermes-proxy when that mode is active, direct HTTP otherwise.
  void _confirmDeleteServer(BuildContext context, ServerConfig server) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteServer),
        content: Text(AppLocalizations.of(context).deleteServerConfirm(server.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context).cancel)),
          TextButton(
            onPressed: () {
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
