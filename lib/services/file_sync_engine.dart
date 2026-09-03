import 'package:flutter/foundation.dart';
import '../services/hermes_api_client.dart';
import '../providers/server_provider.dart' show ServerProvider, IterableExtension;
import '../providers/debug_logger.dart';

/// 文件同步引擎 — 负责跨服务器文件同步
class FileSyncEngine {
  final ServerProvider serverProvider;

  FileSyncEngine(this.serverProvider);

  /// 同步文件从源服务器到目标服务器
  Future<SyncResult> syncFile({
    required String sourceServerId,
    required String targetServerId,
    required String filePath,
    String? targetPath,
  }) async {
    try {
      // 获取源服务器和目标服务器
      final sourceServer = serverProvider.servers
          .where((s) => s.id == sourceServerId)
          .firstOrNull;
      final targetServer = serverProvider.servers
          .where((s) => s.id == targetServerId)
          .firstOrNull;

      if (sourceServer == null || targetServer == null) {
        return SyncResult(success: false, error: '服务器未找到');
      }

      // 读取源文件
      final sourceClient = HermesApiClient(sourceServer);
      final loggedIn = await sourceClient.ensureLoggedIn();
      if (!loggedIn) {
        return SyncResult(success: false, error: '源服务器登录失败');
      }

      // 使用 Studio Files API 读取文件
      final fileContent = await _readFile(sourceClient, filePath);
      if (fileContent == null) {
        return SyncResult(success: false, error: '读取源文件失败: $filePath');
      }

      // 写入目标服务器
      final targetClient = HermesApiClient(targetServer);
      final targetLoggedIn = await targetClient.ensureLoggedIn();
      if (!targetLoggedIn) {
        return SyncResult(success: false, error: '目标服务器登录失败');
      }

      final writeSuccess = await _writeFile(
        targetClient,
        targetPath ?? filePath,
        fileContent,
      );

      if (writeSuccess) {
        return SyncResult(
          success: true,
          message: '文件同步成功: $filePath → ${targetPath ?? filePath}',
        );
      } else {
        return SyncResult(success: false, error: '写入目标文件失败');
      }
    } catch (e) {
      return SyncResult(success: false, error: '同步异常: $e');
    }
  }

  /// 批量同步文件
  Future<List<SyncResult>> syncFiles({
    required String sourceServerId,
    required String targetServerId,
    required List<String> filePaths,
    String? targetDirectory,
  }) async {
    final results = <SyncResult>[];
    for (final filePath in filePaths) {
      final targetPath = targetDirectory != null
          ? '$targetDirectory/${filePath.split('/').last}'
          : null;
      final result = await syncFile(
        sourceServerId: sourceServerId,
        targetServerId: targetServerId,
        filePath: filePath,
        targetPath: targetPath,
      );
      results.add(result);
    }
    return results;
  }

  /// 同步整个目录
  Future<SyncResult> syncDirectory({
    required String sourceServerId,
    required String targetServerId,
    required String directoryPath,
    String? targetDirectory,
  }) async {
    try {
      final sourceServer = serverProvider.servers
          .where((s) => s.id == sourceServerId)
          .firstOrNull;
      if (sourceServer == null) {
        return SyncResult(success: false, error: '源服务器未找到');
      }

      final sourceClient = HermesApiClient(sourceServer);
      await sourceClient.ensureLoggedIn();

      // 列出目录内容
      final files = await _listFiles(sourceClient, directoryPath);
      if (files.isEmpty) {
        return SyncResult(
          success: true,
          message: '目录为空，无需同步: $directoryPath',
        );
      }

      // 批量同步
      final results = await syncFiles(
        sourceServerId: sourceServerId,
        targetServerId: targetServerId,
        filePaths: files,
        targetDirectory: targetDirectory,
      );

      final successCount = results.where((r) => r.success).length;
      final failCount = results.where((r) => !r.success).length;

      return SyncResult(
        success: failCount == 0,
        message: '目录同步完成: $successCount 成功, $failCount 失败',
        details: results,
      );
    } catch (e) {
      return SyncResult(success: false, error: '目录同步异常: $e');
    }
  }

