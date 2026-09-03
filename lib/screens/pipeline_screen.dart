import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pipeline_provider.dart';
import '../models/task_models.dart';

/// Pipeline management screen
class PipelineScreen extends StatefulWidget {
  const PipelineScreen({super.key});

  @override
  State<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends State<PipelineScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    context.watch<PipelineProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('协同工作'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildTabButton(0, '项目', Icons.folder),
                const SizedBox(width: 8),
                _buildTabButton(1, '流水线', Icons.account_tree),
                const SizedBox(width: 8),
                _buildTabButton(2, '执行', Icons.play_circle),
                const SizedBox(width: 8),
                _buildTabButton(3, '日志', Icons.article),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: const [
          _ProjectsTab(),
          _PipelinesTab(),
          _ExecutionTab(),
          _LogsTab(),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return TextButton.icon(
      onPressed: () => setState(() => _selectedTab = index),
      icon: Icon(
        icon,
        size: 16,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
    );
  }
}

/// Projects tab
class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab();

  @override
  Widget build(BuildContext context) {
    final pipelineProvider = context.watch<PipelineProvider>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () => _showCreateProjectDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('新建项目'),
              ),
            ],
          ),
        ),
        Expanded(
          child: pipelineProvider.projects.isEmpty
              ? const Center(child: Text('暂无项目，点击上方按钮创建'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: pipelineProvider.projects.length,
                  itemBuilder: (context, index) {
                    final project = pipelineProvider.projects[index];
                    return _ProjectCard(project: project);
                  },
                ),
        ),
      ],
    );
  }

  void _showCreateProjectDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final repoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建项目'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '项目名称',
                  hintText: '输入项目名称',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '项目描述',
                  hintText: '输入项目描述',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: repoController,
                decoration: const InputDecoration(
                  labelText: '仓库地址（可选）',
                  hintText: 'https://github.com/...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                context.read<PipelineProvider>().createProject(
                      name: nameController.text,
                      description: descController.text,
                      repoUrl: repoController.text,
                    );
                Navigator.pop(context);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;

  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final pipelineProvider = context.watch<PipelineProvider>();
    final isActive = pipelineProvider.activeProject?.id == project.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isActive
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: Icon(
          Icons.folder,
          color: isActive ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          project.name,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : null,
          ),
        ),
        subtitle: Text(project.description.isEmpty ? '无描述' : project.description),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${project.pipelines.length} 流水线'),
            const SizedBox(width: 8),
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'select', child: Text('选择')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
              onSelected: (value) {
                if (value == 'select') {
                  pipelineProvider.setActiveProject(project.id);
                } else if (value == 'delete') {
                  pipelineProvider.deleteProject(project.id);
                }
              },
            ),
          ],
        ),
        onTap: () => pipelineProvider.setActiveProject(project.id),
      ),
    );
  }
}

/// Pipelines tab
class _PipelinesTab extends StatelessWidget {
  const _PipelinesTab();

