import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/models/reader_config.dart';
import 'package:hermes_hive/reader/services/tts_service.dart';

/// Scriptable stand-in for a speech engine.
class FakeSource implements SpeechSource {
  FakeSource({
    required this.engine,
    this.available = true,
    this.failSpeak = false,
  });

  @override
  final SpeechEngine engine;

  bool available;
  bool failSpeak;

  final spoken = <String>[];
  int stopCalls = 0;
  int disposeCalls = 0;
  final rates = <double>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> speak(String text) async {
    if (failSpeak) throw Exception('engine failure');
    spoken.add(text);
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> setRate(double rate) async => rates.add(rate);

  @override
  Future<void> dispose() async => disposeCalls++;
}

void main() {
  late FakeSource server;
  late FakeSource local;

  TtsService build({Future<bool> Function()? connectivity}) => TtsService(
        serverSource: server,
        localSource: local,
        connectivityCheck: connectivity,
      );

  setUp(() {
    server = FakeSource(engine: SpeechEngine.server);
    local = FakeSource(engine: SpeechEngine.local);
  });

  group('TtsService mode selection', () {
    test('auto uses the server when it is healthy', () async {
      final svc = build();
      await svc.setMode(TtsMode.auto);

      final result = await svc.speak('hello');

      expect(result.engine, SpeechEngine.server);
      expect(result.fellBack, isFalse);
      expect(server.spoken, ['hello']);
      expect(local.spoken, isEmpty);
    });

    test('server mode never silently substitutes the local voice', () async {
      server.failSpeak = true;
      final svc = build();
      await svc.setMode(TtsMode.server);

      // Strict mode must surface the failure, not degrade.
      expect(() => svc.speak('hello'), throwsA(isA<Exception>()));
      expect(local.spoken, isEmpty,
          reason: 'local engine must not be used in server-only mode');
    });

    test('local mode never touches the network engine', () async {
      final svc = build();
      await svc.setMode(TtsMode.local);

      final result = await svc.speak('hi');

      expect(result.engine, SpeechEngine.local);
      expect(local.spoken, ['hi']);
      expect(server.spoken, isEmpty);
      expect(server.isAvailable, isNotNull);
    });
  });

  group('TtsService automatic fallback', () {
    test('falls back to local when the server engine fails', () async {
      server.failSpeak = true;
      final svc = build();
      await svc.setMode(TtsMode.auto);

      final result = await svc.speak('hello');

      expect(result.engine, SpeechEngine.local);
      expect(result.fellBack, isTrue);
      expect(result.fallbackReason, contains('server TTS failed'));
      expect(local.spoken, ['hello']);
      expect(svc.lastFallbackReason, isNotNull);
    });

    test('skips the server entirely when offline', () async {
      final svc = build(connectivity: () async => false);
      await svc.setMode(TtsMode.auto);

      final result = await svc.speak('hello');

      expect(result.engine, SpeechEngine.local);
      expect(result.fallbackReason, 'offline');
      // The whole point: no slow network timeout before the fallback.
      expect(server.spoken, isEmpty);
    });

    test('falls back when the server reports itself unavailable', () async {
      server.available = false;
      final svc = build();
      await svc.setMode(TtsMode.auto);

      final result = await svc.speak('hello');

      expect(result.engine, SpeechEngine.local);
      expect(result.fallbackReason, contains('not configured'));
      expect(server.spoken, isEmpty);
    });

    test('throws when every engine fails', () async {
      server.failSpeak = true;
      local.failSpeak = true;
      final svc = build();
      await svc.setMode(TtsMode.auto);

      expect(() => svc.speak('hello'), throwsA(isA<Exception>()));
    });

    test('clears the stale fallback reason after a server success', () async {
      server.failSpeak = true;
      final svc = build();
      await svc.setMode(TtsMode.auto);
      await svc.speak('first');
      expect(svc.lastFallbackReason, isNotNull);

      server.failSpeak = false;
      final result = await svc.speak('second');

      expect(result.fellBack, isFalse);
      expect(svc.lastFallbackReason, isNull);
    });
  });

  group('TtsService state and rate', () {
    test('emits speaking then stays speaking after a successful start',
        () async {
      final svc = build();
      await svc.setMode(TtsMode.local);

      final seen = <TtsState>[];
      final sub = svc.stateStream.listen(seen.add);

      await svc.speak('hello');
      await Future<void>.delayed(Duration.zero);

      expect(seen, contains(TtsState.speaking));
      expect(svc.state, TtsState.speaking);
      await sub.cancel();
    });

    test('emits error when all engines fail', () async {
      server.failSpeak = true;
      local.failSpeak = true;
      final svc = build();
      await svc.setMode(TtsMode.auto);

      final seen = <TtsState>[];
      final sub = svc.stateStream.listen(seen.add);

      await expectLater(() => svc.speak('x'), throwsA(isA<Exception>()));
      await Future<void>.delayed(Duration.zero);

      expect(seen, contains(TtsState.error));
      await sub.cancel();
    });

    test('returns to idle after stop', () async {
      final svc = build();
      await svc.setMode(TtsMode.local);
      await svc.speak('hello');

      await svc.stop();

      expect(svc.state, TtsState.idle);
      expect(local.stopCalls, 1);
      expect(server.stopCalls, 1);
    });

    test('empty text is a no-op that does not engage any engine', () async {
      final svc = build();
      await svc.setMode(TtsMode.auto);

      await svc.speak('   ');

      expect(server.spoken, isEmpty);
      expect(local.spoken, isEmpty);
    });

    test('rate is clamped and pushed to both engines', () async {
      final svc = build();
      await svc.setRate(1.5);
      expect(svc.rate, 1.0);

      await svc.setRate(-2);
      expect(svc.rate, 0.0);

      expect(server.rates.last, 0.0);
      expect(local.rates.last, 0.0);
    });

    test('dispose tears down both engines', () async {
      final svc = build();
      await svc.dispose();

      expect(server.disposeCalls, 1);
      expect(local.disposeCalls, 1);
    });
  });
}
