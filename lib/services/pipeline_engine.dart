import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/task_models.dart';
import '../providers/server_provider.dart' show ServerProvider, IterableExtension;
import '../services/hermes_api_client.dart';
import '../providers/debug_logger.dart';

/// 流水线引擎 — 负责调度和执行任务
class PipelineEngine extends ChangeNotifier {
  final ServerProvider serverProvider;
  
  Pipeline? _currentPipeline;
  bool _isRunning = false;
  bool _isPaused = false;
  
  /// 执行进度流
  final _progressController = StreamController<PipelineProgress>.broadcast();
  Stream<PipelineProgress> get progressStream => _progressController.stream;
  
  Pipeline? get currentPipeline => _currentPipeline;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;

  PipelineEngine(this.serverProvider);

  /// 加载流水线
  void loadPipeline(Pipeline pipeline) {
    _currentPipeline = pipeline;
    notifyListeners();
  }

  /// 执行流水线（串行模式）
  Future<void> execute() async {
    if (_currentPipeline == null) return;
    if (_isRunning) return;

    _isRunning = true;
    _isPaused = false;
    _currentPipeline!.status = PipelineStatus.running;
    _currentPipeline!.startedAt = DateTime.now();
    
    DebugLogger.instance.info('Pipeline: 开始执行流水线 "${_currentPipeline!.name}"');
    notifyListeners();

    try {
      for (int i = 0; i < _currentPipeline!.stages.length; i++) {
        if (_isPaused) {
          _currentPipeline!.status = PipelineStatus.paused;
          DebugLogger.instance.info('Pipeline: 流水线已暂停');
          _progressController.add(PipelineProgress(
            stageIndex: i,
            totalStages: _currentPipeline!.stages.length,
            message: '流水线已暂停',
          ));
          return;
        }

        final stage = _currentPipeline!.stages[i];
        _currentPipeline!.currentStageIndex = i;
        
        DebugLogger.instance.info('Pipeline: 执行阶段 "${stage.name}" (${i + 1}/${_currentPipeline!.stages.length})');
        
        // 根据流水线模式选择执行方式
        if (_currentPipeline!.mode == PipelineMode.parallel) {
          await _executeStageParallel(stage, i);
        } else {
          await _executeStage(stage, i);
        }
        
        if (stage.status == StageStatus.failed) {
          _currentPipeline!.status = PipelineStatus.failed;
          _currentPipeline!.errorMessage = '阶段 "${stage.name}" 执行失败';
          DebugLogger.instance.error('Pipeline: 流水线失败');
          _progressController.add(PipelineProgress(
            stageIndex: i,
            totalStages: _currentPipeline!.stages.length,
            message: '流水线失败: ${stage.name}',
            isError: true,
          ));
          return;
        }

        _progressController.add(PipelineProgress(
          stageIndex: i,
          totalStages: _currentPipeline!.stages.length,
          message: '阶段 "${stage.name}" 完成',
        ));
      }

      _currentPipeline!.status = PipelineStatus.completed;
      _currentPipeline!.completedAt = DateTime.now();
      DebugLogger.instance.success('Pipeline: 流水线执行完成');
      _progressController.add(PipelineProgress(
        stageIndex: _currentPipeline!.stages.length,
        totalStages: _currentPipeline!.stages.length,
        message: '流水线完成',
        isComplete: true,
      ));
    } catch (e) {
      _currentPipeline!.status = PipelineStatus.failed;
      _currentPipeline!.errorMessage = e.toString();
      DebugLogger.instance.error('Pipeline: 流水线异常', e.toString());
      _progressController.add(PipelineProgress(
        stageIndex: _currentPipeline!.currentStageIndex,
        totalStages: _currentPipeline!.stages.length,
        message: '流水线异常: $e',
        isError: true,
      ));
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// 执行单个阶段（并行执行任务）
  Future<void> _executeStageParallel(Stage stage, int stageIndex) async {
    stage.status = StageStatus.running;
    stage.startedAt = DateTime.now();
    notifyListeners();

    // 并行执行所有任务
    final futures = stage.tasks.map((task) async {
      if (_isPaused) {
        task.status = TaskStatus.cancelled;
        return;
      }
      await _executeTask(task);
    });

    // 等待所有任务完成
    await Future.wait(futures);

    // 统计结果
    final completedCount = stage.tasks.where((t) => t.status == TaskStatus.completed).length;
    final failedCount = stage.tasks.where((t) => t.status == TaskStatus.failed).length;

    stage.completedAt = DateTime.now();
    
    if (failedCount > 0 && completedCount == 0) {
      stage.status = StageStatus.failed;
    } else if (failedCount > 0) {
      stage.status = StageStatus.partial;
    } else {
      stage.status = StageStatus.completed;
    }
    
    notifyListeners();
  }

  /// 执行单个阶段（串行执行任务）
  Future<void> _executeStage(Stage stage, int stageIndex) async {
    stage.status = StageStatus.running;
    stage.startedAt = DateTime.now();
    notifyListeners();

    bool hasFailure = false;
    bool hasSuccess = false;

    for (final task in stage.tasks) {
      if (_isPaused) {
        task.status = TaskStatus.cancelled;
        continue;
      }

      await _executeTask(task);
      
      if (task.status == TaskStatus.completed) {
        hasSuccess = true;
      } else if (task.status == TaskStatus.failed) {
        hasFailure = true;
        // 串行模式下，一个任务失败则阶段失败
        break;
      }
    }

    stage.completedAt = DateTime.now();
    
    if (hasFailure) {
      stage.status = StageStatus.failed;
    } else if (hasSuccess) {
      stage.status = StageStatus.completed;
    } else {
      stage.status = StageStatus.partial;
    }
    
    notifyListeners();
  }

  /// 执行单个任务
  Future<void> _executeTask(Task task) async {
    task.status = TaskStatus.running;
    task.startedAt = DateTime.now();
    notifyListeners();

    DebugLogger.instance.info('Task: 执行任务 "${task.name}" (类型: ${task.type.label})');

    // 检查是否有可用服务器
    final availableServers = serverProvider.onlineServers;
    if (availableServers.isEmpty) {
      task.status = TaskStatus.failed;
      task.errorMessage = '没有可用的在线服务器';
      task.completedAt = DateTime.now();
      DebugLogger.instance.error('Task: 无可用服务器');
      notifyListeners();
      return;
    }

    // 分配服务器
    final server = task.serverId != null
        ? availableServers.where((s) => s.id == task.serverId).firstOrNull ??
            availableServers.first
        : availableServers.first;
    
    task.serverId = server.id;

    final client = HermesApiClient(server);
    final loggedIn = await client.ensureLoggedIn();
    if (!loggedIn) {
      task.status = TaskStatus.failed;
      task.errorMessage = '服务器登录失败';
      task.completedAt = DateTime.now();
      notifyListeners();
      return;
    }

    try {
      // 构建任务提示词
      final prompt = _buildTaskPrompt(task);
      
      // 执行任务
      final result = await client.runChat(
        input: prompt,
        sessionId: task.sessionId,
      );

      if (result.success) {
        task.status = TaskStatus.completed;
        task.sessionId = result.sessionId;
        // 将输出作为产物
        if (result.content.isNotEmpty) {
          task.outputArtifacts.add(result.content);
        }
        DebugLogger.instance.success('Task: 任务 "${task.name}" 完成');
      } else {
        // 重试逻辑
        if (task.retryCount < task.maxRetries) {
          task.retryCount++;
          task.status = TaskStatus.retrying;
          DebugLogger.instance.warn('Task: 任务 "${task.name}" 重试 (${task.retryCount}/${task.maxRetries})');
          await Future.delayed(const Duration(seconds: 2));
          return _executeTask(task);
        }
        task.status = TaskStatus.failed;
        task.errorMessage = result.error ?? '未知错误';
        DebugLogger.instance.error('Task: 任务 "${task.name}" 失败', task.errorMessage);
      }
    } catch (e) {
      if (task.retryCount < task.maxRetries) {
        task.retryCount++;
        task.status = TaskStatus.retrying;
        await Future.delayed(const Duration(seconds: 2));
        return _executeTask(task);
      }
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      DebugLogger.instance.error('Task: 任务 "${task.name}" 异常', e.toString());
    } finally {
      task.completedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// 构建任务提示词
  String _buildTaskPrompt(Task task) {
    final buffer = StringBuffer();
    
    buffer.writeln('## 任务: ${task.name}');
    buffer.writeln('类型: ${task.type.label}');
    buffer.writeln('描述: ${task.description}');
    
    if (task.context.isNotEmpty) {
      buffer.writeln('\\n## 上下文:');
      task.context.forEach((key, value) {
        buffer.writeln('$key: $value');
      });
    }
    
    if (task.inputArtifacts.isNotEmpty) {
      buffer.writeln('\\n## 输入:');
      for (final artifact in task.inputArtifacts) {
        buffer.writeln('- $artifact');
      }
    }
    
    buffer.writeln('\\n## 要求:');
    buffer.writeln('完成后回复OK，全部完成回复DONE');
    
    return buffer.toString();
  }

  /// 暂停流水线
  void pause() {
    if (_isRunning) {
      _isPaused = true;
      DebugLogger.instance.info('Pipeline: 请求暂停');
    }
  }

  /// 恢复流水线
  void resume() {
    if (_isPaused && _currentPipeline != null) {
      _isPaused = false;
      DebugLogger.instance.info('Pipeline: 恢复执行');
      execute();
    }
  }

  /// 取消流水线
  void cancel() {
    _isPaused = false;
    _isRunning = false;
    if (_currentPipeline != null) {
      _currentPipeline!.status = PipelineStatus.cancelled;
    }
    DebugLogger.instance.info('Pipeline: 流水线已取消');
    notifyListeners();
  }

  /// 重置流水线
  void reset() {
    if (_currentPipeline != null) {
      _currentPipeline!.status = PipelineStatus.draft;
      _currentPipeline!.currentStageIndex = 0;
      _currentPipeline!.startedAt = null;
      _currentPipeline!.completedAt = null;
      _currentPipeline!.errorMessage = null;
      for (final stage in _currentPipeline!.stages) {
        stage.status = StageStatus.pending;
        stage.startedAt = null;
        stage.completedAt = null;
        for (final task in stage.tasks) {
          task.status = TaskStatus.pending;
          task.startedAt = null;
          task.completedAt = null;
          task.retryCount = 0;
          task.errorMessage = null;
        }
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }
}

/// 流水线执行进度
class PipelineProgress {
  final int stageIndex;
  final int totalStages;
  final String message;
  final bool isError;
  final bool isComplete;

  PipelineProgress({
    required this.stageIndex,
    required this.totalStages,
    required this.message,
    this.isError = false,
    this.isComplete = false,
  });

  double get progress => totalStages > 0 ? stageIndex / totalStages : 0;
}

/// Task Splitter — 将项目分解为可执行的任务
class TaskSplitter {
  /// 分析项目结构并生成任务列表
  List<Stage> analyzeProject({
    required String projectName,
    required String projectDescription,
    required List<String> requirements,
  }) {
    final stages = <Stage>[];
    
    // 阶段1: 分析与规划
    stages.add(Stage(
      name: '分析与规划',
      description: '分析项目需求并制定执行计划',
      tasks: [
        Task(
          name: '需求分析',
          description: '分析以下需求并生成详细的需求文档: ${requirements.join(", ")}',
          type: TaskType.analysis,
          priority: TaskPriority.high,
        ),
      ],
    ));
    
    // 阶段2: 设计
    stages.add(Stage(
      name: '架构设计',
      description: '设计系统架构和模块划分',
      dependsOn: [stages[0].id],
      tasks: [
        Task(
          name: '系统设计',
          description: '基于需求文档设计系统架构、模块划分、接口定义',
          type: TaskType.code,
          priority: TaskPriority.high,
        ),
      ],
    ));
    
    // 阶段3: 开发
    stages.add(Stage(
      name: '开发实现',
          description: '按模块实现代码',
      dependsOn: [stages[1].id],
      tasks: [
        Task(
          name: '核心模块开发',
          description: '实现核心业务逻辑',
          type: TaskType.code,
          priority: TaskPriority.high,
        ),
        Task(
          name: '辅助模块开发',
          description: '实现辅助功能模块',
          type: TaskType.code,
          priority: TaskPriority.medium,
        ),
      ],
    ));
    
    // 阶段4: 测试
    stages.add(Stage(
      name: '测试验证',
      description: '执行单元测试和集成测试',
      dependsOn: [stages[2].id],
      tasks: [
        Task(
          name: '单元测试',
          description: '编写并执行单元测试',
          type: TaskType.test,
          priority: TaskPriority.high,
        ),
      ],
    ));
    
    // 阶段5: 文档
    stages.add(Stage(
      name: '文档编写',
      description: '编写项目文档',
      dependsOn: [stages[2].id],
      tasks: [
        Task(
          name: 'API文档',
          description: '生成API接口文档',
          type: TaskType.doc,
          priority: TaskPriority.medium,
        ),
      ],
    ));
    
    return stages;
  }

  /// 从模板创建流水线
  Pipeline createPipelineFromTemplate({
    required String templateName,
    required String projectId,
    Map<String, dynamic>? params,
  }) {
    switch (templateName) {
      case 'full_stack':
        return _createFullStackPipeline(projectId, params);
      case 'ci_cd':
        return _createCICDPipeline(projectId, params);
      case 'code_review':
        return _createCodeReviewPipeline(projectId, params);
      default:
        return _createCustomPipeline(projectId, params);
    }
  }

  Pipeline _createFullStackPipeline(String projectId, Map<String, dynamic>? params) {
    return Pipeline(
      name: '全栈项目开发',
      description: '完整的全栈项目开发流水线',
      projectId: projectId,
      stages: [
        Stage(name: '需求分析', tasks: [
          Task(name: '需求收集', type: TaskType.analysis),
          Task(name: '需求评审', type: TaskType.review),
        ]),
        Stage(name: '设计', tasks: [
          Task(name: 'UI设计', type: TaskType.code),
          Task(name: '架构设计', type: TaskType.code),
        ]),
        Stage(name: '开发', tasks: [
          Task(name: '后端开发', type: TaskType.code),
          Task(name: '前端开发', type: TaskType.code),
          Task(name: '数据库设计', type: TaskType.code),
        ]),
        Stage(name: '测试', tasks: [
          Task(name: '单元测试', type: TaskType.test),
          Task(name: '集成测试', type: TaskType.test),
        ]),
        Stage(name: '部署', tasks: [
          Task(name: '构建', type: TaskType.build),
          Task(name: '部署', type: TaskType.deploy),
        ]),
      ],
    );
  }

  Pipeline _createCICDPipeline(String projectId, Map<String, dynamic>? params) {
    return Pipeline(
      name: 'CI/CD 流水线',
      description: '持续集成与部署流水线',
      projectId: projectId,
      stages: [
        Stage(name: '检出', tasks: [
          Task(name: '代码检出', type: TaskType.code),
        ]),
        Stage(name: '构建', tasks: [
          Task(name: '编译构建', type: TaskType.build),
        ]),
        Stage(name: '测试', tasks: [
          Task(name: '自动化测试', type: TaskType.test),
        ]),
        Stage(name: '部署', tasks: [
          Task(name: '部署上线', type: TaskType.deploy),
        ]),
      ],
    );
  }

  Pipeline _createCodeReviewPipeline(String projectId, Map<String, dynamic>? params) {
    return Pipeline(
      name: '代码审查',
      description: '自动化代码审查流水线',
      projectId: projectId,
      stages: [
        Stage(name: '静态分析', tasks: [
          Task(name: '代码规范检查', type: TaskType.analysis),
          Task(name: '安全扫描', type: TaskType.analysis),
        ]),
        Stage(name: '人工审查', tasks: [
          Task(name: '代码审查', type: TaskType.review),
        ]),
        Stage(name: '修复', tasks: [
          Task(name: '问题修复', type: TaskType.code),
        ]),
      ],
    );
  }

  Pipeline _createCustomPipeline(String projectId, Map<String, dynamic>? params) {
    return Pipeline(
      name: params?['name'] ?? '自定义流水线',
      description: params?['description'] ?? '自定义流水线',
      projectId: projectId,
      stages: [],
    );
  }
}

/// Extension for firstOrNull - using the one from server_provider.dart

