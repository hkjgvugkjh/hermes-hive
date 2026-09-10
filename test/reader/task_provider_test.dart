import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/providers/task_provider.dart';
import 'package:hermes_hive/reader/screens/task_list_screen.dart';
import 'package:provider/provider.dart';

void main() {
  test('TaskProvider.addTask + resolve lifecycle', () async {
    final p = TaskProvider();
    p.addTask(TaskItem(
      id: '1',
      title: '会话待处理',
      description: '需要用户输入',
      serverId: 'srv-1',
      createdAt: DateTime.now(),
    ));
    expect(p.tasks.length, 1);
    expect(p.unresolved.length, 1);

    p.resolve('1');
    expect(p.tasks.first.resolved, isTrue);
    expect(p.unresolved, isEmpty);

    p.remove('1');
    expect(p.tasks, isEmpty);
  });

  test('TaskProvider enforces insertion order', () async {
    final p = TaskProvider();
    for (var i = 0; i < 3; i++) {
      p.addTask(TaskItem(
        id: '$i',
        title: 'T$i',
        description: '',
        serverId: 's',
        createdAt: DateTime.now(),
      ));
    }
    expect(p.tasks[0].id, '2'); // most recent first
    expect(p.tasks[1].id, '1');
    expect(p.tasks[2].id, '0');
  });

  testWidgets('TaskListScreen renders empty state', (tester) async {
    final p = TaskProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: p,
        child: const MaterialApp(home: TaskListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无待处理事项'), findsOneWidget);
    expect(find.text('待处理事项'), findsOneWidget);
  });

  testWidgets('TaskListScreen shows tasks', (tester) async {
    final p = TaskProvider();
    p.addTask(TaskItem(
      id: '1',
      title: '修复构建',
      description: 'build.sh 第 42 行报错',
      serverId: 'local',
      createdAt: DateTime.now(),
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: p,
        child: const MaterialApp(home: TaskListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('修复构建'), findsOneWidget);
    expect(find.text('build.sh 第 42 行报错'), findsOneWidget);
    expect(find.text('local'), findsOneWidget);
  });
}
