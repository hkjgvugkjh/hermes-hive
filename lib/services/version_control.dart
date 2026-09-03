import 'dart:async';
import '../services/hermes_api_client.dart';
import '../providers/server_provider.dart' show ServerProvider, IterableExtension;
import '../providers/debug_logger.dart';

/// Git 桥接服务 — 通过 Hermes Studio API 执行 Git 操作
class GitBridge {
  final ServerProvider serverProvider;

  GitBridge(this.serverProvider);

  /// 在服务器上执行 Git 命令
  Future<GitResult> executeGitCommand({
    required String serverId,
    required String command,
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    try {
      final server = serverProvider.servers
          .where((s) => s.id == serverId)
          .firstOrNull;
      if (server == null) {
        return GitResult(success: false, error: '服务器未找到');
      }

      final client = HermesApiClient(server);
      final loggedIn = await client.ensureLoggedIn();
      if (!loggedIn) {
        return GitResult(success: false, error: '服务器登录失败');
      }

      // 使用 Terminal API 执行 Git 命令
      final terminalResult = await _runTerminalCommand(
        client,
        command,
        workingDirectory: workingDirectory,
        timeout: timeout,
      );

      return GitResult(
        success: terminalResult.success,
        output: terminalResult.output,
        error: terminalResult.error,
      );
    } catch (e) {
      return GitResult(success: false, error: 'Git 命令执行异常: $e');
    }
  }

  /// 通过 Terminal API 执行命令
  Future<TerminalResult> _runTerminalCommand(
    HermesApiClient client,
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    // 使用 Hermes Studio Terminal API 或 Devices API 执行命令
    // 这里通过 runChat 发送命令给 AI Agent 执行
    try {
      final result = await client.runChat(
        input: '执行以下命令并返回结果，不要修改任何文件：\n```\n$command\n```\n只返回命令输出，不要做其他操作。',
      );

      if (result.success) {
        return TerminalResult(
          success: true,
          output: result.content,
        );
      } else {
        return TerminalResult(
          success: false,
          error: result.error ?? '命令执行失败',
        );
      }
    } catch (e) {
      return TerminalResult(
        success: false,
        error: '命令执行异常: $e',
      );
    }
  }

  /// 克隆仓库
  Future<GitResult> clone({
    required String serverId,
    required String repoUrl,
    String? targetDirectory,
    String? branch,
  }) async {
    final target = targetDirectory ?? './repo';
    final branchFlag = branch != null ? '-b $branch ' : '';
    final command = 'git clone $branchFlag--depth 1 $repoUrl $target';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      timeout: const Duration(minutes: 10),
    );
  }

