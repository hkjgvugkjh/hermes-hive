import 'package:flutter/foundation.dart';
import '../models/task_models.dart';

/// 结果聚合器 — 收集各子任务执行结果并合并输出
class ResultAggregator extends ChangeNotifier {
  /// 聚合策略
  final AggregationStrategy strategy;
  
  /// 聚合结果
  AggregationResult? _result;
  AggregationResult? get result => _result;

  ResultAggregator({this.strategy = AggregationStrategy.sequential});

  /// 聚合多个任务的结果
  AggregationResult aggregate(List<Task> tasks) {
    switch (strategy) {
      case AggregationStrategy.sequential:
        return _aggregateSequential(tasks);
      case AggregationStrategy.union:
        return _aggregateUnion(tasks);
      case AggregationStrategy.voting:
        return _aggregateVoting(tasks);
      case AggregationStrategy.best:
        return _aggregateBest(tasks);
    }
  }

  /// 顺序拼接：流水线模式，上一步输出作为下一步输入
  AggregationResult _aggregateSequential(List<Task> tasks) {
    final outputs = <String>[];
    bool allSuccess = true;
    
    for (final task in tasks) {
      if (task.status == TaskStatus.completed && task.outputArtifacts.isNotEmpty) {
        outputs.addAll(task.outputArtifacts);
      } else if (task.status == TaskStatus.failed) {
        allSuccess = false;
      }
    }

    _result = AggregationResult(
      success: allSuccess,
      outputs: outputs,
      message: allSuccess ? '所有任务顺序完成' : '部分任务失败',
    );
    notifyListeners();
    return _result!;
  }

  /// 并集合并：并行模式，合并所有结果
  AggregationResult _aggregateUnion(List<Task> tasks) {
    final outputs = <String>[];
    int successCount = 0;
    int failCount = 0;

    for (final task in tasks) {
      if (task.status == TaskStatus.completed) {
        outputs.addAll(task.outputArtifacts);
        successCount++;
      } else {
        failCount++;
      }
    }

    _result = AggregationResult(
      success: failCount == 0,
      outputs: outputs,
      message: '成功: $successCount, 失败: $failCount',
    );
    notifyListeners();
    return _result!;
  }

  /// 投票决策：冗余执行，多数表决
  AggregationResult _aggregateVoting(List<Task> tasks) {
    final outputs = <String>[];
    final voteMap = <String, int>{};

    // 统计每个输出结果的出现次数
    for (final task in tasks) {
      if (task.status == TaskStatus.completed && task.outputArtifacts.isNotEmpty) {
        for (final output in task.outputArtifacts) {
          voteMap[output] = (voteMap[output] ?? 0) + 1;
        }
      }
    }

    // 选择出现次数最多的结果
    if (voteMap.isNotEmpty) {
      final sorted = voteMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      outputs.add(sorted.first.key);
    }

    _result = AggregationResult(
      success: outputs.isNotEmpty,
      outputs: outputs,
      message: '投票完成，选择最高票结果',
    );
    notifyListeners();
    return _result!;
  }

  /// 最优选择：多方案执行，选择最佳结果
  AggregationResult _aggregateBest(List<Task> tasks) {
    // 简单实现：选择第一个成功的结果
    for (final task in tasks) {
      if (task.status == TaskStatus.completed && task.outputArtifacts.isNotEmpty) {
        _result = AggregationResult(
          success: true,
          outputs: task.outputArtifacts,
          message: '选择最佳结果来自任务: ${task.name}',
        );
        notifyListeners();
        return _result!;
      }
    }

    _result = AggregationResult(
      success: false,
      outputs: [],
      message: '没有成功的任务',
    );
    notifyListeners();
    return _result!;
  }
}

/// 聚合策略
enum AggregationStrategy {
  sequential('顺序拼接'),
  union('并集合并'),
  voting('投票决策'),
  best('最优选择');

  const AggregationStrategy(this.label);
  final String label;
}

/// 聚合结果
class AggregationResult {
  final bool success;
  final List<String> outputs;
  final String message;
  final DateTime timestamp;

  AggregationResult({
    required this.success,
    required this.outputs,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// 会话管理器 — 管理跨服务器的会话状态和上下文传递
class SessionManager extends ChangeNotifier {
  final Map<String, TaskSession> _sessions = {};
  final Map<String, DateTime> _lastActivity = {};

  /// 获取或创建任务会话
  TaskSession getOrCreateSession({
    required String taskId,
    required String serverId,
    String? sessionId,
  }) {
    final key = '${taskId}_$serverId';
    if (_sessions.containsKey(key)) {
      return _sessions[key]!;
    }

    final session = TaskSession(
      taskId: taskId,
      serverId: serverId,
      sessionId: sessionId,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
    );
    _sessions[key] = session;
    notifyListeners();
    return session;
  }

  /// 更新会话状态
  void updateSession(String taskId, String serverId, {
    TaskStatus? status,
    String? sessionId,
    List<String>? outputArtifacts,
  }) {
    final key = '${taskId}_$serverId';
    final session = _sessions[key];
    if (session != null) {
      session.status = status ?? session.status;
      session.sessionId = sessionId ?? session.sessionId;
      if (outputArtifacts != null) {
        session.outputArtifacts.addAll(outputArtifacts);
      }
      session.lastActivity = DateTime.now();
      _lastActivity[key] = DateTime.now();
      notifyListeners();
    }
  }

  /// 记录会话活动
  void recordActivity(String taskId, String serverId) {
    final key = '${taskId}_$serverId';
    _lastActivity[key] = DateTime.now();
  }

  /// 获取会话活动状态
  TaskStatus getActivityStatus(String taskId, String serverId) {
    final key = '${taskId}_$serverId';
    final lastActivity = _lastActivity[key];
    if (lastActivity == null) return TaskStatus.pending;
    
    final elapsed = DateTime.now().difference(lastActivity);
    if (elapsed.inMinutes < 5) return TaskStatus.running;
    return TaskStatus.completed;
  }

  /// 获取所有会话
  List<TaskSession> get allSessions => _sessions.values.toList();

  /// 清理过期会话
  void cleanupStaleSessions({Duration timeout = const Duration(hours: 24)}) {
    final now = DateTime.now();
    _sessions.removeWhere((key, session) {
      final lastActivity = _lastActivity[key] ?? session.createdAt;
      return now.difference(lastActivity) > timeout;
    });
    notifyListeners();
  }
}

/// 任务会话
class TaskSession {
  final String taskId;
  final String serverId;
  String? sessionId;
  TaskStatus status;
  List<String> outputArtifacts;
  final DateTime createdAt;
  DateTime? lastActivity;

  TaskSession({
    required this.taskId,
    required this.serverId,
    this.sessionId,
    required this.status,
    List<String>? outputArtifacts,
    required this.createdAt,
    this.lastActivity,
  }) : outputArtifacts = outputArtifacts ?? [];
}
