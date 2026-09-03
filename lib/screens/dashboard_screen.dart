import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/dashboard_service.dart';
import '../models/task_models.dart';

/// Dashboard screen with stats, progress, and activity
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboardProvider = context.watch<DashboardProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('仪表板'),
        actions: [
          IconButton(
            onPressed: dashboardProvider.refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats cards row
            Row(
              children: [
                _buildStatCard(
                  context,
                  title: '在线服务器',
                  value: '${dashboardProvider.onlineServerCount}/${dashboardProvider.totalServerCount}',
                  icon: Icons.dns,
                  color: Colors.blue,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  context,
                  title: '总任务',
                  value: '${dashboardProvider.totalTasks}',
                  icon: Icons.task,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  context,
                  title: '进行中',
                  value: '${dashboardProvider.runningTasks}',
                  icon: Icons.play_circle,
                  color: Colors.orange,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  context,
                  title: '已完成',
                  value: '${dashboardProvider.completedTasks}',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Progress section
            Text(
              '整体进度',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${(dashboardProvider.overallProgress * 100).toStringAsFixed(1)}%'),
                        Text('${dashboardProvider.completedTasks}/${dashboardProvider.totalTasks} 完成'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: dashboardProvider.overallProgress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Two columns: Server distribution + Recent tasks
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Server task distribution
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '服务器任务分布',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          if (dashboardProvider.serverTaskDistribution.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: Text('暂无数据')),
                            )
                          else
                            ...dashboardProvider.serverTaskDistribution.entries.map((e) {
                              final serverName = dashboardProvider.getServerName(e.key);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.dns, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(serverName, style: const TextStyle(fontSize: 13))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${e.value}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Recent tasks
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '最近任务',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          if (dashboardProvider.recentTasks.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: Text('暂无任务')),
                            )
                          else
                            ...dashboardProvider.recentTasks.map((task) => _RecentTaskTile(task: task)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTaskTile extends StatelessWidget {
  final Task task;

  const _RecentTaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            _getStatusIcon(task.status),
            size: 16,
            color: _getStatusColor(task.status),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  task.type.label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Text(
            task.status.label,
            style: TextStyle(
              fontSize: 11,
              color: _getStatusColor(task.status),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Icons.circle_outlined;
      case TaskStatus.ready:
        return Icons.radio_button_unchecked;
      case TaskStatus.running:
        return Icons.play_circle;
      case TaskStatus.completed:
        return Icons.check_circle;
      case TaskStatus.failed:
        return Icons.error;
      case TaskStatus.retrying:
        return Icons.refresh;
      case TaskStatus.cancelled:
        return Icons.cancel;
      case TaskStatus.skipped:
        return Icons.skip_next;
    }
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.running:
        return Colors.blue;
      case TaskStatus.failed:
        return Colors.red;
      case TaskStatus.retrying:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
