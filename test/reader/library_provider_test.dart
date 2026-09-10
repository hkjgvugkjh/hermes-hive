import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/models/book.dart';
import 'package:hermes_hive/reader/models/reader_config.dart';
import 'package:hermes_hive/reader/providers/library_provider.dart';
import 'package:hermes_hive/reader/services/library_sandbox.dart';
import 'package:hermes_hive/reader/services/library_service.dart';

class FakeStorage extends BookStorage {
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

class FakeTransport implements FileTransport {
  FakeTransport({this.entries = const [], this.fileBytes, this.fail = false});

  final List<Map<String, dynamic>> entries;
  final List<int>? fileBytes;
  final bool fail;

  @override
  Future<TransportResponse> get(String path,
      {Map<String, String>? headers}) async {
    if (fail) {
      return TransportResponse(statusCode: 500, body: Uint8List(0));
    }
    if (path.contains('files/list')) {
      return TransportResponse(
        statusCode: 200,
        body: Uint8List.fromList(
            utf8.encode(jsonEncode({'entries': entries}))),
      );
    }
    return TransportResponse(
      statusCode: 200,
      body: Uint8List.fromList(fileBytes ?? utf8.encode('body text')),
    );
  }
}

Book book(String name, {int size = 10}) => Book(
      // Mirrors LibraryService.listBooks: id embeds the sandboxed relative
      // path, so a Book built here matches one produced from a real listing.
      id: 'srv::library/$name',
      serverId: 'srv',
      serverName: 'Server',
      relativePath: 'library/$name',
      title: name,
      sizeBytes: size,
    );

void main() {
  group('LibraryProvider', () {
    test('refresh populates the shelf', () async {
      final provider = LibraryProvider(LibraryService(storage: FakeStorage()));
      final transport = FakeTransport(entries: [
        {'name': 'a.txt', 'size': 10},
        {'name': 'b.txt', 'size': 20},
      ]);

      await provider.refresh(
        transport: transport,
        serverId: 'srv',
        serverName: 'Server',
      );

      expect(provider.books.length, 2);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
      expect(provider.activeServerId, 'srv');
    });

    test('refresh records which books are already on the device', () async {
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);
      final provider = LibraryProvider(service);

      final target = book('cached.txt');
      await service.downloadBook(
        transport: FakeTransport(fileBytes: utf8.encode('x')),
        book: target,
      );

      final transport = FakeTransport(entries: [
        {'name': 'cached.txt', 'size': 1},
        {'name': 'new.txt', 'size': 1},
      ]);
      await provider.refresh(
          transport: transport, serverId: 'srv', serverName: 'Server');

      final cachedBook = provider.books.firstWhere((b) => b.title == 'cached');
      expect(provider.isCached(cachedBook), isTrue);
      expect(
        provider.isCached(provider.books.firstWhere((b) => b.title == 'new')),
        isFalse,
      );
    });

    test('refresh surfaces a sandbox-friendly error', () async {
      final provider = LibraryProvider(LibraryService(storage: FakeStorage()));
      final transport = FakeTransport(fail: true);

      await provider.refresh(
          transport: transport, serverId: 'srv', serverName: 'Server');

      expect(provider.error, isNotNull);
      expect(provider.books, isEmpty);
      expect(provider.loading, isFalse);
    });

    test('download stores content and marks the book cached', () async {
      final provider = LibraryProvider(LibraryService(storage: FakeStorage()));
      final target = book('dl.txt');

      final content = await provider.download(
        transport: FakeTransport(fileBytes: utf8.encode('downloaded')),
        book: target,
      );

      expect(content?.text, 'downloaded');
      expect(provider.isCached(target), isTrue);
      expect(provider.progressFor(target.id), 1.0);
      expect(provider.error, isNull);
    });

    test('download failure clears progress and sets an error', () async {
      final provider = LibraryProvider(LibraryService(storage: FakeStorage()));
      final target = book('bad.txt');

      final content = await provider.download(
        transport: FakeTransport(fail: true),
        book: target,
      );

      expect(content, isNull);
      expect(provider.error, isNotNull);
      expect(provider.progressFor(target.id), 0.0);
      expect(provider.isCached(target), isFalse);
    });

    test('open uses the local copy without hitting the network', () async {
      final transport = FakeTransport(fail: true); // any request would fail
      final provider = LibraryProvider(LibraryService(storage: FakeStorage()));
      final target = book('local.txt');

      await provider.download(
        transport: FakeTransport(fileBytes: utf8.encode('saved')),
        book: target,
      );

      final content = await provider.open(
        transport: transport,
        book: target,
      );

      expect(content?.text, 'saved');
    });

    test('open downloads when no local copy exists', () async {
      final provider = LibraryProvider(LibraryService(storage: FakeStorage()));
      final target = book('fresh.txt');

      final content = await provider.open(
        transport: FakeTransport(fileBytes: utf8.encode('fetched')),
        book: target,
      );

      expect(content?.text, 'fetched');
    });

    test('remove deletes the local copy', () async {
      final provider = LibraryProvider(LibraryService(storage: FakeStorage()));
      final target = book('gone.txt');

      await provider.download(
        transport: FakeTransport(fileBytes: utf8.encode('x')),
        book: target,
      );
      expect(provider.isCached(target), isTrue);

      await provider.remove(target);
      expect(provider.isCached(target), isFalse);
    });
  });

