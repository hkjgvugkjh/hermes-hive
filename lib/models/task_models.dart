import 'package:uuid/uuid.dart';

/// 任务状态枚举
enum TaskStatus {
  pending('待执行'),
  ready('就绪'),
  running('执行中'),
  completed('已完成'),
  failed('失败'),
  retrying('重试中'),
  cancelled('已取消'),
  skipped('已跳过');

  const TaskStatus(this.label);
  final String label;
}

/// 任务优先级
enum TaskPriority {
  critical(0),
  high(1),
  medium(2),
  low(3);

  const TaskPriority(this.value);
  final int value;
}

/// 任务类型
enum TaskType {
  code('代码开发'),
  test('测试'),
  build('构建'),
  deploy('部署'),
  review('代码审查'),
  doc('文档'),
  analysis('分析'),
  sync('同步');

  const TaskType(this.label);
  final String label;
}

/// 任务模型
class Task {
  final String id;
  String name;
  String description;
  TaskType type;
  TaskPriority priority;
  TaskStatus status;
  String? serverId; // 执行的服务器 ID
  String? sessionId; // Hermes Studio 会话 ID
  Map<String, dynamic> context; // 任务上下文
  List<String> inputArtifacts; // 输入产物路径
  List<String> outputArtifacts; // 输出产物路径
  int maxRetries;
  int retryCount;
  Duration timeout;
  DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;
  String? errorMessage;

  Task({
    String? id,
    required this.name,
    this.description = '',
    this.type = TaskType.code,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    this.serverId,
    this.sessionId,
    Map<String, dynamic>? context,
    List<String>? inputArtifacts,
    List<String>? outputArtifacts,
    this.maxRetries = 3,
    this.retryCount = 0,
    this.timeout = const Duration(minutes: 30),
    DateTime? createdAt,
    this.startedAt,
    this.completedAt,
    this.errorMessage,
  })  : id = id ?? const Uuid().v4(),
        context = context ?? {},
        inputArtifacts = inputArtifacts ?? [],
        outputArtifacts = outputArtifacts ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'type': type.name,
        'priority': priority.name,
        'status': status.name,
        'serverId': serverId,
        'sessionId': sessionId,
        'context': context,
        'inputArtifacts': inputArtifacts,
        'outputArtifacts': outputArtifacts,
        'maxRetries': maxRetries,
        'retryCount': retryCount,
        'timeout': timeout.inSeconds,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'errorMessage': errorMessage,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        type: TaskType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => TaskType.code,
        ),
        priority: TaskPriority.values.firstWhere(
          (e) => e.name == json['priority'],
          orElse: () => TaskPriority.medium,
        ),
        status: TaskStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => TaskStatus.pending,
        ),
        serverId: json['serverId'] as String?,
        sessionId: json['sessionId'] as String?,
        context: json['context'] as Map<String, dynamic>? ?? {},
        inputArtifacts:
            (json['inputArtifacts'] as List?)?.cast<String>() ?? [],
        outputArtifacts:
            (json['outputArtifacts'] as List?)?.cast<String>() ?? [],
        maxRetries: json['maxRetries'] as int? ?? 3,
        retryCount: json['retryCount'] as int? ?? 0,
        timeout: Duration(seconds: json['timeout'] as int? ?? 1800),
        createdAt: DateTime.parse(json['createdAt'] as String),
        startedAt: json['startedAt'] != null
            ? DateTime.parse(json['startedAt'] as String)
            : null,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        errorMessage: json['errorMessage'] as String?,
      );

  Task copyWith({
    String? name,
    String? description,
    TaskType? type,
    TaskPriority? priority,
    TaskStatus? status,
    String? serverId,
    String? sessionId,
    Map<String, dynamic>? context,
    List<String>? inputArtifacts,
    List<String>? outputArtifacts,
    int? maxRetries,
    int? retryCount,
    Duration? timeout,
    DateTime? startedAt,
    DateTime? completedAt,
    String? errorMessage,
  }) =>
      Task(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        type: type ?? this.type,
        priority: priority ?? this.priority,
        status: status ?? this.status,
        serverId: serverId ?? this.serverId,
        sessionId: sessionId ?? this.sessionId,
        context: context ?? this.context,
        inputArtifacts: inputArtifacts ?? this.inputArtifacts,
        outputArtifacts: outputArtifacts ?? this.outputArtifacts,
        maxRetries: maxRetries ?? this.maxRetries,
        retryCount: retryCount ?? this.retryCount,
        timeout: timeout ?? this.timeout,
        createdAt: createdAt,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

/// 阶段模型 — 流水线中的一个阶段，包含多个并行任务
class Stage {
  final String id;
  String name;
  String description;
  List<Task> tasks;
  List<String> dependsOn; // 依赖的阶段 ID
  StageStatus status;
  DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;

  Stage({
    String? id,
    required this.name,
    this.description = '',
    List<Task>? tasks,
    List<String>? dependsOn,
    this.status = StageStatus.pending,
    DateTime? createdAt,
    this.startedAt,
    this.completedAt,
  })  : id = id ?? const Uuid().v4(),
        tasks = tasks ?? [],
        dependsOn = dependsOn ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'dependsOn': dependsOn,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory Stage.fromJson(Map<String, dynamic> json) => Stage(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        tasks: (json['tasks'] as List? ?? [])
            .map((t) => Task.fromJson(t as Map<String, dynamic>))
            .toList(),
        dependsOn: (json['dependsOn'] as List?)?.cast<String>() ?? [],
        status: StageStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => StageStatus.pending,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        startedAt: json['startedAt'] != null
            ? DateTime.parse(json['startedAt'] as String)
            : null,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );
}

enum StageStatus {
  pending('待执行'),
  running('执行中'),
  completed('已完成'),
  failed('失败'),
  partial('部分完成');

  const StageStatus(this.label);
  final String label;
}

/// 流水线模型 — 由多个阶段组成的工作流
class Pipeline {
  final String id;
  String name;
  String description;
  String projectId;
  PipelineMode mode;
  List<Stage> stages;
  PipelineStatus status;
  Map<String, dynamic> sharedContext; // 阶段间共享上下文
  DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;
  String? errorMessage;
  int currentStageIndex;

  Pipeline({
    String? id,
    required this.name,
    this.description = '',
    required this.projectId,
    this.mode = PipelineMode.sequential,
    List<Stage>? stages,
    this.status = PipelineStatus.draft,
    Map<String, dynamic>? sharedContext,
    DateTime? createdAt,
    this.startedAt,
    this.completedAt,
    this.errorMessage,
    this.currentStageIndex = 0,
  })  : id = id ?? const Uuid().v4(),
        stages = stages ?? [],
        sharedContext = sharedContext ?? {},
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'projectId': projectId,
        'mode': mode.name,
        'stages': stages.map((s) => s.toJson()).toList(),
        'status': status.name,
        'sharedContext': sharedContext,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'errorMessage': errorMessage,
        'currentStageIndex': currentStageIndex,
      };

  factory Pipeline.fromJson(Map<String, dynamic> json) => Pipeline(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        projectId: json['projectId'] as String,
        mode: PipelineMode.values.firstWhere(
          (e) => e.name == json['mode'],
          orElse: () => PipelineMode.sequential,
        ),
        stages: (json['stages'] as List? ?? [])
            .map((s) => Stage.fromJson(s as Map<String, dynamic>))
            .toList(),
        status: PipelineStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => PipelineStatus.draft,
        ),
        sharedContext:
            json['sharedContext'] as Map<String, dynamic>? ?? {},
        createdAt: DateTime.parse(json['createdAt'] as String),
        startedAt: json['startedAt'] != null
            ? DateTime.parse(json['startedAt'] as String)
            : null,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        errorMessage: json['errorMessage'] as String?,
        currentStageIndex: json['currentStageIndex'] as int? ?? 0,
      );

  /// 获取下一个待执行的阶段
  Stage? get nextStage {
    if (currentStageIndex < stages.length) {
      return stages[currentStageIndex];
    }
    return null;
  }

  /// 获取所有任务（跨阶段）
  List<Task> get allTasks {
    return stages.expand((s) => s.tasks).toList();
  }

  /// 获取已完成任务数
  int get completedTaskCount {
    return allTasks.where((t) => t.status == TaskStatus.completed).length;
  }

  /// 获取总任务数
  int get totalTaskCount => allTasks.length;

  /// 获取进度百分比
  double get progress {
    if (totalTaskCount == 0) return 0;
    return completedTaskCount / totalTaskCount;
  }
}

