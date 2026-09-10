import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/services/library_sandbox.dart';

void main() {
  group('LibrarySandbox.resolve — traversal', () {
    final sandbox = const LibrarySandbox();

    test('accepts a plain filename and roots it under library', () {
      expect(sandbox.resolve('novel.txt'), 'library/novel.txt');
    });

    test('accepts a nested path', () {
      expect(sandbox.resolve('scifi/dune.md'), 'library/scifi/dune.md');
    });

    test('rejects simple parent traversal', () {
      expect(
        () => sandbox.resolve('../secrets.txt'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects traversal buried in the middle', () {
      expect(
        () => sandbox.resolve('books/../../etc/passwd'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects traversal that returns to the root', () {
      expect(
        () => sandbox.resolve('a/../b.txt'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects absolute unix paths', () {
      expect(
        () => sandbox.resolve('/etc/passwd'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects absolute windows paths', () {
      expect(
        () => sandbox.resolve('C:\\Windows\\win.ini'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects UNC-style paths', () {
      expect(
        () => sandbox.resolve(r'\\server\share\file.txt'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects url-encoded traversal', () {
      expect(
        () => sandbox.resolve('..%2Fsecrets.txt'),
        throwsA(isA<LibrarySandboxError>()),
      );
      expect(
        () => sandbox.resolve('%2e%2e/secrets.txt'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects NUL byte injection', () {
      expect(
        () => sandbox.resolve('safe.txt\u0000.jpg'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects backslash separators used to smuggle traversal', () {
      expect(
        () => sandbox.resolve('..\\secrets.txt'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('is idempotent — an already-rooted path is not double-prefixed', () {
      // A Book persisted from a previous session already carries the prefix;
      // re-resolving it must not produce 'library/library/...'.
      expect(sandbox.resolve('library/novel.txt'), 'library/novel.txt');
      expect(sandbox.resolve('library/scifi/dune.md'),
          'library/scifi/dune.md');
      expect(sandbox.resolve('library/library/x.txt'), 'library/x.txt');
    });

    test('rejects a path that is only the library root', () {
      expect(
        () => sandbox.resolve('library'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects empty path', () {
      expect(
        () => sandbox.resolve(''),
        throwsA(isA<LibrarySandboxError>()),
      );
    });
  });

  group('LibrarySandbox.resolve — extension and depth', () {
    final sandbox = const LibrarySandbox();

    test('allows .txt and .md', () {
      expect(sandbox.resolve('a.txt'), 'library/a.txt');
      expect(sandbox.resolve('a.md'), 'library/a.md');
    });

    test('is case-insensitive on extension', () {
      expect(sandbox.resolve('README.MD'), 'library/README.MD');
    });

    test('rejects executable and archive types', () {
      for (final f in const [
        'payload.sh',
        'app.apk',
        'data.db',
        'script.exe',
        'archive.zip',
        'x.pdf',
      ]) {
        expect(
          () => sandbox.resolve(f),
          throwsA(isA<LibrarySandboxError>()),
          reason: '$f should be rejected',
        );
      }
    });

    test('rejects files with no extension', () {
      expect(
        () => sandbox.resolve('passwd'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects dotfiles (no usable stem)', () {
      expect(
        () => sandbox.resolve('.bashrc'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects paths deeper than the depth cap', () {
      expect(
        () => sandbox.resolve('a/b/c/d/e.txt'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });
  });

  group('LibrarySandbox.resolveDir', () {
    final sandbox = const LibrarySandbox();

    test('empty maps to the library root', () {
      expect(sandbox.resolveDir(''), 'library');
      expect(sandbox.resolveDir('.'), 'library');
    });

    test('does not double-prefix an already rooted path', () {
      expect(sandbox.resolveDir('library/scifi'), 'library/scifi');
    });

    test('rejects traversal', () {
      expect(
        () => sandbox.resolveDir('../..'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('rejects excessive depth', () {
      expect(
        () => sandbox.resolveDir('a/b/c/d'),
        throwsA(isA<LibrarySandboxError>()),
      );
    });
  });

  group('LibrarySandbox size guards', () {
    final sandbox = const LibrarySandbox();

    test('accepts sizes under the cap', () {
      expect(sandbox.sizeAllowed(1024), isTrue);
      expect(sandbox.sizeAllowed(19 * 1024 * 1024), isTrue);
    });

    test('rejects zero, negative and oversized', () {
      expect(sandbox.sizeAllowed(0), isFalse);
      expect(sandbox.sizeAllowed(-1), isFalse);
      expect(sandbox.sizeAllowed(21 * 1024 * 1024), isFalse);
    });

    test('checkTransfer rejects oversized transfers', () {
      expect(() => sandbox.checkTransfer(1024), returnsNormally);
      expect(
        () => sandbox.checkTransfer(60 * 1024 * 1024),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('validateContent rejects empty and oversized payloads', () {
      expect(
        () => sandbox.validateContent(Uint8List(0), declaredSize: 0),
        throwsA(isA<LibrarySandboxError>()),
      );
      expect(
        () => sandbox.validateContent(
          Uint8List(21 * 1024 * 1024),
          declaredSize: 21 * 1024 * 1024,
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
    });

    test('validateContent rejects a lying content-length', () {
      // Declared small, actually huge — classic decompression-bomb tell.
      expect(
        () => sandbox.validateContent(
          Uint8List(5 * 1024 * 1024),
          declaredSize: 1024,
        ),
        throwsA(isA<LibrarySandboxError>()),
      );
    });
  });

  group('LibrarySandbox.localFileName', () {
    final sandbox = const LibrarySandbox();

    test('flattens separators so nested paths cannot escape', () {
      final name = sandbox.localFileName('srv1', 'library/a/b.txt');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('\\')));
    });

    test('is stable for the same input', () {
      final a = sandbox.localFileName('s1', 'library/x.txt');
      final b = sandbox.localFileName('s1', 'library/x.txt');
      expect(a, b);
    });

    test('differs per server so two servers cannot collide', () {
      final a = sandbox.localFileName('s1', 'library/x.txt');
      final b = sandbox.localFileName('s2', 'library/x.txt');
      expect(a, isNot(b));
    });
  });
}