  group('ReaderProvider', () {
    ReaderProvider build({int charsPerPage = 10}) => ReaderProvider(
          config: ReaderConfig(charsPerPage: charsPerPage),
        );

    test('starts empty', () {
      final provider = build();
      expect(provider.hasBook, isFalse);
      expect(provider.pageCount, 0);
      expect(provider.progress, 0.0);
    });

    test('openBook paginates the text', () {
      final provider = build(charsPerPage: 10);
      final target = book('t.txt');

      provider.openBook(
          target, BookContent(bookId: target.id, text: 'x' * 35));

      expect(provider.hasBook, isTrue);
      expect(provider.pageCount, 4);
      expect(provider.pageIndex, 0);
      expect(provider.currentPage?.content.length, 10);
    });

    test('nextPage and previousPage walk the pages', () {
      final provider = build(charsPerPage: 10);
      final target = book('t.txt');
      provider.openBook(target, BookContent(bookId: target.id, text: 'x' * 30));

      expect(provider.atStart, isTrue);
      expect(provider.nextPage(), isTrue);
      expect(provider.pageIndex, 1);
      expect(provider.previousPage(), isTrue);
      expect(provider.pageIndex, 0);
      // Cannot go before the first page.
      expect(provider.previousPage(), isFalse);
    });

    test('atEnd stops advancing', () {
      final provider = build(charsPerPage: 10);
      final target = book('t.txt');
      provider.openBook(target, BookContent(bookId: target.id, text: 'x' * 20));

      expect(provider.nextPage(), isTrue);
      expect(provider.atEnd, isTrue);
      expect(provider.nextPage(), isFalse);
      expect(provider.pageIndex, 1);
    });

    test('progress runs 0 to 1 across the book', () {
      final provider = build(charsPerPage: 10);
      final target = book('t.txt');
      provider.openBook(target, BookContent(bookId: target.id, text: 'x' * 30));

      expect(provider.progress, 0.0);
      provider.nextPage();
      expect(provider.progress, closeTo(0.5, 0.001));
      provider.nextPage();
      expect(provider.progress, 1.0);
    });

    test('goToPage clamps out-of-range values', () {
      final provider = build(charsPerPage: 10);
      final target = book('t.txt');
      provider.openBook(target, BookContent(bookId: target.id, text: 'x' * 30));

      provider.goToPage(99);
      expect(provider.pageIndex, 2);
      provider.goToPage(-5);
      expect(provider.pageIndex, 0);
    });

    test('changing charsPerPage re-paginates but keeps a valid position', () {
      final provider = build(charsPerPage: 10);
      final target = book('t.txt');
      provider.openBook(target, BookContent(bookId: target.id, text: 'x' * 100));
      provider.goToPage(9);
      expect(provider.pageCount, 10);

      provider.updateConfig(const ReaderConfig(charsPerPage: 50));

      expect(provider.pageCount, 2);
      // Old index 9 is out of range for the new layout; it must be clamped,
      // not read out of bounds.
      expect(provider.pageIndex, 1);
      expect(provider.currentPage, isNotNull);
    });

    test('an unrelated config change does not reset pagination', () {
      final provider = build(charsPerPage: 10);
      final target = book('t.txt');
      provider.openBook(target, BookContent(bookId: target.id, text: 'x' * 30));
      provider.goToPage(1);

      provider.updateConfig(const ReaderConfig(
        charsPerPage: 10,
        fontScale: 1.5, // unrelated
      ));

      expect(provider.pageIndex, 1);
      expect(provider.pageCount, 3);
    });

    test('close clears the book', () {
      final provider = build(charsPerPage: 10);
      final target = book('t.txt');
      provider.openBook(target, BookContent(bookId: target.id, text: 'x' * 20));

      provider.close();

      expect(provider.hasBook, isFalse);
      expect(provider.book, isNull);
      expect(provider.pageCount, 0);
    });
  });
}
