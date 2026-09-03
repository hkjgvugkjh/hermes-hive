import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_models.dart';
import '../providers/debug_logger.dart';

/// 状态持久化服务 — 保存和恢复流水线状态
class PipelinePersistence {
  static const String _projectsKey = 'hermes_hive_projects';
  static const String _pipelinesKey = 'hermes_hive_pipelines';
  static const String _activeProjectKey = 'hermes_hive_active_project';

  /// 保存项目列表
  Future<void> saveProjects(List<Project> projects) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = projects.map((p) => p.toJson()).toList();
      await prefs.setString(_projectsKey, jsonEncode(json));
      DebugLogger.instance.info('Persistence: 保存 ${projects.length} 个项目');
    } catch (e) {
      DebugLogger.instance.error('Persistence: 保存项目失败', e.toString());
    }
  }

  /// 加载项目列表
  Future<List<Project>> loadProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_projectsKey);
      if (data == null) return [];
      
      final List<dynamic> json = jsonDecode(data);
      final projects = json
          .map((j) => Project.fromJson(j as Map<String, dynamic>))
          .toList();
      DebugLogger.instance.info('Persistence: 加载 ${projects.length} 个项目');
      return projects;
    } catch (e) {
      DebugLogger.instance.error('Persistence: 加载项目失败', e.toString());
      return [];
    }
  }

  /// 保存流水线列表
  Future<void> savePipelines(String projectId, List<Pipeline> pipelines) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_pipelinesKey\_$projectId';
      final json = pipelines.map((p) => p.toJson()).toList();
      await prefs.setString(key, jsonEncode(json));
      DebugLogger.instance.info('Persistence: 保存项目 $projectId 的 ${pipelines.length} 条流水线');
    } catch (e) {
      DebugLogger.instance.error('Persistence: 保存流水线失败', e.toString());
    }
  }

  /// 加载流水线列表
  Future<List<Pipeline>> loadPipelines(String projectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_pipelinesKey\_$projectId';
      final data = prefs.getString(key);
      if (data == null) return [];
      
      final List<dynamic> json = jsonDecode(data);
      final pipelines = json
          .map((j) => Pipeline.fromJson(j as Map<String, dynamic>))
          .toList();
      DebugLogger.instance.info('Persistence: 加载项目 $projectId 的 ${pipelines.length} 条流水线');
      return pipelines;
    } catch (e) {
      DebugLogger.instance.error('Persistence: 加载流水线失败', e.toString());
      return [];
    }
  }

  /// 保存当前活跃项目
  Future<void> saveActiveProject(String projectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeProjectKey, projectId);
    } catch (e) {
      DebugLogger.instance.error('Persistence: 保存活跃项目失败', e.toString());
    }
  }

  /// 加载当前活跃项目
  Future<String?> loadActiveProject() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_activeProjectKey);
    } catch (e) {
      DebugLogger.instance.error('Persistence: 加载活跃项目失败', e.toString());
      return null;
    }
  }

  /// 清除所有数据
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_projectsKey);
      await prefs.remove(_activeProjectKey);
      DebugLogger.instance.info('Persistence: 清除所有数据');
    } catch (e) {
      DebugLogger.instance.error('Persistence: 清除数据失败', e.toString());
    }
  }
}
