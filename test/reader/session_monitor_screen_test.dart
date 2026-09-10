import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/providers/server_provider.dart';
import 'package:hermes_hive/reader/providers/session_provider.dart';
import 'package:hermes_hive/reader/screens/session_monitor_screen.dart';
import 'package:hermes_hive/reader/services/session_monitor_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('SessionMonitorScreen shows empty state', (tester) async {
    final mock = MockClient((req) async {
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'});
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SessionProvider()),
          ChangeNotifierProvider(create: (_) => ServerProvider()),
        ],
        child: const MaterialApp(home: SessionMonitorScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('会话监控'), findsOneWidget);
    expect(find.text('暂无变更事件'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.delete_sweep), findsOneWidget);
  });

  test('SessionProvider.maxHistory default is 50', () async {
    final p = SessionProvider();
    expect(p.maxHistory, 50);
    p.dispose();
  });

  test('SessionProvider.recentChanges is unmodifiable', () async {
    final p = SessionProvider();
    final list = p.recentChanges;
    expect(
        () => list.add(SessionChange(
              kind: SessionChangeKind.sessionStarted,
              serverId: 'x',
            )),
        throwsUnsupportedError);
    p.dispose();
  });
}
