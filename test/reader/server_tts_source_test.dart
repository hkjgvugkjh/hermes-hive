import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/services/server_tts_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakePlayer implements AudioPlayerPort {
  Uint8List? lastBytes;
  int playCount = 0;
  int stopCount = 0;

  @override
  Future<void> playBytes(Uint8List bytes, {String? contentType}) async {
    lastBytes = bytes;
    playCount++;
  }

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> dispose() async {}
}

void main() {
  group('ServerTtsSource', () {
    test('probe returns true when providers exist', () async {
      final mock = MockClient((req) async {
        return http.Response(jsonEncode([
          {'id': 'openai', 'name': 'OpenAI TTS'}
        ]), 200);
      });
      final ok = await ServerTtsSource.probe('http://h', null, client: mock);
      expect(ok, isTrue);
    });

    test('probe returns false on network error', () async {
      final ok = await ServerTtsSource.probe('http://unreachable', null);
      expect(ok, isFalse);
    });

    test('engine property is SpeechEngine.server', () {
      final src = ServerTtsSource(baseUrl: 'http://h', player: _FakePlayer());
      expect(src.engine.name, 'server');
    });

    test('isAvailable defaults to true', () async {
      final src = ServerTtsSource(baseUrl: 'http://h', player: _FakePlayer());
      expect(await src.isAvailable(), isTrue);
    });

    test('speak sends JSON request and plays bytes', () async {
      final fakePlayer = _FakePlayer();
      final mock = MockClient((req) async {
        expect(req.url.path, '/api/hermes/tts/synthesize');
        final body = jsonDecode(req.body);
        expect(body['text'], 'hello');
        return http.Response.bytes([1, 2, 3], 200,
            headers: {'content-type': 'audio/mpeg'});
      });

      final src = ServerTtsSource(
        baseUrl: 'http://h',
        authToken: 'tok',
        client: mock,
        player: fakePlayer,
      );

      await src.speak('hello');

      expect(fakePlayer.playCount, 1);
      expect(fakePlayer.lastBytes, isNotNull);
    });

    test('speak wraps PCM with WAV header when content-type is audio/x-pcm', () async {
      final fakePlayer = _FakePlayer();
      final mock = MockClient((req) async {
        return http.Response.bytes([0, 1, 2, 3], 200,
            headers: {'content-type': 'audio/x-pcm'});
      });

      final src = ServerTtsSource(
        baseUrl: 'http://h',
        client: mock,
        player: fakePlayer,
      );

      await src.speak('test');

      expect(fakePlayer.playCount, 1);
      expect(fakePlayer.lastBytes!.sublist(0, 4), [0x52, 0x49, 0x46, 0x46]); // 'RIFF'
    });

    test('speak throws on 401', () async {
      final mock = MockClient((req) async => http.Response('{}', 401));
      final src = ServerTtsSource(baseUrl: 'http://h', client: mock, player: _FakePlayer());
      Object? caught;
      try {
        await src.speak('x');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<Exception>());
      expect(caught.toString(), contains('authorization'));
    });

    test('speak throws on 500', () async {
      final mock = MockClient((req) async => http.Response('{}', 500));
      final src = ServerTtsSource(baseUrl: 'http://h', client: mock, player: _FakePlayer());
      Object? caught;
      try {
        await src.speak('x');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<Exception>());
      expect(caught.toString(), contains('500'));
    });

    test('stop delegates to player', () async {
      final fakePlayer = _FakePlayer();
      final src = ServerTtsSource(baseUrl: 'http://h', player: fakePlayer);
      await src.stop();
      expect(fakePlayer.stopCount, 1);
    });

    test('dispose delegates to player', () async {
      final fakePlayer = _FakePlayer();
      final src = ServerTtsSource(baseUrl: 'http://h', player: fakePlayer);
      await src.dispose();
      // _FakePlayer.dispose is a no-op, but no exception means success.
    });
  });
}