  /// 读取文件（通过 Hermes Studio Files API）
  Future<String?> _readFile(HermesApiClient client, String path) async {
    // 使用 Hermes Studio Files API
    // 这里需要通过 HTTP 请求调用 Studio Files API
    // 由于 HermesApiClient 目前没有直接封装文件操作，我们需要扩展它
    // 暂时返回 null，后续扩展
    DebugLogger.instance.info('FileSync: 读取文件 $path');
    return null;
  }

  /// 写入文件（通过 Hermes Studio Files API）
  Future<bool> _writeFile(HermesApiClient client, String path, String content) async {
    DebugLogger.instance.info('FileSync: 写入文件 $path');
    return false;
  }

  /// 列出目录文件
  Future<List<String>> _listFiles(HermesApiClient client, String path) async {
    DebugLogger.instance.info('FileSync: 列出目录 $path');
    return [];
  }
}

/// 同步结果
class SyncResult {
  final bool success;
  final String? message;
  final String? error;
  final List<SyncResult>? details;

  SyncResult({
    required this.success,
    this.message,
    this.error,
    this.details,
  });
}

/// 文件同步 Provider
class FileSyncProvider extends ChangeNotifier {
  final ServerProvider serverProvider;
  late final FileSyncEngine _engine;

  bool _isSyncing = false;
  List<SyncJob> _syncJobs = [];

  FileSyncProvider(this.serverProvider) {
    _engine = FileSyncEngine(serverProvider);
  }

  bool get isSyncing => _isSyncing;
  List<SyncJob> get syncJobs => List.unmodifiable(_syncJobs);

  /// 创建同步任务
  Future<void> createSyncJob({
    required String sourceServerId,
    required String targetServerId,
    required String filePath,
    String? targetPath,
  }) async {
    _isSyncing = true;
    notifyListeners();

    final job = SyncJob(
      sourceServerId: sourceServerId,
      targetServerId: targetServerId,
      filePath: filePath,
      targetPath: targetPath,
    );
    _syncJobs.add(job);
    notifyListeners();

    final result = await _engine.syncFile(
      sourceServerId: sourceServerId,
      targetServerId: targetServerId,
      filePath: filePath,
      targetPath: targetPath,
    );

    job.result = result;
    _isSyncing = false;
    notifyListeners();
  }

  /// 创建目录同步任务
  Future<void> createDirectorySyncJob({
    required String sourceServerId,
    required String targetServerId,
    required String directoryPath,
    String? targetDirectory,
  }) async {
    _isSyncing = true;
    notifyListeners();

    final job = SyncJob(
      sourceServerId: sourceServerId,
      targetServerId: targetServerId,
      filePath: directoryPath,
      targetPath: targetDirectory,
      isDirectory: true,
    );
    _syncJobs.add(job);
    notifyListeners();

    final result = await _engine.syncDirectory(
      sourceServerId: sourceServerId,
      targetServerId: targetServerId,
      directoryPath: directoryPath,
      targetDirectory: targetDirectory,
    );

    job.result = result;
    _isSyncing = false;
    notifyListeners();
  }

  void clearJobs() {
    _syncJobs.clear();
    notifyListeners();
  }
}

/// 同步任务
class SyncJob {
  final String sourceServerId;
  final String targetServerId;
  final String filePath;
  final String? targetPath;
  final bool isDirectory;
  final DateTime createdAt;
  SyncResult? result;

  SyncJob({
    required this.sourceServerId,
    required this.targetServerId,
    required this.filePath,
    this.targetPath,
    this.isDirectory = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isCompleted => result != null;
  bool get isSuccess => result?.success ?? false;
}


