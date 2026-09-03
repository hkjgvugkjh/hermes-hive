import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/version_control.dart';
import '../providers/server_provider.dart' show ServerProvider;

/// 版本控制 Provider
class VersionControlProvider extends ChangeNotifier {
  final ServerProvider serverProvider;
  late final GitBridge _gitBridge;
  late final SvnBridge _svnBridge;
  late final BranchStrategyManager _branchStrategy;
  late final ConflictDetector _conflictDetector;

  bool _isBusy = false;
  List<VersionControlLog> _logs = [];
  String? _activeServerId;
  String _currentBranch = '';
  String _currentRepoPath = '';

  VersionControlProvider(this.serverProvider) {
    _gitBridge = GitBridge(serverProvider);
    _svnBridge = SvnBridge(serverProvider);
    _branchStrategy = BranchStrategyManager(_gitBridge);
    _conflictDetector = ConflictDetector();
  }

  bool get isBusy => _isBusy;
  List<VersionControlLog> get logs => List.unmodifiable(_logs);
  String? get activeServerId => _activeServerId;
  String get currentBranch => _currentBranch;
  String get currentRepoPath => _currentRepoPath;

  void setActiveServer(String serverId) {
    _activeServerId = serverId;
    notifyListeners();
  }

  void setRepoPath(String path) {
    _currentRepoPath = path;
    notifyListeners();
  }

  // Git 操作
  Future<GitResult> gitClone(String repoUrl, {String? targetDir, String? branch}) async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.clone(
      serverId: _activeServerId!,
      repoUrl: repoUrl,
      targetDirectory: targetDir,
      branch: branch,
    );

    _addLog('git clone $repoUrl', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<GitResult> gitCheckout(String branch, {bool create = false}) async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.checkout(
      serverId: _activeServerId!,
      branch: branch,
      workingDirectory: _currentRepoPath,
      create: create,
    );

    if (result.success) {
      _currentBranch = branch;
    }

    _addLog('git checkout ${create ? '-b ' : ''}$branch', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<GitResult> gitCommit(String message, {bool addAll = true}) async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.commit(
      serverId: _activeServerId!,
      message: message,
      workingDirectory: _currentRepoPath,
      addAll: addAll,
    );

    _addLog('git commit -m "$message"', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<GitResult> gitPush({String? remote, String? branch}) async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.push(
      serverId: _activeServerId!,
      remote: remote,
      branch: branch,
      workingDirectory: _currentRepoPath,
    );

    _addLog('git push ${remote ?? 'origin'} ${branch ?? 'HEAD'}', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<GitResult> gitPull({String? remote, String? branch}) async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.pull(
      serverId: _activeServerId!,
      remote: remote,
      branch: branch,
      workingDirectory: _currentRepoPath,
    );

    _addLog('git pull ${remote ?? 'origin'} ${branch ?? 'HEAD'}', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<GitResult> gitStatus() async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.status(
      serverId: _activeServerId!,
      workingDirectory: _currentRepoPath,
    );

    _addLog('git status', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<GitResult> gitLog({int count = 10}) async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.log(
      serverId: _activeServerId!,
      workingDirectory: _currentRepoPath,
      count: count,
    );

    _addLog('git log -$count', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<GitResult> gitMerge(String branch, {bool noFf = false}) async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.merge(
      serverId: _activeServerId!,
      branch: branch,
      workingDirectory: _currentRepoPath,
      noFf: noFf,
    );

    _addLog('git merge ${noFf ? '--no-ff ' : ''}$branch', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<GitResult> gitDiff({String? branch1, String? branch2}) async {
    if (_activeServerId == null) return GitResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _gitBridge.diff(
      serverId: _activeServerId!,
      workingDirectory: _currentRepoPath,
      branch1: branch1,
      branch2: branch2,
    );

    _addLog('git diff ${branch1 ?? ''} ${branch2 ?? ''}', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  // 分支策略
  Future<void> executeGitFlow(String featureName) async {
    if (_activeServerId == null) return;
    _isBusy = true;
    notifyListeners();

    await _branchStrategy.executeGitFlow(
      serverId: _activeServerId!,
      repoPath: _currentRepoPath,
      featureName: featureName,
    );

    _addLog('GitFlow: 创建 feature/$featureName', LogLevel.success, '');
    _isBusy = false;
    notifyListeners();
  }

  Future<void> finishFeature(String featureName) async {
    if (_activeServerId == null) return;
    _isBusy = true;
    notifyListeners();

    await _branchStrategy.finishFeature(
      serverId: _activeServerId!,
      repoPath: _currentRepoPath,
      featureName: featureName,
    );

    _addLog('GitFlow: 完成 feature/$featureName', LogLevel.success, '');
    _isBusy = false;
    notifyListeners();
  }

  // 冲突检测
  Future<ConflictResult> detectConflicts(String sourceBranch, String targetBranch) async {
    if (_activeServerId == null) return ConflictResult(hasConflicts: false, conflictFiles: [], message: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _conflictDetector.detectConflicts(
      gitBridge: _gitBridge,
      serverId: _activeServerId!,
      repoPath: _currentRepoPath,
      sourceBranch: sourceBranch,
      targetBranch: targetBranch,
    );

    _addLog('冲突检测: $sourceBranch → $targetBranch', result.hasConflicts ? LogLevel.warn : LogLevel.success, result.message);
    _isBusy = false;
    notifyListeners();
    return result;
  }

  // SVN 操作
  Future<SvnResult> svnCheckout(String repoUrl, {String? targetDir}) async {
    if (_activeServerId == null) return SvnResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _svnBridge.checkout(
      serverId: _activeServerId!,
      repoUrl: repoUrl,
      targetDirectory: targetDir,
    );

    _addLog('svn checkout $repoUrl', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<SvnResult> svnUpdate() async {
    if (_activeServerId == null) return SvnResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _svnBridge.update(
      serverId: _activeServerId!,
      workingDirectory: _currentRepoPath,
    );

    _addLog('svn update', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<SvnResult> svnCommit(String message) async {
    if (_activeServerId == null) return SvnResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _svnBridge.commit(
      serverId: _activeServerId!,
      message: message,
      workingDirectory: _currentRepoPath,
    );

    _addLog('svn commit -m "$message"', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  Future<SvnResult> svnStatus() async {
    if (_activeServerId == null) return SvnResult(success: false, error: '未选择服务器');
    _isBusy = true;
    notifyListeners();

    final result = await _svnBridge.status(
      serverId: _activeServerId!,
      workingDirectory: _currentRepoPath,
    );

    _addLog('svn status', result.success ? LogLevel.success : LogLevel.error, result.output ?? result.error ?? '');
    _isBusy = false;
    notifyListeners();
    return result;
  }

  void _addLog(String message, LogLevel level, String output) {
    _logs.add(VersionControlLog(
      message: message,
      level: level,
      output: output,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}

/// 版本控制日志
class VersionControlLog {
  final String message;
  final LogLevel level;
  final String output;
  final DateTime timestamp;

  VersionControlLog({
    required this.message,
    required this.level,
    required this.output,
    required this.timestamp,
  });
}

enum LogLevel {
  info,
  success,
  warn,
  error,
}
