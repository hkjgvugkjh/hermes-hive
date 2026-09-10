import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/models/book.dart';
import 'package:hermes_hive/reader/services/library_sandbox.dart';
import 'package:hermes_hive/reader/services/library_service.dart';

/// Records requests and serves canned responses.
class FakeTransport implements FileTransport {
  final Map<String, TransportResponse> responses;
  final List<String> requestedPaths = [];

  FakeTransport(this.responses);

  @override
  Future<TransportResponse> get(String path,
      {Map<String, String>? headers}) async {
    requestedPaths.add(path);
    for (final entry in responses.entries) {
      if (path.contains(entry.key)) return entry.value;
    }
    return TransportResponse(
      statusCode: 404,
      body: Uint8List(0),
    );
  }
}

TransportResponse jsonResponse(Object body) => TransportResponse(
      statusCode: 200,
      body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );

TransportResponse bytesResponse(List<int> bytes, {int status = 200}) =>
    TransportResponse(
      statusCode: status,
      body: Uint8List.fromList(bytes),
    );

/// In-memory stand-in for on-disk storage, so download tests need no platform
/// channels.
class FakeStorage extends BookStorage {
  final Map<String, Uint8List> files = {};
  int saveCount = 0;

  @override
  Future<void> save(Book book, Uint8List bytes) async {
    saveCount++;
    files[book.id] = bytes;
  }

  @override
  Future<Uint8List?> load(Book book) async => files[book.id];

  @override
  Future<void> delete(Book book) async => files.remove(book.id);

  @override
  Future<bool> exists(Book book) async => files.containsKey(book.id);
}

/// Fails every write, to prove a disk error is not masked as a network error.
class FailingStorage extends BookStorage {
  @override
  Future<void> save(Book book, Uint8List bytes) async {
    throw const FileSystemException('disk full');
  }
}

