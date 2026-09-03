import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/version_control_provider.dart';
import 'providers/server_provider.dart';
import 'services/dashboard_service.dart';
import 'providers/pipeline_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/global_config_provider.dart';
import 'providers/debug_logger.dart';
import 'providers/prompt_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/egg_provider.dart';
import 'screens/home_screen.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(const HermesHiveApp());
}

class HermesHiveApp extends StatelessWidget {
  const HermesHiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GlobalConfigProvider()),
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => DebugLogger.instance),
        ChangeNotifierProvider(create: (_) => PromptProvider()..init()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => EggProvider()),
        ChangeNotifierProxyProvider<ServerProvider, PipelineProvider>(
          create: (context) => PipelineProvider(context.read<ServerProvider>()),
          update: (context, serverProvider, previous) => previous ?? PipelineProvider(serverProvider),
        ),
        ChangeNotifierProxyProvider<ServerProvider, VersionControlProvider>(
          create: (context) => VersionControlProvider(context.read<ServerProvider>()),
          update: (context, serverProvider, previous) => previous ?? VersionControlProvider(serverProvider),
        ),
        ChangeNotifierProxyProvider2<ServerProvider, PipelineProvider, DashboardProvider>(
          create: (context) => DashboardProvider(
            serverProvider: context.read<ServerProvider>(),
            pipelineProvider: context.read<PipelineProvider>(),
          ),
          update: (context, serverProvider, pipelineProvider, previous) =>
              previous ?? DashboardProvider(serverProvider: serverProvider, pipelineProvider: pipelineProvider),
        ),
        ChangeNotifierProxyProvider2<GlobalConfigProvider, ServerProvider, ChatProvider>(
          create: (context) => ChatProvider(
            context.read<ServerProvider>(),
            context.read<GlobalConfigProvider>(),
          ),
          update: (context, globalConfig, serverProvider, previous) =>
              previous ?? ChatProvider(serverProvider, globalConfig),
        ),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
            title: 'Hermes Hive',
            debugShowCheckedModeBanner: false,
            locale: localeProvider.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('en', 'US'),
            ],
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6750A4),
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              cardTheme: CardThemeData(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6750A4),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              cardTheme: CardThemeData(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            themeMode: ThemeMode.system,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
