import 'dart:convert';
import 'dart:typed_data';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/models/book.dart';
import 'package:hermes_hive/reader/providers/library_provider.dart';
import 'package:hermes_hive/reader/screens/book_reader_screen.dart';
import 'package:hermes_hive/reader/screens/reader_home_screen.dart';
import 'package:hermes_hive/reader/services/library_service.dart';
import 'package:hermes_hive/reader/services/tts_service.dart';
import 'fake_tts.dart';
import 'package:hermes_hive/reader/models/reader_config.dart';
import 'package:provider/provider.dart';

/// In-memory book storage for widget tests.
class InMemoryStorage extends BookStorage {
  final Map<String, Uint8List> files = {};

  @override
  Future<void> save(Book book, Uint8List bytes) async => files[book.id] = bytes;

  @override
  Future<Uint8List?> load(Book book) async => files[book.id];

  @override
  Future<void> delete(Book book) async => files.remove(book.id);

  @override
  Future<bool> exists(Book book) async => files.containsKey(book.id);
}

class StubTransport implements FileTransport {
  StubTransport({this.entries = const [], this.bytes});

  final List<Map<String, dynamic>> entries;
  final List<int>? bytes;

  @override
  Future<TransportResponse> get(String path,
      {Map<String, String>? headers}) async {
    if (path.contains('files/list')) {
      return TransportResponse(
        statusCode: 200,
        body: Uint8List.fromList(
            utf8.encode(jsonEncode({'entries': entries}))),
      );
    }
    return TransportResponse(
      statusCode: 200,
      body: Uint8List.fromList(bytes ?? utf8.encode('page text')),
    );
  }
}

void main() {
  Book book(String name, {int size = 10}) => Book(
        id: 'srv::library/$name',
        serverId: 'srv',
        serverName: 'Server',
        relativePath: 'library/$name',
        title: name,
        sizeBytes: size,
      );

  Widget buildShelf(FileTransport transport) {
    return MultiProvider(
      providers: [
        // In-memory storage: the real one calls path_provider, which needs
        // platform channels that do not exist in a widget test.
        Provider<LibraryService>(
            create: (_) => LibraryService(storage: InMemoryStorage())),
        ChangeNotifierProxyProvider<LibraryService, LibraryProvider>(
          create: (c) => LibraryProvider(c.read<LibraryService>()),
          update: (_, s, p) => p ?? LibraryProvider(s),
        ),
        ChangeNotifierProvider(create: (_) => ReaderProvider()),
        Provider<TtsService>(
          create: (_) => TtsService(
            serverSource: FakeTtsSource(
              engine: SpeechEngine.server,
              available: false,
            ),
            localSource: FakeTtsSource(engine: SpeechEngine.local),
          ),
        ),
      ],
      child: MaterialApp(
        home: ReaderHomeScreen(
          serverId: 'srv',
          serverName: 'Server',
          transport: transport,
        ),
      ),
    );
  }

  testWidgets('shelf lists books from the server', (tester) async {
    await tester.pumpWidget(buildShelf(StubTransport(entries: [
      {'name': 'alpha.txt', 'size': 100},
      {'name': 'beta.md', 'size': 200},
    ])));
    await tester.pumpAndSettle();

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
  });

  testWidgets('shelf shows an empty state when there are no books',
      (tester) async {
    await tester.pumpWidget(buildShelf(StubTransport()));
    await tester.pumpAndSettle();

    expect(find.text('书架上还没有书'), findsOneWidget);
  });

  testWidgets('tapping a book opens the reader and shows the first page',
      (tester) async {
    await tester.pumpWidget(buildShelf(
      StubTransport(
        entries: [
          {'name': 'novel.txt', 'size': 40},
        ],
        bytes: utf8.encode('第一章 开始。这是正文。'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('novel'));
    await tester.pumpAndSettle();

    // We are now on the reader page.
    expect(find.byType(BookReaderScreen), findsOneWidget);
    expect(find.text('第一章 开始。这是正文。'), findsOneWidget);
  });

  testWidgets('reader advances pages and shows progress', (tester) async {
    final provider = ReaderProvider(
      config: const ReaderConfig(charsPerPage: 10),
    );
    final target = book('t.txt');
    provider.openBook(
        target, BookContent(bookId: target.id, text: 'a' * 10 + 'b' * 10 + 'c' * 10));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ReaderProvider>.value(value: provider),
        Provider<TtsService>(
          create: (_) => TtsService(
            serverSource: FakeTtsSource(
              engine: SpeechEngine.server,
              available: false,
            ),
            localSource: FakeTtsSource(engine: SpeechEngine.local),
          ),
        ),
      ],
      child: const MaterialApp(home: BookReaderScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('a' * 10), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('b' * 10), findsOneWidget);
  });

  testWidgets('reader narration falls back to the local engine and notices',
      (tester) async {
    final provider = ReaderProvider(
      config: const ReaderConfig(charsPerPage: 100),
    );
    final target = book('t.txt');
    provider.openBook(target, BookContent(bookId: target.id, text: 'hello world'));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ReaderProvider>.value(value: provider),
        Provider<TtsService>(
          create: (_) => TtsService(
            serverSource: FakeTtsSource(
              engine: SpeechEngine.server,
              available: false,
            ),
            localSource: FakeTtsSource(engine: SpeechEngine.local),
          ),
        ),
      ],
      child: const MaterialApp(home: BookReaderScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.record_voice_over));
    await tester.pumpAndSettle();

    // The fallback banner must appear — silently changing the voice would
    // leave the user wondering why it sounds different.
    expect(find.textContaining('已降级为本机语音'), findsOneWidget);
  });
}
