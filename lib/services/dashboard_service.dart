import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/task_models.dart';
import '../providers/server_provider.dart' show ServerProvider, IterableExtension;
import '../providers/pipeline_provider.dart';
import '../providers/debug_logger.dart';

/// 仪表板数据 Provider
class DashboardProvider extends ChangeNotifier {
  final ServerProvider serverProvider;
  final PipelineProvider pipelineProvider;

  Timer? _refreshTimer;
  bool _isRefreshing = false;
  
  // 统计数据
  int _totalTasks = 0;
  int _completedTasks = 0;
  int _failedTasks = 0;
  int _runningTasks = 0;
  double _overallProgress = 0.0;
  List<Task> _recentTasks = [];
  Map<String, int> _serverTaskDistribution = {};

  DashboardProvider({
    required this.serverProvider,
    required this.pipelineProvider,
  }) {
    // 每 5 秒自动刷新
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    refresh();
  }

  // Getters
  int get totalTasks => _totalTasks;
  int get completedTasks => _completedTasks;
  int get failedTasks => _failedTasks;
  int get runningTasks => _runningTasks;
  double get overallProgress => _overallProgress;
  List<Task> get recentTasks => List.unmodifiable(_recentTasks);
  Map<String, int> get serverTaskDistribution => Map.unmodifiable(_serverTaskDistribution);
  bool get isRefreshing => _isRefreshing;

  int get onlineServerCount => serverProvider.onlineServers.length;
  int get totalServerCount => serverProvider.servers.length;

  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    
    try {
      // 聚合所有项目的任务
      final allTasks = <Task>[];
      for (final project in pipelineProvider.projects) {
        for (final pipeline in project.pipelines) {
          allTasks.addAll(pipeline.allTasks);
        }
      }

      _totalTasks = allTasks.length;
      _completedTasks = allTasks.where((t) => t.status == TaskStatus.completed).length;
      _failedTasks = allTasks.where((t) => t.status == TaskStatus.failed).length;
      _runningTasks = allTasks.where((t) => t.status == TaskStatus.running).length;
      _overallProgress = _totalTasks > 0 ? _completedTasks / _totalTasks : 0.0;

      // 最近任务（按时间倒序）
      final sortedTasks = List<Task>.from(allTasks);
      sortedTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _recentTasks = sortedTasks.take(10).toList();

      // 服务器任务分布
      _serverTaskDistribution = {};
      for (final task in allTasks) {
        if (task.serverId != null) {
          _serverTaskDistribution[task.serverId!] = 
              (_serverTaskDistribution[task.serverId!] ?? 0) + 1;
        }
      }
    } catch (e) {
      DebugLogger.instance.error('Dashboard: 刷新失败', e.toString());
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// 获取服务器名称
  String getServerName(String? serverId) {
    if (serverId == null) return '未分配';
    final server = serverProvider.servers.where((s) => s.id == serverId).firstOrNull;
    return server?.name ?? '未知';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

/// 任务调度器
class TaskScheduler extends ChangeNotifier {
  final PipelineProvider pipelineProvider;
  Timer? _schedulerTimer;
  final List<ScheduledTask> _scheduledTasks = [];

  TaskScheduler(this.pipelineProvider) {
    _schedulerTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkSchedules());
  }

  List<ScheduledTask> get scheduledTasks => List.unmodifiable(_scheduledTasks);

  /// 添加定时任务
  void addScheduledTask({
    required String name,
    required String pipelineId,
    required ScheduleType type,
    required DateTime startTime,
    Duration? interval,
    Map<String, dynamic>? params,
  }) {
    final task = ScheduledTask(
      name: name,
      pipelineId: pipelineId,
      type: type,
      startTime: startTime,
      interval: interval,
      params: params ?? {},
    );
    _scheduledTasks.add(task);
    DebugLogger.instance.info('Scheduler: 添加定时任务 "$name"');
    notifyListeners();
  }

  /// 移除定时任务
  void removeScheduledTask(String taskId) {
    _scheduledTasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  /// 检查并执行到期的任务
  void _checkSchedules() {
    final now = DateTime.now();
    for (final task in _scheduledTasks) {
      if (task.shouldExecute(now)) {
        _executeScheduledTask(task);
        task.lastExecuted = now;
        if (task.type == ScheduleType.once) {
          task.isEnabled = false;
        }
      }
    }
  }

  Future<void> _executeScheduledTask(ScheduledTask task) async {
    DebugLogger.instance.info('Scheduler: 执行定时任务 "${task.name}"');
    // 触发流水线执行
    pipelineProvider.setActivePipeline(task.pipelineId);
    await pipelineProvider.executePipeline();
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    super.dispose();
  }
}

/// 定时任务
class ScheduledTask {
  final String id;
  String name;
  String pipelineId;
  ScheduleType type;
  DateTime startTime;
  Duration? interval;
  Map<String, dynamic> params;
  bool isEnabled;
  DateTime? lastExecuted;

  ScheduledTask({
    String? id,
    required this.name,
    required this.pipelineId,
    required this.type,
    required this.startTime,
    this.interval,
    this.params = const {},
    this.isEnabled = true,
    this.lastExecuted,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  bool shouldExecute(DateTime now) {
    if (!isEnabled) return false;
    if (now.isBefore(startTime)) return false;
    
    if (lastExecuted == null) return true;
    if (interval == null) return false;
    
    return now.difference(lastExecuted!) >= interval!;
  }
}

enum ScheduleType {
  once('一次'),
  daily('每天'),
  weekly('每周'),
  interval('间隔');

  const ScheduleType(this.label);
  final String label;
}

/// 通知系统
class NotificationService extends ChangeNotifier {
  final List<AppNotification> _notifications = [];
  int _unreadCount = 0;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;

  void addNotification({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
  }) {
    final notification = AppNotification(
      title: title,
      message: message,
      type: type,
    );
    _notifications.insert(0, notification);
    _unreadCount++;
    
    // 限制通知数量
    if (_notifications.length > 100) {
      _notifications.removeLast();
    }
    
    notifyListeners();
  }

  void markAsRead(String notificationId) {
    final notification = _notifications.where((n) => n.id == notificationId).firstOrNull;
    if (notification != null && !notification.isRead) {
      notification.isRead = true;
      _unreadCount--;
      notifyListeners();
    }
  }

  void markAllAsRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    _unreadCount = 0;
    notifyListeners();
  }

  void clearAll() {
    _notifications.clear();
    _unreadCount = 0;
    notifyListeners();
  }
}

class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    String? id,
    required this.title,
    required this.message,
    required this.type,
    DateTime? timestamp,
    this.isRead = false,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();
}

enum NotificationType {
  info,
  success,
  warning,
  error,
}