enum PipelineStatus {
  draft('草稿'),
  ready('就绪'),
  running('执行中'),
  paused('已暂停'),
  completed('已完成'),
  failed('失败'),
  cancelled('已取消');

  const PipelineStatus(this.label);
  final String label;
}

/// 流水线执行模式
enum PipelineMode {
  sequential('串行'),
  parallel('并行');

  const PipelineMode(this.label);
  final String label;
}

/// 项目模型
class Project {
  final String id;
  String name;
  String description;
  String repoUrl;
  String branch;
  List<Pipeline> pipelines;
  DateTime createdAt;
  DateTime? lastRunAt;

  Project({
    String? id,
    required this.name,
    this.description = '',
    this.repoUrl = '',
    this.branch = 'main',
    List<Pipeline>? pipelines,
    DateTime? createdAt,
    this.lastRunAt,
  })  : id = id ?? const Uuid().v4(),
        pipelines = pipelines ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'repoUrl': repoUrl,
        'branch': branch,
        'pipelines': pipelines.map((p) => p.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'lastRunAt': lastRunAt?.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        repoUrl: json['repoUrl'] as String? ?? '',
        branch: json['branch'] as String? ?? 'main',
        pipelines: (json['pipelines'] as List? ?? [])
            .map((p) => Pipeline.fromJson(p as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastRunAt: json['lastRunAt'] != null
            ? DateTime.parse(json['lastRunAt'] as String)
            : null,
      );
}
