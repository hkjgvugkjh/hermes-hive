import 'package:flutter/material.dart';
import '../models/models.dart';
import '../l10n/app_localizations.dart';

/// Sidebar showing all configured servers
class ServerListSidebar extends StatelessWidget {
  final List<ServerConfig> servers;
  final ServerConfig? activeServer;
  final ValueChanged<ServerConfig> onServerSelected;
  final VoidCallback onAddServer;
  final ValueChanged<ServerConfig> onEditServer;
  final ValueChanged<ServerConfig> onDeleteServer;

  const ServerListSidebar({
    super.key,
    required this.servers,
    required this.activeServer,
    required this.onServerSelected,
    required this.onAddServer,
    required this.onEditServer,
    required this.onDeleteServer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.dns, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).servers,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: onAddServer,
                  tooltip: AppLocalizations.of(context).addServer,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Server list
          Expanded(
            child: ListView.builder(
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                final isActive = activeServer?.id == server.id;
                return _ServerTile(
                  server: server,
                  isActive: isActive,
                  onTap: () => onServerSelected(server),
                  onEdit: () => onEditServer(server),
                  onDelete: () => onDeleteServer(server),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  final ServerConfig server;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServerTile({
    required this.server,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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
        title: Text(
          server.name,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          server.url,
          style: const TextStyle(fontSize: 11),
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 16),
          padding: EdgeInsets.zero,
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'edit', child: Text(AppLocalizations.of(context).edit)),
            PopupMenuItem(
              value: 'delete',
              child: Text(AppLocalizations.of(context).delete, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
