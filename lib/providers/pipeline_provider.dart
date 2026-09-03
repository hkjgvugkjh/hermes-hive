import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/task_models.dart';
import '../services/pipeline_engine.dart';
import '../services/session_manager.dart';
import '../services/pipeline_persistence.dart';
import '../providers/server_provider.dart' show ServerProvider, IterableExtension;
import '../providers/debug_logger.dart';

/// Pipeline Provider — 管理流水线的状态和操作
class PipelineProvider extends ChangeNotifier {
  final ServerProvider serverProvider;
  late final PipelineEngine _engine;
  late final TaskSplitter _splitter;
  late final SessionManager _sessionManager;
  late final ResultAggregator _resultAggregator;
  late final PipelinePersistence _persistence;

  List<Project> _projects = [];
  Project? _activeProject;
  List<Pipeline> _pipelines = [];
  Pipeline? _activePipeline;

  // 执行日志
  final List<ExecutionLog> _logs = [];

  PipelineProvider(this.serverProvider) {
    _engine = PipelineEngine(serverProvider);
    _splitter = TaskSplitter();
    _sessionManager = SessionManager();
    _resultAggregator = ResultAggregator();
    _persistence = PipelinePersistence();
    _engine.addListener(_onEngineUpdate);
    _init();
  }

  // Getters
  List<Project> get projects => _projects;
  Project? get activeProject => _activeProject;
  List<Pipeline> get pipelines => _pipelines;
  Pipeline? get activePipeline => _activePipeline;
  List<ExecutionLog> get logs => List.unmodifiable(_logs);
  bool get isRunning => _engine.isRunning;
  bool get isPaused => _engine.isPaused;
  Stream<PipelineProgress> get progressStream => _engine.progressStream;
  SessionManager get sessionManager => _sessionManager;

  void _onEngineUpdate() {
    notifyListeners();
  }

  Future<void> _init() async {
    _projects = await _persistence.loadProjects();
    final activeId = await _persistence.loadActiveProject();
    if (activeId != null) {
      _activeProject = _projects.where((p) => p.id == activeId).firstOrNull;
      if (_activeProject != null) {
        _pipelines = await _persistence.loadPipelines(_activeProject!.id);
      }
    }
    notifyListeners();
  }

  // 项目管理
  void createProject({
    required String name,
    String description = '',
    String repoUrl = '',
    String branch = 'main',
  }) {
    final project = Project(
      name: name,
      description: description,
      repoUrl: repoUrl,
      branch: branch,
    );
    _projects.add(project);
    _persistence.saveProjects(_projects);
    DebugLogger.instance.info('Project: 创建项目 "$name"');
    notifyListeners();
  }

  void deleteProject(String projectId) {
    _projects.removeWhere((p) => p.id == projectId);
    if (_activeProject?.id == projectId) {
      _activeProject = _projects.isNotEmpty ? _projects.first : null;
      if (_activeProject != null) {
        _persistence.saveActiveProject(_activeProject!.id);
      }
    }
    _persistence.saveProjects(_projects);
    notifyListeners();
  }

