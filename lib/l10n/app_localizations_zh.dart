// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Hermes Hive';

  @override
  String get addServer => '添加服务器';

  @override
  String get editServer => '编辑服务器';

  @override
  String get deleteServer => '删除服务器';

  @override
  String deleteServerConfirm(Object serverName) {
    return '确定要删除 \"$serverName\" 吗？';
  }

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get test => '测试';

  @override
  String get edit => '编辑';

  @override
  String get fetchFromProxy => '从代理获取';

  @override
  String get selectServerToChat => '选择一个服务器开始聊天';

  @override
  String get globalConfiguration => '全局配置';

  @override
  String get refreshServerList => '刷新服务器列表';

  @override
  String get supportedEndpoints => '支持的端点：';

  @override
  String get model => '模型：';

  @override
  String get selectModel => '选择模型';

  @override
  String get clearAllPrompts => '清空所有提示词';

  @override
  String get clearAllPromptsConfirm => '确定要删除所有保存的提示词吗？';

  @override
  String get clear => '清空';

  @override
  String get close => '关闭';

  @override
  String get loginRequired => '需要登录';

  @override
  String loginPrompt(Object serverName) {
    return '请输入凭据以访问 $serverName';
  }

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get login => '登录';

  @override
  String get loggingIn => '登录中...';

  @override
  String get loginFailed => '登录失败';

  @override
  String get thinking => '思考中...';

  @override
  String get typeMessage => '输入消息...';

  @override
  String emptyResponses(Object count) {
    return '$count 条空回复';
  }

  @override
  String get noSessions => '暂无会话';

  @override
  String get noMessages => '暂无消息';

  @override
  String get debugLog => '调试日志';

  @override
  String get server => '服务器';

  @override
  String get proxy => '代理';

  @override
  String get standalone => '独立模式';

  @override
  String get settings => '设置';

  @override
  String get language => '语言';

  @override
  String get english => 'English';

  @override
  String get chinese => '中文';

  @override
  String get encryptionAlwaysEnabled => '加密始终启用（X25519 + ChaCha20-Poly1305）';

  @override
  String get proxyUrl => '代理地址';

  @override
  String get proxyToken => '代理令牌';

  @override
  String get connectionMode => '连接模式';

  @override
  String get hermesProxy => 'Hermes 代理';

  @override
  String get standaloneMode => '独立模式';

  @override
  String get serverName => '服务器名称';

  @override
  String get serverUrl => '服务器地址';

  @override
  String get profile => '配置文件';

  @override
  String get useAuth => '使用认证';

  @override
  String get connectionTestSuccess => '连接测试成功';

  @override
  String get connectionTestFailed => '连接测试失败';

  @override
  String proxyFetchSuccess(Object count) {
    return '成功获取 $count 个服务器';
  }

  @override
  String get proxyFetchFailed => '从代理获取服务器失败';

  @override
  String get servers => '服务器';

  @override
  String get online => '在线';

  @override
  String get offline => '离线';

  @override
  String get send => '发送';

  @override
  String get prompts => '提示词';

  @override
  String get savedPrompts => '已保存提示词';

  @override
  String get noPrompts => '暂无保存的提示词';

  @override
  String get clickToInsert => '点击插入';

  @override
  String get noServers => '暂无服务器';

  @override
  String get fetchFromProxyHint => '点击 \"从代理获取\" 加载服务器';

  @override
  String get addServerHint => '点击 + 添加 Hermes Studio 服务器';

  @override
  String get untitled => '未命名';

  @override
  String get proxyModeHint => 'Hermes 代理模式 — 从代理获取服务器';

  @override
  String get standaloneModeHint => '独立模式 — 直接连接';

  @override
  String get serverNameHint => 'My Hermes Server';

  @override
  String get enterServerName => '请输入服务器名称';

  @override
  String get enterServerUrl => '请输入服务器地址';

  @override
  String get enterValidUrl => '请输入有效的地址';

  @override
  String get profileHelper => '此服务器使用的 Hermes 配置文件';

  @override
  String get enterUsername => '请输入用户名';

  @override
  String get enterPassword => '请输入密码';

  @override
  String get selectProxyServer => '从代理的服务器列表中选择';

  @override
  String availableServers(Object count) {
    return '可用服务器 ($count)';
  }

  @override
  String get enabled => '已启用';

  @override
  String get disabled => '已禁用';

  @override
  String get connectionInfo => '连接信息';

  @override
  String get proxyConnectionInfo =>
      'Hermes 代理：WebSocket + X25519 密钥交换\n独立模式：直接 HTTP/WebSocket 连接';

  @override
  String get noPromptsHint => '暂无保存的提示词。\n用户消息将自动保存在这里。';

  @override
  String get sessionsList => '会话列表';

  @override
  String get newSession => '新建会话';

  @override
  String get startConversation => '开始对话';

  @override
  String typeToBegin(Object serverName) {
    return '在下方输入消息，开始与 $serverName 对话';
  }

  @override
  String get enterProxyUrl => '请输入代理地址';

  @override
  String get enterValidProxyUrl => '请输入有效的地址';

  @override
  String get proxyTokenHint => '代理管理员认证令牌';

  @override
  String get adminTokenRequired => 'Hermes 代理模式需要管理员令牌';

  @override
  String get modeDescription => '模式说明';

  @override
  String get proxyModeDesc => '通过 Hermes 代理连接，从代理获取服务器列表';

  @override
  String get standaloneModeDesc => '直接连接 Hermes Studio 服务器，手动添加服务器';

  @override
  String get proxyModeInfo =>
      'Hermes 代理模式：\n- 流量使用 X25519 + ChaCha20-Poly1305 加密\n- 从代理获取服务器列表\n- 通过代理管理员令牌认证';

  @override
  String get standaloneModeInfo =>
      '独立模式：\n- 直接 HTTP/WebSocket 连接\n- 手动添加服务器\n- 可选的每服务器认证';

  @override
  String get connectionSuccess => '连接成功！代理可达。';

  @override
  String get authFailed => '认证失败：管理员令牌无效';

  @override
  String httpFailed(Object statusCode) {
    return '失败：HTTP $statusCode';
  }

  @override
  String connectionFailed(Object error) {
    return '连接失败：$error';
  }

  @override
  String get eggOfToday => '今日鸡蛋';

  @override
  String get openRouterConfig => 'OpenRouter 配置';

  @override
  String get refreshAll => '全部刷新';

  @override
  String get apiUrl => 'API 地址';

  @override
  String get apiKey => 'API 密钥';

  @override
  String get freeModels => '免费模型';

  @override
  String get fetchModels => '获取模型';

  @override
  String get noFreeModels => '暂无免费模型。请配置 API 密钥后获取。';

  @override
  String selectedCount(Object count) {
    return '已选择 $count 个';
  }

  @override
  String get createCombination => '创建组合';

  @override
  String get modelCombinations => '模型组合';

  @override
  String get noCombinations => '暂无组合。请选择模型后创建。';

  @override
  String get checkAvailability => '检查可用性';

  @override
  String get combinationName => '组合名称';

  @override
  String get combinationNameHint => '例如：我的免费栈';

  @override
  String get create => '创建';

  @override
  String get deleteCombination => '删除组合';

  @override
  String deleteCombinationConfirm(Object name) {
    return '确定要删除 \"$name\" 吗？';
  }

  @override
  String get available => '可用';

  @override
  String get unavailable => '不可用';

  @override
  String get autoContinueMode => '自动继续模式';

  @override
  String get allSessions => '所有';

  @override
  String get recentSessions => '最近';

  @override
  String get inProgress => '进行中';

  @override
  String get completed => '已完成';
}
