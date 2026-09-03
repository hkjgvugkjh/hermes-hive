import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/version_control_provider.dart';
import '../providers/server_provider.dart';

/// Version control screen
class VersionControlScreen extends StatefulWidget {
  const VersionControlScreen({super.key});

  @override
  State<VersionControlScreen> createState() => _VersionControlScreenState();
}

class _VersionControlScreenState extends State<VersionControlScreen> {
  final _repoPathController = TextEditingController(text: './repo');
  final _branchController = TextEditingController();
  final _commitMsgController = TextEditingController();

  @override
  void dispose() {
    _repoPathController.dispose();
    _branchController.dispose();
    _commitMsgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vcProvider = context.watch<VersionControlProvider>();
    final serverProvider = context.watch<ServerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('版本控制'),
      ),
      body: Row(
        children: [
          // Left panel - Server selection and repo config
          SizedBox(
            width: 300,
            child: Column(
              children: [
                // Server selection
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: '选择服务器',
                      border: OutlineInputBorder(),
                    ),
                    value: vcProvider.activeServerId,
                    items: serverProvider.servers
                        .where((s) => s.isOnline)
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        vcProvider.setActiveServer(value);
                      }
                    },
                  ),
                ),
                // Repo path
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _repoPathController,
                    decoration: const InputDecoration(
                      labelText: '仓库路径',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: vcProvider.setRepoPath,
                  ),
                ),
                const SizedBox(height: 16),
                // Git quick actions
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildSectionTitle('Git 操作'),
                      _buildActionTile(
                        icon: Icons.cloud_download,
                        title: '克隆仓库',
                        onTap: () => _showCloneDialog(context),
                      ),
                      _buildActionTile(
                        icon: Icons.sync,
                        title: 'Pull',
                        onTap: vcProvider.isBusy ? null : () => vcProvider.gitPull(),
                      ),
                      _buildActionTile(
                        icon: Icons.upload,
                        title: 'Push',
                        onTap: vcProvider.isBusy ? null : () => vcProvider.gitPush(),
                      ),
                      _buildActionTile(
                        icon: Icons.check,
                        title: 'Status',
                        onTap: vcProvider.isBusy ? null : () => vcProvider.gitStatus(),
                      ),
                      _buildActionTile(
                        icon: Icons.history,
                        title: 'Log',
                        onTap: vcProvider.isBusy ? null : () => vcProvider.gitLog(),
                      ),
                      const Divider(),
                      _buildSectionTitle('分支操作'),
                      _buildActionTile(
                        icon: Icons.call_split,
                        title: '检出分支',
                        onTap: vcProvider.isBusy ? null : () => _showCheckoutDialog(context),
                      ),
                      _buildActionTile(
                        icon: Icons.merge_type,
                        title: '合并分支',
                        onTap: vcProvider.isBusy ? null : () => _showMergeDialog(context),
                      ),
                      _buildActionTile(
                        icon: Icons.compare_arrows,
                        title: '冲突检测',
                        onTap: vcProvider.isBusy ? null : () => _showConflictDialog(context),
                      ),
                      const Divider(),
                      _buildSectionTitle('SVN 操作'),
                      _buildActionTile(
                        icon: Icons.cloud_download,
                        title: 'SVN 检出',
                        onTap: vcProvider.isBusy ? null : () => _showSvnCheckoutDialog(context),
                      ),
                      _buildActionTile(
                        icon: Icons.sync,
                        title: 'SVN 更新',
                        onTap: vcProvider.isBusy ? null : () => vcProvider.svnUpdate(),
                      ),
                      _buildActionTile(
                        icon: Icons.check,
                        title: 'SVN 状态',
                        onTap: vcProvider.isBusy ? null : () => vcProvider.svnStatus(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Right panel - Output logs
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '执行日志',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: vcProvider.clearLogs,
                        icon: const Icon(Icons.clear_all),
                        tooltip: '清除日志',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: vcProvider.logs.isEmpty
                      ? const Center(child: Text('暂无日志'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: vcProvider.logs.length,
                          itemBuilder: (context, index) {
                            final log = vcProvider.logs[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  _getLogLevelIcon(log.level),
                                  color: _getLogLevelColor(log.level),
                                ),
                                title: Text(log.message),
                                subtitle: log.output.isNotEmpty
                                    ? Text(
                                        log.output,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                      )
                                    : null,
                                trailing: Text(
                                  '${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title),
      dense: true,
      onTap: onTap,
      enabled: onTap != null,
    );
  }

  void _showCloneDialog(BuildContext context) {
    final urlController = TextEditingController();
    final dirController = TextEditingController(text: './repo');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('克隆仓库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: '仓库地址',
                hintText: 'https://github.com/...',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dirController,
              decoration: const InputDecoration(
                labelText: '目标目录',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (urlController.text.isNotEmpty) {
                context.read<VersionControlProvider>().gitClone(
                      urlController.text,
                      targetDir: dirController.text,
                    );
                Navigator.pop(context);
              }
            },
            child: const Text('克隆'),
          ),
        ],
      ),
    );
  }

  void _showCheckoutDialog(BuildContext context) {
    final branchController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('检出分支'),
        content: TextField(
          controller: branchController,
          decoration: const InputDecoration(
            labelText: '分支名',
            hintText: '输入分支名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (branchController.text.isNotEmpty) {
                context.read<VersionControlProvider>().gitCheckout(
                      branchController.text,
                      create: true,
                    );
                Navigator.pop(context);
              }
            },
            child: const Text('创建并检出'),
          ),
        ],
      ),
    );
  }

  void _showMergeDialog(BuildContext context) {
    final branchController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('合并分支'),
        content: TextField(
          controller: branchController,
          decoration: const InputDecoration(
            labelText: '源分支',
            hintText: '要合并的分支名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (branchController.text.isNotEmpty) {
                context.read<VersionControlProvider>().gitMerge(branchController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('合并'),
          ),
        ],
      ),
    );
  }

  void _showConflictDialog(BuildContext context) {
    final sourceController = TextEditingController();
    final targetController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('冲突检测'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: sourceController,
              decoration: const InputDecoration(
                labelText: '源分支',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetController,
              decoration: const InputDecoration(
                labelText: '目标分支',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (sourceController.text.isNotEmpty && targetController.text.isNotEmpty) {
                context.read<VersionControlProvider>().detectConflicts(
                      sourceController.text,
                      targetController.text,
                    );
                Navigator.pop(context);
              }
            },
            child: const Text('检测'),
          ),
        ],
      ),
    );
  }

  void _showSvnCheckoutDialog(BuildContext context) {
    final urlController = TextEditingController();
    final dirController = TextEditingController(text: './svn-repo');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SVN 检出'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'SVN 地址',
                hintText: 'https://svn.example.com/repo',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dirController,
              decoration: const InputDecoration(
                labelText: '目标目录',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (urlController.text.isNotEmpty) {
                context.read<VersionControlProvider>().svnCheckout(
                      urlController.text,
                      targetDir: dirController.text,
                    );
                Navigator.pop(context);
              }
            },
            child: const Text('检出'),
          ),
        ],
      ),
    );
  }

  IconData _getLogLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Icons.info;
      case LogLevel.success:
        return Icons.check_circle;
      case LogLevel.warn:
        return Icons.warning;
      case LogLevel.error:
        return Icons.error;
    }
  }

  Color _getLogLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.success:
        return Colors.green;
      case LogLevel.warn:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }
}