  void setActiveProject(String projectId) {
    _activeProject = _projects.where((p) => p.id == projectId).firstOrNull;
    if (_activeProject != null) {
      _persistence.saveActiveProject(_activeProject!.id);
      // 加载项目的流水线
      _persistence.loadPipelines(_activeProject!.id).then((pipelines) {
        _pipelines = pipelines;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // 流水线管理
  void createPipelineFromAnalysis({
    required String name,
    required List<String> requirements,
  }) {
    if (_activeProject == null) return;

    final stages = _splitter.analyzeProject(
      projectName: _activeProject!.name,
      projectDescription: _activeProject!.description,
      requirements: requirements,
    );

    final pipeline = Pipeline(
      name: name,
      description: '通过智能分析生成的流水线',
      projectId: _activeProject!.id,
      stages: stages,
      status: PipelineStatus.ready,
    );

    _pipelines.add(pipeline);
    _activeProject!.pipelines.add(pipeline);
    _persistence.savePipelines(_activeProject!.id, _pipelines);
    DebugLogger.instance.info('Pipeline: 从分析创建流水线 "$name" (${stages.length} 阶段)');
    notifyListeners();
  }

  void createPipelineFromTemplate({
    required String templateName,
    Map<String, dynamic>? params,
  }) {
    if (_activeProject == null) return;

    final pipeline = _splitter.createPipelineFromTemplate(
      templateName: templateName,
      projectId: _activeProject!.id,
      params: params,
    );
    pipeline.status = PipelineStatus.ready;

    _pipelines.add(pipeline);
    _activeProject!.pipelines.add(pipeline);
    _persistence.savePipelines(_activeProject!.id, _pipelines);
    DebugLogger.instance.info('Pipeline: 从模板创建流水线 "$templateName"');
    notifyListeners();
  }

  void deletePipeline(String pipelineId) {
    _pipelines.removeWhere((p) => p.id == pipelineId);
    _activeProject?.pipelines.removeWhere((p) => p.id == pipelineId);
    if (_activePipeline?.id == pipelineId) {
      _activePipeline = null;
    }
    if (_activeProject != null) {
      _persistence.savePipelines(_activeProject!.id, _pipelines);
    }
    notifyListeners();
  }

  void setActivePipeline(String pipelineId) {
    _activePipeline = _pipelines.where((p) => p.id == pipelineId).firstOrNull;
    if (_activePipeline != null) {
      _engine.loadPipeline(_activePipeline!);
    }
    notifyListeners();
  }

  // 切换流水线执行模式
  void setPipelineMode(String pipelineId, PipelineMode mode) {
    final pipeline = _pipelines.where((p) => p.id == pipelineId).firstOrNull;
    if (pipeline != null) {
      pipeline.mode = mode;
      if (_activeProject != null) {
        _persistence.savePipelines(_activeProject!.id, _pipelines);
      }
      notifyListeners();
    }
  }

  // 流水线执行
  Future<void> executePipeline() async {
    if (_activePipeline == null) return;

    _logs.clear();
    _addLog('开始执行流水线: ${_activePipeline!.name}', LogLevel.info);
    _addLog('执行模式: ${_activePipeline!.mode.label}', LogLevel.info);

    _engine.loadPipeline(_activePipeline!);
    await _engine.execute();

    // 聚合结果
    if (_activePipeline!.status == PipelineStatus.completed) {
      final result = _resultAggregator.aggregate(_activePipeline!.allTasks);
      _addLog('结果聚合: ${result.message}', LogLevel.success);
    }

    _addLog('流水线执行结束: ${_activePipeline!.status.label}',
        _activePipeline!.status == PipelineStatus.completed ? LogLevel.success : LogLevel.error);

    // 保存状态
    if (_activeProject != null) {
      _persistence.savePipelines(_activeProject!.id, _pipelines);
    }
  }

  void pausePipeline() {
    _engine.pause();
    _addLog('流水线已暂停', LogLevel.warn);
  }

  void resumePipeline() {
    _engine.resume();
    _addLog('流水线恢复执行', LogLevel.info);
  }

  void cancelPipeline() {
    _engine.cancel();
    _addLog('流水线已取消', LogLevel.warn);
  }

  void resetPipeline() {
    _engine.reset();
    _logs.clear();
    DebugLogger.instance.info('Pipeline: 流水线已重置');
    notifyListeners();
  }

  void _addLog(String message, LogLevel level) {
    _logs.add(ExecutionLog(
      message: message,
      level: level,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  // 添加阶段
  void addStage({
    required String name,
    String description = '',
  }) {
    if (_activePipeline == null) return;

    final stage = Stage(name: name, description: description);
    _activePipeline!.stages.add(stage);
    if (_activeProject != null) {
      _persistence.savePipelines(_activeProject!.id, _pipelines);
    }
    DebugLogger.instance.info('Pipeline: 添加阶段 "$name"');
    notifyListeners();
  }

  void removeStage(String stageId) {
    if (_activePipeline == null) return;
    _activePipeline!.stages.removeWhere((s) => s.id == stageId);
    if (_activeProject != null) {
      _persistence.savePipelines(_activeProject!.id, _pipelines);
    }
    notifyListeners();
  }

  // 添加任务
  void addTask({
    required String stageId,
    required String name,
    String description = '',
    TaskType type = TaskType.code,
    TaskPriority priority = TaskPriority.medium,
  }) {
    if (_activePipeline == null) return;

    final stage = _activePipeline!.stages.where((s) => s.id == stageId).firstOrNull;
    if (stage == null) return;

    final task = Task(
      name: name,
      description: description,
      type: type,
      priority: priority,
    );
    stage.tasks.add(task);
    if (_activeProject != null) {
      _persistence.savePipelines(_activeProject!.id, _pipelines);
    }
    DebugLogger.instance.info('Pipeline: 添加任务 "$name" 到阶段 "${stage.name}"');
    notifyListeners();
  }

  void removeTask(String stageId, String taskId) {
    if (_activePipeline == null) return;
    final stage = _activePipeline!.stages.where((s) => s.id == stageId).firstOrNull;
    stage?.tasks.removeWhere((t) => t.id == taskId);
    if (_activeProject != null) {
      _persistence.savePipelines(_activeProject!.id, _pipelines);
    }
    notifyListeners();
  }

  // 更新任务服务器分配
  void assignTaskServer(String taskId, String serverId) {
    if (_activePipeline == null) return;
    for (final stage in _activePipeline!.stages) {
      for (final task in stage.tasks) {
        if (task.id == taskId) {
          task.serverId = serverId;
          notifyListeners();
          return;
        }
      }
    }
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineUpdate);
    _engine.dispose();
    super.dispose();
  }
}

/// 执行日志
class ExecutionLog {
  final String message;
  final LogLevel level;
  final DateTime timestamp;

  ExecutionLog({
    required this.message,
    required this.level,
    required this.timestamp,
  });
}

enum LogLevel {
  info,
  success,
  warn,
  error,
}
