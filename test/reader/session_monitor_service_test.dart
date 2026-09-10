import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/services/session_monitor_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SessionSnapshot', () {
    test('parses id + title from hermes-style session', () {
      final snap = SessionSnapshot.fromJson({
        'id': 'sess-42',
        'title': '代码审查任务',
        'updated_at': '2026-09-06T10:30:00.000Z',
        'status': 'running',
      });
      expect(snap.id, 'sess-42');
      expect(snap.title, '代码审查任务');
      expect(snap.state, SessionState.running);
    });

    test('parses fallback title keys (name)', () {
      final snap = SessionSnapshot.fromJson({'id': 'x', 'name': 'Legacy Name'});
      expect(snap.title, 'Legacy Name');
    });

    test('falls back to untitled when no title key', () {
      final snap = SessionSnapshot.fromJson({'id': 'y'});
      expect(snap.title, 'untitled');
    });

    test('detects completed state', () {
      final s = SessionSnapshot.fromJson({'id': '1', 'completed': true});
      expect(s.state, SessionState.stopped);
    });

    test('detects pending state via needs_input', () {
      final s = SessionSnapshot.fromJson({'id': '1', 'needs_input': true});
      expect(s.state, SessionState.pending);
    });

    test('detects error state', () {
      final s = SessionSnapshot.fromJson({'id': '1', 'status': 'error'});
      expect(s.state, SessionState.error);
    });

    test('default state is running', () {
      final s = SessionSnapshot.fromJson({'id': '1', 'title': 'T'});
      expect(s.state, SessionState.running);
    });
  });

  group('MonitorTarget defaults', () {
    test('sensible defaults', () {
      const t = MonitorTarget(serverId: 'a', baseUrl: 'http://h:3000');
      expect(t.pollInterval, const Duration(seconds: 60));
      expect(t.stoppedThreshold, const Duration(seconds: 90));
      expect(t.authToken, isNull);
    });
  });

  group('SessionMonitorService (via MockClient)', () {
    test('parses list response', () async {
      final mock = MockClient((req) async {
        expect(req.url.path, '/api/hermes/sessions');
        return http.Response(
          jsonEncode([
            {'id': '1', 'title': 'A'},
            {'id': '2', 'title': 'B'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = SessionMonitorService(client: mock);
      // Just verify no throw during a full cycle.
      svc.addTarget(const MonitorTarget(serverId: 'a', baseUrl: 'http://h'));
      await svc.pollNow('a');
      await Future.delayed(Duration.zero);
      await svc.stop();
    });

    test('emits sessionStarted when new session appears', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode([
            {'id': '1', 'title': 'A'},
            {'id': '2', 'title': 'B'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = SessionMonitorService(client: mock);
      final received = <SessionChange>[];
      svc.changes.listen(received.add);

      svc.addTarget(const MonitorTarget(
          serverId: 'a',
          baseUrl: 'http://h:3000',
          pollInterval: Duration(milliseconds: 50)));
      await svc.start();
      await Future.delayed(const Duration(milliseconds: 120));
      await svc.stop();

      expect(received.any((c) => c.kind == SessionChangeKind.sessionStarted), isTrue);
    });

    test('401 emits authRequired', () async {
      final mock = MockClient((req) async => http.Response('{}', 401));
      final svc = SessionMonitorService(client: mock);
      final received = <SessionChange>[];
      svc.changes.listen(received.add);

      svc.addTarget(const MonitorTarget(serverId: 'a', baseUrl: 'http://h'));
      await svc.start();
      await Future.delayed(Duration.zero);

      expect(received.any((c) => c.kind == SessionChangeKind.authRequired), isTrue);
      await svc.stop();
    });

    test('500 emits serverError', () async {
      final mock = MockClient((req) async => http.Response('{}', 500));
      final svc = SessionMonitorService(client: mock);
      final received = <SessionChange>[];
      svc.changes.listen(received.add);

      svc.addTarget(const MonitorTarget(serverId: 'a', baseUrl: 'http://h'));
      await svc.start();
      await Future.delayed(Duration.zero);

      expect(received.any((c) => c.kind == SessionChangeKind.serverError), isTrue);
      await svc.stop();
    });

    test('sessionStopped emitted when state changes running->stopped', () async {
      var toggle = false;
      final mock = MockClient((req) async {
        if (!toggle) {
          toggle = true;
          return http.Response(
            jsonEncode([
              {'id': '1', 'title': 'X', 'status': 'running'}
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([
            {'id': '1', 'title': 'X', 'status': 'completed'}
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = SessionMonitorService(client: mock);
      final received = <SessionChange>[];
      svc.changes.listen(received.add);

      svc.addTarget(const MonitorTarget(
          serverId: 'a',
          baseUrl: 'http://h',
          pollInterval: Duration(milliseconds: 50)));
      await svc.start();
      await Future.delayed(const Duration(milliseconds: 120));
      await svc.stop();

      expect(received.any((c) => c.kind == SessionChangeKind.sessionStopped), isTrue);
    });

    test('sessionNeedsInput emitted when state becomes pending', () async {
      var toggle = false;
      final mock = MockClient((req) async {
        if (!toggle) {
          toggle = true;
          return http.Response(
            jsonEncode([
              {'id': '1', 'title': 'X', 'status': 'running'}
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([
            {'id': '1', 'title': 'X', 'needs_input': true}
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = SessionMonitorService(client: mock);
      final received = <SessionChange>[];
      svc.changes.listen(received.add);

      svc.addTarget(const MonitorTarget(
          serverId: 'a',
          baseUrl: 'http://h',
          pollInterval: Duration(milliseconds: 50)));
      await svc.start();
      await Future.delayed(const Duration(milliseconds: 120));
      await svc.stop();

      expect(received.any((c) => c.kind == SessionChangeKind.sessionNeedsInput), isTrue);
    });

    test('does NOT double-notify stopped for same session', () async {
      var step = 0;
      final mock = MockClient((req) async {
        step++;
        if (step == 1) {
          return http.Response(
            jsonEncode([
              {'id': '1', 'title': 'X', 'status': 'running'}
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([
            {'id': '1', 'title': 'X', 'status': 'completed'}
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = SessionMonitorService(client: mock);
      final received = <SessionChange>[];
      svc.changes.listen(received.add);

      svc.addTarget(const MonitorTarget(
          serverId: 'a',
          baseUrl: 'http://h',
          pollInterval: Duration(milliseconds: 50)));
      await svc.start();
      await Future.delayed(const Duration(milliseconds: 200));
      await svc.stop();

      final stops = received.where((c) => c.kind == SessionChangeKind.sessionStopped).length;
      expect(stops, 1);
    });

    test('Authorization header sent when token set', () async {
      String? seenAuth;
      final mock = MockClient((req) async {
        seenAuth = req.headers['authorization'];
        return http.Response('[]', 200);
      });
      final svc = SessionMonitorService(client: mock);
      svc.addTarget(const MonitorTarget(
          serverId: 'a', baseUrl: 'http://h', authToken: 'tok-1'));
      await svc.start();

      expect(seenAuth, 'Bearer tok-1');
      await svc.stop();
    });

    test('setToken overrides initial token', () async {
      String? seenAuth;
      final mock = MockClient((req) async {
        seenAuth = req.headers['authorization'];
        return http.Response('[]', 200);
      });
      final svc = SessionMonitorService(client: mock);
      svc.addTarget(const MonitorTarget(
          serverId: 'a', baseUrl: 'http://h', authToken: 'old'));
      svc.setToken('a', 'new');
      await svc.start();

      expect(seenAuth, 'Bearer new');
      await svc.stop();
    });

    test('addTarget + removeTarget lifecycle', () async {
      final mock = MockClient((req) async => http.Response('[]', 200));
      final svc = SessionMonitorService(client: mock);
      svc.addTarget(const MonitorTarget(serverId: 's', baseUrl: 'http://h'));
      expect(svc.targets.length, 1);
      svc.removeTarget('s');
      expect(svc.targets, isEmpty);
    });

    test('pollNow triggers one poll', () async {
      var callCount = 0;
      final mock = MockClient((req) async {
        callCount++;
        return http.Response('[{"id":"1", "title":"T"}]', 200,
            headers: {'content-type': 'application/json'});
      });
      final svc = SessionMonitorService(client: mock);
      final received = <SessionChange>[];
      svc.changes.listen(received.add);

      svc.addTarget(const MonitorTarget(serverId: 'a', baseUrl: 'http://h'));
      await svc.pollNow('a');
      await Future.delayed(Duration.zero);

      expect(callCount, 1);
      expect(received.any((c) => c.kind == SessionChangeKind.sessionStarted), isTrue);
      await svc.stop();
    });
  });

  group('SessionChange', () {
    test('toString is informative', () {
      final c = SessionChange(
        kind: SessionChangeKind.sessionStarted,
        serverId: 'srv-1',
        after: SessionSnapshot(
          id: '1',
          title: 'X',
          state: SessionState.running,
          lastActivity: DateTime.now(),
        ),
      );
      expect(c.toString(), contains('sessionStarted'));
      expect(c.toString(), contains('srv-1'));
    });
  });
}