  @override
  Widget build(BuildContext context) {
    final pipelineProvider = context.watch<PipelineProvider>();

    if (pipelineProvider.activeProject == null) {
      return const Center(child: Text('请先选择一个项目'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () => _showCreatePipelineDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('智能创建'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showTemplateDialog(context),
                icon: const Icon(Icons.dashboard_customize),
                label: const Text('从模板'),
              ),
            ],
          ),
        ),
        Expanded(
          child: pipelineProvider.pipelines.isEmpty
              ? const Center(child: Text('暂无流水线，点击上方按钮创建'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: pipelineProvider.pipelines.length,
                  itemBuilder: (context, index) {
                    final pipeline = pipelineProvider.pipelines[index];
                    return _PipelineCard(pipeline: pipeline);
                  },
                ),
        ),
      ],
    );
  }

  void _showCreatePipelineDialog(BuildContext context) {
    final nameController = TextEditingController();
    final reqController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('智能创建流水线'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '流水线名称',
                  hintText: '输入流水线名称',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reqController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '项目需求（每行一个）',
                  hintText: '输入项目需求，每行一条',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                final requirements = reqController.text
                    .split('\n')
                    .where((r) => r.trim().isNotEmpty)
                    .toList();
                context.read<PipelineProvider>().createPipelineFromAnalysis(
                      name: nameController.text,
                      requirements: requirements,
                    );
                Navigator.pop(context);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showTemplateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择模板'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TemplateTile(
                name: '全栈项目开发',
                description: '完整的全栈项目开发流水线',
                icon: Icons.web,
                onTap: () {
                  context.read<PipelineProvider>().createPipelineFromTemplate(
                        templateName: 'full_stack',
                      );
                  Navigator.pop(context);
                },
              ),
              _TemplateTile(
                name: 'CI/CD 流水线',
                description: '持续集成与部署',
                icon: Icons.sync,
                onTap: () {
                  context.read<PipelineProvider>().createPipelineFromTemplate(
                        templateName: 'ci_cd',
                      );
                  Navigator.pop(context);
                },
              ),
              _TemplateTile(
                name: '代码审查',
                description: '自动化代码审查',
                icon: Icons.rate_review,
                onTap: () {
                  context.read<PipelineProvider>().createPipelineFromTemplate(
                        templateName: 'code_review',
                      );
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  final String name;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  const _TemplateTile({
    required this.name,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(name),
      subtitle: Text(description),
      onTap: onTap,
    );
  }
}

class _PipelineCard extends StatelessWidget {
  final Pipeline pipeline;

  const _PipelineCard({required this.pipeline});

  @override
  Widget build(BuildContext context) {
    final pipelineProvider = context.watch<PipelineProvider>();
    final isActive = pipelineProvider.activePipeline?.id == pipeline.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isActive
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ExpansionTile(
        leading: Icon(
          Icons.account_tree,
          color: isActive ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          pipeline.name,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : null,
          ),
        ),
        subtitle: Row(
          children: [
            _StatusChip(status: pipeline.status.label, color: _getStatusColor(pipeline.status)),
            const SizedBox(width: 4),
            _StatusChip(status: pipeline.mode.label, color: Colors.blueGrey),
            const SizedBox(width: 4),
            Text('${pipeline.stages.length} 阶段/${pipeline.totalTaskCount} 任务'),
          ],
        ),
        children: [
          ...pipeline.stages.map((stage) => _StageTile(stage: stage)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => pipelineProvider.setActivePipeline(pipeline.id),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('选择'),
                ),
                TextButton.icon(
                  onPressed: () {
                    final newMode = pipeline.mode == PipelineMode.sequential
                        ? PipelineMode.parallel
                        : PipelineMode.sequential;
                    pipelineProvider.setPipelineMode(pipeline.id, newMode);
                  },
                  icon: Icon(
                    pipeline.mode == PipelineMode.sequential
                        ? Icons.more_horiz
                        : Icons.more_vert,
                    size: 16,
                  ),
                  label: Text(pipeline.mode == PipelineMode.sequential ? '切并行' : '切串行'),
                ),
                TextButton.icon(
                  onPressed: () => pipelineProvider.deletePipeline(pipeline.id),
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(PipelineStatus status) {
    switch (status) {
      case PipelineStatus.completed:
        return Colors.green;
      case PipelineStatus.running:
        return Colors.blue;
      case PipelineStatus.failed:
        return Colors.red;
      case PipelineStatus.paused:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  final Stage stage;

  const _StageTile({required this.stage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, right: 16, bottom: 4),
      child: ExpansionTile(
        leading: const Icon(Icons.layers, size: 18),
        title: Text(stage.name, style: const TextStyle(fontSize: 14)),
        subtitle: Text('${stage.tasks.length} 任务'),
        children: [
          ...stage.tasks.map((task) => Padding(
                padding: const EdgeInsets.only(left: 48, right: 16, bottom: 4),
                child: ListTile(
                  dense: true,
                  leading: Icon(_getTaskIcon(task.type), size: 16),
                  title: Text(task.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(task.type.label),
                  trailing: _StatusChip(
                    status: task.status.label,
                    color: _getTaskStatusColor(task.status),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  IconData _getTaskIcon(TaskType type) {
    switch (type) {
      case TaskType.code:
        return Icons.code;
      case TaskType.test:
        return Icons.bug_report;
      case TaskType.build:
        return Icons.build;
      case TaskType.deploy:
        return Icons.rocket_launch;
      case TaskType.review:
        return Icons.rate_review;
      case TaskType.doc:
        return Icons.description;
      case TaskType.analysis:
        return Icons.analytics;
      case TaskType.sync:
        return Icons.sync;
    }
  }

  Color _getTaskStatusColor(TaskStatus status) {
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

/// Execution tab
class _ExecutionTab extends StatelessWidget {
  const _ExecutionTab();

  @override
  Widget build(BuildContext context) {
    final pipelineProvider = context.watch<PipelineProvider>();

    if (pipelineProvider.activePipeline == null) {
      return const Center(child: Text('请先选择一条流水线'));
    }

    final pipeline = pipelineProvider.activePipeline!;

    return Column(
      children: [
        // Control bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Text(
                pipeline.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (!pipelineProvider.isRunning && !pipelineProvider.isPaused)
                FilledButton.icon(
                  onPressed: pipelineProvider.executePipeline,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('执行'),
                ),
              if (pipelineProvider.isRunning && !pipelineProvider.isPaused)
                FilledButton.icon(
                  onPressed: pipelineProvider.pausePipeline,
                  icon: const Icon(Icons.pause),
                  label: const Text('暂停'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                ),
              if (pipelineProvider.isPaused)
                FilledButton.icon(
                  onPressed: pipelineProvider.resumePipeline,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('恢复'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              if (pipelineProvider.isRunning || pipelineProvider.isPaused) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: pipelineProvider.cancelPipeline,
                  icon: const Icon(Icons.stop),
                  label: const Text('取消'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                onPressed: pipelineProvider.resetPipeline,
                icon: const Icon(Icons.refresh),
                tooltip: '重置',
              ),
            ],
          ),
        ),
        // Progress bar
        if (pipelineProvider.isRunning || pipelineProvider.isPaused)
          LinearProgressIndicator(
            value: pipeline.progress,
            minHeight: 4,
          ),
        // Pipeline visualization
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: pipeline.stages.length,
            itemBuilder: (context, index) {
              final stage = pipeline.stages[index];
              final isCurrent = index == pipeline.currentStageIndex && pipelineProvider.isRunning;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isCurrent
                      ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                      : BorderSide.none,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (isCurrent)
                            Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(right: 8),
                              child: const CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              stage.status == StageStatus.completed
                                  ? Icons.check_circle
                                  : stage.status == StageStatus.failed
                                      ? Icons.error
                                      : Icons.circle_outlined,
                              size: 18,
                              color: stage.status == StageStatus.completed
                                  ? Colors.green
                                  : stage.status == StageStatus.failed
                                      ? Colors.red
                                      : Colors.grey,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            stage.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: isCurrent ? FontWeight.bold : null,
                                ),
                          ),
                          const Spacer(),
                          Text(
                            '${stage.tasks.where((t) => t.status == TaskStatus.completed).length}/${stage.tasks.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    ...stage.tasks.map((task) => _TaskExecutionTile(task: task)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TaskExecutionTile extends StatelessWidget {
  final Task task;

  const _TaskExecutionTile({required this.task});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              _getStatusIcon(task.status),
              size: 16,
              color: _getStatusColor(task.status),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.name, style: const TextStyle(fontSize: 13)),
                  if (task.errorMessage != null)
                    Text(
                      task.errorMessage!,
                      style: const TextStyle(fontSize: 11, color: Colors.red),
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

/// Logs tab
class _LogsTab extends StatelessWidget {
  const _LogsTab();

  @override
  Widget build(BuildContext context) {
    final pipelineProvider = context.watch<PipelineProvider>();

    if (pipelineProvider.logs.isEmpty) {
      return const Center(child: Text('暂无日志'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pipelineProvider.logs.length,
      itemBuilder: (context, index) {
        final log = pipelineProvider.logs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              _getLogLevelIcon(log.level),
              color: _getLogLevelColor(log.level),
            ),
            title: Text(log.message),
            subtitle: Text(
              '${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
            ),
          ),
        );
      },
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
