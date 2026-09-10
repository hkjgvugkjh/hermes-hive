import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/providers/session_provider.dart';
import 'package:hermes_hive/reader/services/session_monitor_service.dart';

void main() {
  test('lazy init on first use', () async {
    final p = SessionProvider();
    expect(p.isInitialized, isFalse);

    await p.start();
    expect(p.isInitialized, isTrue);

    await p.stop();
    p.dispose();
  });

  test('isMonitoring true after start()', () async {
    final p = SessionProvider();
    await p.start();
    // start() sets _running=true immediately, regardless of targets.
    expect(p.isMonitoring, isTrue);
    await p.stop();
    p.dispose();
  });

  test('dispose cancels subscriptions without throw', () async {
    final p = SessionProvider();
    await p.start();
    p.dispose();
    expect(true, isTrue);
  });

  test('clearHistory empties list', () async {
    final p = SessionProvider();
    await p.start();
    p.clearHistory();
    expect(p.recentChanges, isEmpty);
    p.dispose();
  });
}
