import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Hermes Hive'**
  String get appTitle;

  /// No description provided for @addServer.
  ///
  /// In zh, this message translates to:
  /// **'添加服务器'**
  String get addServer;

  /// No description provided for @editServer.
  ///
  /// In zh, this message translates to:
  /// **'编辑服务器'**
  String get editServer;

  /// No description provided for @deleteServer.
  ///
  /// In zh, this message translates to:
  /// **'删除服务器'**
  String get deleteServer;

  /// No description provided for @deleteServerConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除 \"{serverName}\" 吗？'**
  String deleteServerConfirm(Object serverName);

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @test.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get test;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @fetchFromProxy.
  ///
  /// In zh, this message translates to:
  /// **'从代理获取'**
  String get fetchFromProxy;

  /// No description provided for @selectServerToChat.
  ///
  /// In zh, this message translates to:
  /// **'选择一个服务器开始聊天'**
  String get selectServerToChat;

  /// No description provided for @globalConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'全局配置'**
  String get globalConfiguration;

  /// No description provided for @refreshServerList.
  ///
  /// In zh, this message translates to:
  /// **'刷新服务器列表'**
  String get refreshServerList;

  /// No description provided for @supportedEndpoints.
  ///
  /// In zh, this message translates to:
  /// **'支持的端点：'**
  String get supportedEndpoints;

  /// No description provided for @model.
  ///
  /// In zh, this message translates to:
  /// **'模型：'**
  String get model;

  /// No description provided for @selectModel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get selectModel;

  /// No description provided for @clearAllPrompts.
  ///
  /// In zh, this message translates to:
  /// **'清空所有提示词'**
  String get clearAllPrompts;

  /// No description provided for @clearAllPromptsConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除所有保存的提示词吗？'**
  String get clearAllPromptsConfirm;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @loginRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要登录'**
  String get loginRequired;

  /// No description provided for @loginPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请输入凭据以访问 {serverName}'**
  String loginPrompt(Object serverName);

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @loggingIn.
  ///
  /// In zh, this message translates to:
  /// **'登录中...'**
  String get loggingIn;

  /// No description provided for @loginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败'**
  String get loginFailed;

  /// No description provided for @thinking.
  ///
  /// In zh, this message translates to:
  /// **'思考中...'**
  String get thinking;

  /// No description provided for @typeMessage.
  ///
  /// In zh, this message translates to:
  /// **'输入消息...'**
  String get typeMessage;

  /// No description provided for @emptyResponses.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条空回复'**
  String emptyResponses(Object count);

  /// No description provided for @noSessions.
  ///
  /// In zh, this message translates to:
  /// **'暂无会话'**
  String get noSessions;

  /// No description provided for @noMessages.
  ///
  /// In zh, this message translates to:
  /// **'暂无消息'**
  String get noMessages;

  /// No description provided for @debugLog.
  ///
  /// In zh, this message translates to:
  /// **'调试日志'**
  String get debugLog;

  /// No description provided for @server.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get server;

  /// No description provided for @proxy.
  ///
  /// In zh, this message translates to:
  /// **'代理'**
  String get proxy;

  /// No description provided for @standalone.
  ///
  /// In zh, this message translates to:
  /// **'独立模式'**
  String get standalone;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @english.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @chinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get chinese;

  /// No description provided for @encryptionAlwaysEnabled.
  ///
  /// In zh, this message translates to:
  /// **'加密始终启用（X25519 + ChaCha20-Poly1305）'**
  String get encryptionAlwaysEnabled;

  /// No description provided for @proxyUrl.
  ///
  /// In zh, this message translates to:
  /// **'代理地址'**
  String get proxyUrl;

  /// No description provided for @proxyToken.
  ///
  /// In zh, this message translates to:
  /// **'代理令牌'**
  String get proxyToken;

  /// No description provided for @connectionMode.
  ///
  /// In zh, this message translates to:
  /// **'连接模式'**
  String get connectionMode;

  /// No description provided for @hermesProxy.
  ///
  /// In zh, this message translates to:
  /// **'Hermes 代理'**
  String get hermesProxy;

  /// No description provided for @standaloneMode.
  ///
  /// In zh, this message translates to:
  /// **'独立模式'**
  String get standaloneMode;

  /// No description provided for @serverName.
  ///
  /// In zh, this message translates to:
  /// **'服务器名称'**
  String get serverName;

  /// No description provided for @serverUrl.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverUrl;

  /// No description provided for @profile.
  ///
  /// In zh, this message translates to:
  /// **'配置文件'**
  String get profile;

  /// No description provided for @useAuth.
  ///
  /// In zh, this message translates to:
  /// **'使用认证'**
  String get useAuth;

  /// No description provided for @connectionTestSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接测试成功'**
  String get connectionTestSuccess;

  /// No description provided for @connectionTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接测试失败'**
  String get connectionTestFailed;

  /// No description provided for @proxyFetchSuccess.
  ///
  /// In zh, this message translates to:
  /// **'成功获取 {count} 个服务器'**
  String proxyFetchSuccess(Object count);

  /// No description provided for @proxyFetchFailed.
  ///
  /// In zh, this message translates to:
  /// **'从代理获取服务器失败'**
  String get proxyFetchFailed;

  /// No description provided for @servers.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get servers;

  /// No description provided for @online.
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In zh, this message translates to:
  /// **'离线'**
  String get offline;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @prompts.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get prompts;

  /// No description provided for @savedPrompts.
  ///
  /// In zh, this message translates to:
  /// **'已保存提示词'**
  String get savedPrompts;

  /// No description provided for @noPrompts.
  ///
  /// In zh, this message translates to:
  /// **'暂无保存的提示词'**
  String get noPrompts;

  /// No description provided for @clickToInsert.
  ///
  /// In zh, this message translates to:
  /// **'点击插入'**
  String get clickToInsert;

  /// No description provided for @noServers.
  ///
  /// In zh, this message translates to:
  /// **'暂无服务器'**
  String get noServers;

  /// No description provided for @fetchFromProxyHint.
  ///
  /// In zh, this message translates to:
  /// **'点击 \"从代理获取\" 加载服务器'**
  String get fetchFromProxyHint;

  /// No description provided for @addServerHint.
  ///
  /// In zh, this message translates to:
  /// **'点击 + 添加 Hermes Studio 服务器'**
  String get addServerHint;

  /// No description provided for @untitled.
  ///
  /// In zh, this message translates to:
  /// **'未命名'**
  String get untitled;

  /// No description provided for @proxyModeHint.
  ///
  /// In zh, this message translates to:
  /// **'Hermes 代理模式 — 从代理获取服务器'**
  String get proxyModeHint;

  /// No description provided for @standaloneModeHint.
  ///
  /// In zh, this message translates to:
  /// **'独立模式 — 直接连接'**
  String get standaloneModeHint;

  /// No description provided for @serverNameHint.
  ///
  /// In zh, this message translates to:
  /// **'My Hermes Server'**
  String get serverNameHint;

  /// No description provided for @enterServerName.
  ///
  /// In zh, this message translates to:
  /// **'请输入服务器名称'**
  String get enterServerName;

  /// No description provided for @enterServerUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入服务器地址'**
  String get enterServerUrl;

  /// No description provided for @enterValidUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的地址'**
  String get enterValidUrl;

  /// No description provided for @profileHelper.
  ///
  /// In zh, this message translates to:
  /// **'此服务器使用的 Hermes 配置文件'**
  String get profileHelper;

  /// No description provided for @enterUsername.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名'**
  String get enterUsername;

  /// No description provided for @enterPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get enterPassword;

  /// No description provided for @selectProxyServer.
  ///
  /// In zh, this message translates to:
  /// **'从代理的服务器列表中选择'**
  String get selectProxyServer;

  /// No description provided for @availableServers.
  ///
  /// In zh, this message translates to:
  /// **'可用服务器 ({count})'**
  String availableServers(Object count);

  /// No description provided for @enabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In zh, this message translates to:
  /// **'已禁用'**
  String get disabled;

  /// No description provided for @connectionInfo.
  ///
  /// In zh, this message translates to:
  /// **'连接信息'**
  String get connectionInfo;

  /// No description provided for @proxyConnectionInfo.
  ///
  /// In zh, this message translates to:
  /// **'Hermes 代理：WebSocket + X25519 密钥交换\n独立模式：直接 HTTP/WebSocket 连接'**
  String get proxyConnectionInfo;

  /// No description provided for @noPromptsHint.
  ///
  /// In zh, this message translates to:
  /// **'暂无保存的提示词。\n用户消息将自动保存在这里。'**
  String get noPromptsHint;

  /// No description provided for @sessionsList.
  ///
  /// In zh, this message translates to:
  /// **'会话列表'**
  String get sessionsList;

  /// No description provided for @newSession.
  ///
  /// In zh, this message translates to:
  /// **'新建会话'**
  String get newSession;

  /// No description provided for @startConversation.
  ///
  /// In zh, this message translates to:
  /// **'开始对话'**
  String get startConversation;

  /// No description provided for @typeToBegin.
  ///
  /// In zh, this message translates to:
  /// **'在下方输入消息，开始与 {serverName} 对话'**
  String typeToBegin(Object serverName);

  /// No description provided for @enterProxyUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入代理地址'**
  String get enterProxyUrl;

  /// No description provided for @enterValidProxyUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的地址'**
  String get enterValidProxyUrl;

  /// No description provided for @proxyTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'代理管理员认证令牌'**
  String get proxyTokenHint;

  /// No description provided for @adminTokenRequired.
  ///
  /// In zh, this message translates to:
  /// **'Hermes 代理模式需要管理员令牌'**
  String get adminTokenRequired;

  /// No description provided for @modeDescription.
  ///
  /// In zh, this message translates to:
  /// **'模式说明'**
  String get modeDescription;

  /// No description provided for @proxyModeDesc.
  ///
  /// In zh, this message translates to:
  /// **'通过 Hermes 代理连接，从代理获取服务器列表'**
  String get proxyModeDesc;

  /// No description provided for @standaloneModeDesc.
  ///
  /// In zh, this message translates to:
  /// **'直接连接 Hermes Studio 服务器，手动添加服务器'**
  String get standaloneModeDesc;

  /// No description provided for @proxyModeInfo.
  ///
  /// In zh, this message translates to:
  /// **'Hermes 代理模式：\n- 流量使用 X25519 + ChaCha20-Poly1305 加密\n- 从代理获取服务器列表\n- 通过代理管理员令牌认证'**
  String get proxyModeInfo;

  /// No description provided for @standaloneModeInfo.
  ///
  /// In zh, this message translates to:
  /// **'独立模式：\n- 直接 HTTP/WebSocket 连接\n- 手动添加服务器\n- 可选的每服务器认证'**
  String get standaloneModeInfo;

  /// No description provided for @connectionSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接成功！代理可达。'**
  String get connectionSuccess;

  /// No description provided for @authFailed.
  ///
  /// In zh, this message translates to:
  /// **'认证失败：管理员令牌无效'**
  String get authFailed;

  /// No description provided for @httpFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败：HTTP {statusCode}'**
  String httpFailed(Object statusCode);

  /// No description provided for @connectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{error}'**
  String connectionFailed(Object error);

  /// No description provided for @eggOfToday.
  ///
  /// In zh, this message translates to:
  /// **'今日鸡蛋'**
  String get eggOfToday;

  /// No description provided for @openRouterConfig.
  ///
  /// In zh, this message translates to:
  /// **'OpenRouter 配置'**
  String get openRouterConfig;

  /// No description provided for @refreshAll.
  ///
  /// In zh, this message translates to:
  /// **'全部刷新'**
  String get refreshAll;

  /// No description provided for @apiUrl.
  ///
  /// In zh, this message translates to:
  /// **'API 地址'**
  String get apiUrl;

  /// No description provided for @apiKey.
  ///
  /// In zh, this message translates to:
  /// **'API 密钥'**
  String get apiKey;

  /// No description provided for @freeModels.
  ///
  /// In zh, this message translates to:
  /// **'免费模型'**
  String get freeModels;

  /// No description provided for @fetchModels.
  ///
  /// In zh, this message translates to:
  /// **'获取模型'**
  String get fetchModels;

  /// No description provided for @noFreeModels.
  ///
  /// In zh, this message translates to:
  /// **'暂无免费模型。请配置 API 密钥后获取。'**
  String get noFreeModels;

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 个'**
  String selectedCount(Object count);

  /// No description provided for @createCombination.
  ///
  /// In zh, this message translates to:
  /// **'创建组合'**
  String get createCombination;

  /// No description provided for @modelCombinations.
  ///
  /// In zh, this message translates to:
  /// **'模型组合'**
  String get modelCombinations;

  /// No description provided for @noCombinations.
  ///
  /// In zh, this message translates to:
  /// **'暂无组合。请选择模型后创建。'**
  String get noCombinations;

  /// No description provided for @checkAvailability.
  ///
  /// In zh, this message translates to:
  /// **'检查可用性'**
  String get checkAvailability;

  /// No description provided for @combinationName.
  ///
  /// In zh, this message translates to:
  /// **'组合名称'**
  String get combinationName;

  /// No description provided for @combinationNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：我的免费栈'**
  String get combinationNameHint;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @deleteCombination.
  ///
  /// In zh, this message translates to:
  /// **'删除组合'**
  String get deleteCombination;

  /// No description provided for @deleteCombinationConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除 \"{name}\" 吗？'**
  String deleteCombinationConfirm(Object name);

  /// No description provided for @available.
  ///
  /// In zh, this message translates to:
  /// **'可用'**
  String get available;

  /// No description provided for @unavailable.
  ///
  /// In zh, this message translates to:
  /// **'不可用'**
  String get unavailable;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