void main() {
  const serverId = 'srv-1';

  Book book(String path, {int size = 1024}) => Book(
        id: '$serverId::library/$path',
        serverId: serverId,
        serverName: 'Test Server',
        relativePath: 'library/$path',
        title: path,
        sizeBytes: size,
      );

  group('LibraryService.listBooks', () {
    test('requests the library directory specifically', () async {
      final transport = FakeTransport({
        'files/list': jsonResponse({'entries': []}),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      await service.listBooks(
        transport: transport,
        serverId: serverId,
        serverName: 'Test Server',
      );

      expect(transport.requestedPaths.single, contains('library'));
      expect(
        Uri.decodeComponent(transport.requestedPaths.single),
        contains('path=library'),
      );
    });

    test('parses entries into books', () async {
      final transport = FakeTransport({
        'files/list': jsonResponse({
          'entries': [
            {'name': 'dune.txt', 'size': 2048, 'is_dir': false},
            {'name': 'notes.md', 'size': 512, 'is_dir': false},
          ],
        }),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      final books = await service.listBooks(
        transport: transport,
        serverId: serverId,
        serverName: 'Test Server',
      );

      expect(books.length, 2);
      expect(books.map((b) => b.title), containsAll(['dune', 'notes']));
      expect(books.first.sizeBytes, 2048);
    });

    test('skips directories', () async {
      final transport = FakeTransport({
        'files/list': jsonResponse({
          'entries': [
            {'name': 'subdir', 'size': 0, 'is_dir': true},
            {'name': 'a.txt', 'size': 10, 'is_dir': false},
          ],
        }),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      final books = await service.listBooks(
        transport: transport,
        serverId: serverId,
        serverName: 'Test Server',
      );

      expect(books.length, 1);
      expect(books.single.title, 'a');
    });

    test('drops entries the sandbox rejects instead of failing', () async {
      final transport = FakeTransport({
        'files/list': jsonResponse({
          'entries': [
            {'name': 'good.txt', 'size': 10},
            {'name': 'evil.apk', 'size': 10},
            {'name': 'leak.sh', 'size': 10},
          ],
        }),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      final books = await service.listBooks(
        transport: transport,
        serverId: serverId,
        serverName: 'Test Server',
      );

      expect(books.length, 1);
      expect(books.single.title, 'good');
    });

    test('drops files over the size cap', () async {
      final transport = FakeTransport({
        'files/list': jsonResponse({
          'entries': [
            {'name': 'small.txt', 'size': 1024},
            {'name': 'huge.txt', 'size': 25 * 1024 * 1024},
          ],
        }),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      final books = await service.listBooks(
        transport: transport,
        serverId: serverId,
        serverName: 'Test Server',
      );

      expect(books.length, 1);
      expect(books.single.title, 'small');
    });

    test('throws on a non-200 listing', () async {
      final transport = FakeTransport({
        'files/list': TransportResponse(
          statusCode: 403,
          body: Uint8List(0),
        ),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      expect(
        () => service.listBooks(
          transport: transport,
          serverId: serverId,
          serverName: 'Test Server',
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('throws on malformed json', () async {
      final transport = FakeTransport({
        'files/list': bytesResponse(utf8.encode('not json at all')),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      expect(
        () => service.listBooks(
          transport: transport,
          serverId: serverId,
          serverName: 'Test Server',
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('sorts results by title', () async {
      final transport = FakeTransport({
        'files/list': jsonResponse({
          'entries': [
            {'name': 'zebra.txt', 'size': 1},
            {'name': 'apple.txt', 'size': 1},
            {'name': 'mango.txt', 'size': 1},
          ],
        }),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      final books = await service.listBooks(
        transport: transport,
        serverId: serverId,
        serverName: 'Test Server',
      );

      expect(books.map((b) => b.title).toList(),
          ['apple', 'mango', 'zebra']);
    });
  });

  group('LibraryService.downloadBook', () {
    test('sends the sandboxed path, not the raw one', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(utf8.encode('hello world')),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      await service.downloadBook(
        transport: transport,
        book: book('novel.txt', size: 11),
      );

      final path = Uri.decodeComponent(transport.requestedPaths.single);
      expect(path, contains('path=library/novel.txt'));
    });

    test('decodes the body into text', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(utf8.encode('第一章 开始')),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      final content = await service.downloadBook(
        transport: transport,
        book: book('cn.txt', size: 20),
      );

      expect(content.text, '第一章 开始');
    });

    test('refuses a traversal path even when handed a Book object', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(utf8.encode('secret')),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      expect(
        () => service.downloadBook(
          transport: transport,
          book: Book(
            id: 'x',
            serverId: serverId,
            serverName: 'Test',
            relativePath: 'library/../../etc/passwd',
            title: 'passwd',
            sizeBytes: 6,
          ),
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
      // And nothing was ever sent.
      expect(transport.requestedPaths, isEmpty);
    });

    test('refuses an oversized declared transfer before requesting', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(utf8.encode('x')),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      expect(
        () => service.downloadBook(
          transport: transport,
          book: book('big.txt', size: 60 * 1024 * 1024),
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
      expect(transport.requestedPaths, isEmpty);
    });

    test('rejects a payload larger than what was declared', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(List.filled(5 * 1024 * 1024, 65)),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      expect(
        () => service.downloadBook(
          transport: transport,
          book: book('liar.txt', size: 1024),
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects an empty payload', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse([]),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      expect(
        () => service.downloadBook(
          transport: transport,
          book: book('empty.txt', size: 0),
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('throws on a failed download', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(utf8.encode('nope'), status: 500),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      expect(
        () => service.downloadBook(
          transport: transport,
          book: book('x.txt', size: 4),
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('persists the payload and reports the saved text', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(utf8.encode('persisted body')),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      final target = book('persist.txt', size: 14);
      final content = await service.downloadBook(
        transport: transport,
        book: target,
      );

      expect(content.text, 'persisted body');
      expect(storage.saveCount, 1);
      expect(storage.files[target.id], isNotNull);

      // readCached returns the same bytes.
      final cached = await service.readCached(target);
      expect(cached?.text, 'persisted body');
    });

    test('deleteCached removes the local copy', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(utf8.encode('x')),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);
      final target = book('gone.txt', size: 1);

      await service.downloadBook(transport: transport, book: target);
      expect(await service.isCached(target), isTrue);

      await service.deleteCached(target);
      expect(await service.isCached(target), isFalse);
      expect(await service.readCached(target), isNull);
    });

    test('a disk failure surfaces as itself, not as a network error', () async {
      final transport = FakeTransport({
        'files/read': bytesResponse(utf8.encode('x')),
      });
      final service = LibraryService(storage: FailingStorage());

      expect(
        () => service.downloadBook(
          transport: transport,
          book: book('disk.txt', size: 1),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('falls back to latin-1 for invalid utf-8 rather than throwing',
        () async {
      final transport = FakeTransport({
        'files/read': bytesResponse([0xFF, 0xFE, 0x41, 0x42]),
      });
      final storage = FakeStorage();
      final service = LibraryService(storage: storage);

      final content = await service.downloadBook(
        transport: transport,
        book: book('gbk.txt', size: 4),
      );

      expect(content.text, isNotEmpty);
    });
  });
}
