import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/services/tts_service.dart';

/// Test-only speech source: records calls instead of touching a real engine.
///
/// Exists because both real sources reach into platform channels
/// (flutter_tts) or the network, neither of which works in a widget test.
class FakeTtsSource implements SpeechSource {
  FakeTtsSource({
    required this.engine,
    this.available = true,
    this.fails = false,
  });

  @override
  final SpeechEngine engine;

  bool available;
  bool fails;

  final spoken = <String>[];
  int stops = 0;
  int disposes = 0;
  final rates = <double>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> speak(String text) async {
    if (fails) throw Exception('engine failure');
    spoken.add(text);
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> setRate(double rate) async => rates.add(rate);

  @override
  Future<void> dispose() async => disposes++;
}