  /// 检出分支
  Future<GitResult> checkout({
    required String serverId,
    required String branch,
    String? workingDirectory,
    bool create = false,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final createFlag = create ? '-b ' : '';
    final command = '${dir}git checkout $createFlag$branch';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 提交更改
  Future<GitResult> commit({
    required String serverId,
    required String message,
    String? workingDirectory,
    bool addAll = true,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final addFlag = addAll && workingDirectory != null ? 'git add . && ' : '';
    final command = '${dir}${addFlag}git commit -m "$message"';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 推送
  Future<GitResult> push({
    required String serverId,
    String? remote,
    String? branch,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final remoteFlag = remote != null ? remote : 'origin';
    final branchFlag = branch != null ? branch : 'HEAD';
    final command = '${dir}git push $remoteFlag $branchFlag';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 拉取
  Future<GitResult> pull({
    required String serverId,
    String? remote,
    String? branch,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final remoteFlag = remote != null ? remote : 'origin';
    final branchFlag = branch != null ? branch : 'HEAD';
    final command = '${dir}git pull $remoteFlag $branchFlag';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 获取状态
  Future<GitResult> status({
    required String serverId,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}git status --porcelain';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 获取当前分支
  Future<GitResult> currentBranch({
    required String serverId,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}git rev-parse --abbrev-ref HEAD';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 获取分支列表
  Future<GitResult> listBranches({
    required String serverId,
    String? workingDirectory,
    bool all = false,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final allFlag = all ? '-a ' : '';
    final command = '${dir}git branch $allFlag--format="%(refname:short)"';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 创建合并请求（通过 GitHub/GitLab API）
  Future<GitResult> createMergeRequest({
    required String serverId,
    required String title,
    required String sourceBranch,
    required String targetBranch,
    String? description,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final desc = description ?? '自动创建的合并请求';
    
    // 尝试使用 GitHub CLI 或 GitLab CLI
    final command = '${dir}gh pr create --title "$title" --body "$desc" --head "$sourceBranch" --base "$targetBranch" 2>&1 || '
        'glab mr create --title "$title" --description "$desc" --source-branch "$sourceBranch" --target-branch "$targetBranch" 2>&1 || '
        'echo "请手动创建合并请求: $sourceBranch → $targetBranch"';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 合并分支
  Future<GitResult> merge({
    required String serverId,
    required String branch,
    String? targetBranch,
    String? workingDirectory,
    bool noFf = false,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final noFfFlag = noFf ? '--no-ff ' : '';
    
    if (targetBranch != null) {
      // 先切换到目标分支，再合并
      await checkout(serverId: serverId, branch: targetBranch, workingDirectory: workingDirectory);
    }
    
    final command = '${dir}git merge $noFfFlag$branch';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 获取日志
  Future<GitResult> log({
    required String serverId,
    String? workingDirectory,
    int count = 10,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}git log --oneline -$count';
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 获取差异
  Future<GitResult> diff({
    required String serverId,
    String? workingDirectory,
    String? branch1,
    String? branch2,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    String command;
    
    if (branch1 != null && branch2 != null) {
      command = '${dir}git diff $branch1..$branch2';
    } else {
      command = '${dir}git diff';
    }
    
    return executeGitCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }
}

/// SVN 桥接服务
class SvnBridge {
  final ServerProvider serverProvider;

  SvnBridge(this.serverProvider);

  /// 执行 SVN 命令
  Future<SvnResult> executeSvnCommand({
    required String serverId,
    required String command,
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    try {
      final server = serverProvider.servers
          .where((s) => s.id == serverId)
          .firstOrNull;
      if (server == null) {
        return SvnResult(success: false, error: '服务器未找到');
      }

      final client = HermesApiClient(server);
      final loggedIn = await client.ensureLoggedIn();
      if (!loggedIn) {
        return SvnResult(success: false, error: '服务器登录失败');
      }

      final result = await client.runChat(
        input: '执行以下 SVN 命令并返回结果，不要修改任何文件：\n```\n$command\n```\n只返回命令输出，不要做其他操作。',
      );

      if (result.success) {
        return SvnResult(success: true, output: result.content);
      } else {
        return SvnResult(success: false, error: result.error ?? '命令执行失败');
      }
    } catch (e) {
      return SvnResult(success: false, error: 'SVN 命令执行异常: $e');
    }
  }

  /// 检出仓库
  Future<SvnResult> checkout({
    required String serverId,
    required String repoUrl,
    String? targetDirectory,
  }) async {
    final target = targetDirectory ?? './svn-repo';
    final command = 'svn checkout $repoUrl $target';
    
    return executeSvnCommand(
      serverId: serverId,
      command: command,
      timeout: const Duration(minutes: 10),
    );
  }

  /// 更新
  Future<SvnResult> update({
    required String serverId,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}svn update';
    
    return executeSvnCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 提交
  Future<SvnResult> commit({
    required String serverId,
    required String message,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}svn commit -m "$message"';
    
    return executeSvnCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 添加文件
  Future<SvnResult> add({
    required String serverId,
    required String path,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}svn add $path';
    
    return executeSvnCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 获取状态
  Future<SvnResult> status({
    required String serverId,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}svn status';
    
    return executeSvnCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 获取日志
  Future<SvnResult> log({
    required String serverId,
    String? workingDirectory,
    int limit = 10,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}svn log --limit $limit';
    
    return executeSvnCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// 获取信息
  Future<SvnResult> info({
    required String serverId,
    String? workingDirectory,
  }) async {
    final dir = workingDirectory != null ? 'cd $workingDirectory && ' : '';
    final command = '${dir}svn info';
    
    return executeSvnCommand(
      serverId: serverId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }
}

/// 分支策略自动化
class BranchStrategyManager {
  final GitBridge gitBridge;

  BranchStrategyManager(this.gitBridge);

  /// Git Flow 策略
  Future<void> executeGitFlow({
    required String serverId,
    required String repoPath,
    required String featureName,
  }) async {
    // 1. 从 develop 创建 feature 分支
    await gitBridge.checkout(
      serverId: serverId,
      branch: 'develop',
      workingDirectory: repoPath,
    );
    
    await gitBridge.pull(serverId: serverId, workingDirectory: repoPath);
    
    await gitBridge.checkout(
      serverId: serverId,
      branch: 'feature/$featureName',
      workingDirectory: repoPath,
      create: true,
    );

    DebugLogger.instance.info('GitFlow: 创建 feature/$featureName 分支');
  }

  /// 完成 feature 分支
  Future<void> finishFeature({
    required String serverId,
    required String repoPath,
    required String featureName,
  }) async {
    // 1. 切换到 develop
    await gitBridge.checkout(
      serverId: serverId,
      branch: 'develop',
      workingDirectory: repoPath,
    );

    // 2. 合并 feature 分支
    await gitBridge.merge(
      serverId: serverId,
      branch: 'feature/$featureName',
      workingDirectory: repoPath,
      noFf: true,
    );

    // 3. 推送到远程
    await gitBridge.push(
      serverId: serverId,
      branch: 'develop',
      workingDirectory: repoPath,
    );

    DebugLogger.instance.info('GitFlow: 完成 feature/$featureName');
  }

  /// GitHub Flow 策略
  Future<void> executeGitHubFlow({
    required String serverId,
    required String repoPath,
    required String branchName,
  }) async {
    // 1. 从 main 创建分支
    await gitBridge.checkout(
      serverId: serverId,
      branch: 'main',
      workingDirectory: repoPath,
    );
    
    await gitBridge.pull(serverId: serverId, workingDirectory: repoPath);
    
    await gitBridge.checkout(
      serverId: serverId,
      branch: branchName,
      workingDirectory: repoPath,
      create: true,
    );

    DebugLogger.instance.info('GitHubFlow: 创建 $branchName 分支');
  }

  /// 创建发布分支
  Future<void> createReleaseBranch({
    required String serverId,
    required String repoPath,
    required String version,
  }) async {
    await gitBridge.checkout(
      serverId: serverId,
      branch: 'main',
      workingDirectory: repoPath,
    );
    
    await gitBridge.pull(serverId: serverId, workingDirectory: repoPath);
    
    await gitBridge.checkout(
      serverId: serverId,
      branch: 'release/$version',
      workingDirectory: repoPath,
      create: true,
    );

    DebugLogger.instance.info('Release: 创建 release/$version 分支');
  }
}

/// 冲突检测与解决
class ConflictDetector {
  /// 检测合并冲突
  Future<ConflictResult> detectConflicts({
    required GitBridge gitBridge,
    required String serverId,
    required String repoPath,
    required String sourceBranch,
    required String targetBranch,
  }) async {
    // 尝试合并，检查是否有冲突
    final mergeResult = await gitBridge.executeGitCommand(
      serverId: serverId,
      command: 'cd $repoPath && git merge --no-commit --no-ff $sourceBranch 2>&1 || true',
      workingDirectory: repoPath,
    );

    if (mergeResult.success && mergeResult.output?.contains('CONFLICT') == true) {
      // 获取冲突文件列表
      final statusResult = await gitBridge.status(
        serverId: serverId,
        workingDirectory: repoPath,
      );

      // 回滚合并
      await gitBridge.executeGitCommand(
        serverId: serverId,
        command: 'cd $repoPath && git merge --abort',
        workingDirectory: repoPath,
      );

      return ConflictResult(
        hasConflicts: true,
        conflictFiles: _parseConflictFiles(statusResult.output ?? ''),
        message: '检测到合并冲突',
      );
    }

    // 没有冲突，回滚测试合并
    await gitBridge.executeGitCommand(
      serverId: serverId,
      command: 'cd $repoPath && git merge --abort 2>/dev/null || true',
      workingDirectory: repoPath,
    );

    return ConflictResult(
      hasConflicts: false,
      conflictFiles: [],
      message: '无冲突，可以安全合并',
    );
  }

  /// 解析冲突文件列表
  List<String> _parseConflictFiles(String statusOutput) {
    final conflictFiles = <String>[];
    for (final line in statusOutput.split('\n')) {
      if (line.startsWith('UU') || line.startsWith('AA') || line.startsWith('DD')) {
        conflictFiles.add(line.substring(3).trim());
      }
    }
    return conflictFiles;
  }
}

/// Git 操作结果
class GitResult {
  final bool success;
  final String? output;
  final String? error;

  GitResult({
    required this.success,
    this.output,
    this.error,
  });
}

/// SVN 操作结果
class SvnResult {
  final bool success;
  final String? output;
  final String? error;

  SvnResult({
    required this.success,
    this.output,
    this.error,
  });
}

/// 终端执行结果
class TerminalResult {
  final bool success;
  final String? output;
  final String? error;

  TerminalResult({
    required this.success,
    this.output,
    this.error,
  });
}

/// 冲突检测结果
class ConflictResult {
  final bool hasConflicts;
  final List<String> conflictFiles;
  final String message;

  ConflictResult({
    required this.hasConflicts,
    required this.conflictFiles,
    required this.message,
  });
}
