import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/reader/services/paginator_service.dart';

void main() {
  final paginator = PaginatorService();

  group('PaginatorService.paginate', () {
    test('returns no pages for empty text', () {
      expect(paginator.paginate(''), isEmpty);
    });

    test('puts short text on a single page', () {
      final pages = paginator.paginate('Hello world.');
      expect(pages.length, 1);
      expect(pages.single.content, 'Hello world.');
      expect(pages.single.index, 0);
      expect(pages.single.startOffset, 0);
    });

    test('splits long text into multiple pages', () {
      final text = List.generate(50, (i) => 'Paragraph $i.\n\n').join();
      final pages = paginator.paginate(text, charsPerPage: 200);
      expect(pages.length, greaterThan(1));
    });

    test('every page respects a soft cap (except one long paragraph)', () {
      final text = List.generate(100, (i) => 'Para $i ${'x' * 30}\n\n').join();
      final pages = paginator.paginate(text, charsPerPage: 200);
      for (final page in pages) {
        expect(
          page.content.length,
          lessThanOrEqualTo(200 + 60),
          reason: 'page ${page.index} is ${page.content.length} chars',
        );
      }
    });

    test('page indices are sequential', () {
      final text = List.generate(40, (i) => 'P$i ${'y' * 40}\n\n').join();
      final pages = paginator.paginate(text, charsPerPage: 150);
      for (var i = 0; i < pages.length; i++) {
        expect(pages[i].index, i);
      }
    });

    test('never splits inside a paragraph when it fits', () {
      final para = 'AAA ${'a' * 50}\n\nBBB ${'b' * 50}\n\n';
      final pages = paginator.paginate(para, charsPerPage: 60);
      // Each page should end at a paragraph boundary.
      for (final page in pages) {
        expect(page.content.trimRight().endsWith('b') ||
            page.content.trimRight().endsWith('a'), isTrue);
      }
    });

    test('hard-splits a single over-long paragraph', () {
      final long = 'z' * 1000;
      final pages = paginator.paginate(long, charsPerPage: 100);
      expect(pages.length, greaterThan(5));
      for (final page in pages) {
        expect(page.content.length, lessThanOrEqualTo(160),
            reason: 'page ${page.index} len ${page.content.length}');
      }
    });

    test('splits on CJK sentence terminators', () {
      final text = List.generate(30, (i) => '第${i}句话。').join();
      final pages = paginator.paginate(text, charsPerPage: 50);
      expect(pages.length, greaterThan(3));
      // Each page should end with a full stop, not mid-sentence.
      for (final page in pages) {
        if (page.content.length > 20) {
          expect(page.content.trimRight().endsWith('。'), isTrue,
              reason: 'page ${page.index} ended mid-sentence: '
                  '${page.content.substring(page.content.length - 8)}');
        }
      }
    });

    test('reassembling pages reproduces the original text', () {
      final original =
          List.generate(30, (i) => 'Line $i ${'q' * 20}\n\n').join();
      final pages = paginator.paginate(original, charsPerPage: 120);
      final joined = pages.map((p) => p.content).join();
      expect(joined, original);
    });

    test('startOffsets increase monotonically', () {
      final text = List.generate(40, (i) => 'P$i ${'w' * 30}\n\n').join();
      final pages = paginator.paginate(text, charsPerPage: 150);
      for (var i = 1; i < pages.length; i++) {
        expect(pages[i].startOffset, greaterThan(pages[i - 1].startOffset));
      }
    });
  });

  group('PaginatorService.progressFor', () {
    test('is 0 for an empty book', () {
      expect(paginator.progressFor(0, 0), 0.0);
    });

    test('is 1 for a single page', () {
      expect(paginator.progressFor(0, 1), 1.0);
    });

    test('spans 0 to 1 across pages', () {
      expect(paginator.progressFor(0, 4), 0.0);
      expect(paginator.progressFor(3, 4), 1.0);
      expect(paginator.progressFor(1, 3), closeTo(0.5, 0.001));
    });

    test('clamps out-of-range indices', () {
      expect(paginator.progressFor(-5, 4), 0.0);
      expect(paginator.progressFor(99, 4), 1.0);
    });
  });

  group('PaginatorService.toSpeechText', () {
    test('strips markdown headings', () {
      expect(paginator.toSpeechText('## Chapter One'), 'Chapter One');
    });

    test('strips bold and italic markers', () {
      expect(paginator.toSpeechText('**bold** and *italic*'),
          'bold and italic');
    });

    test('strips link syntax but keeps the label', () {
      expect(paginator.toSpeechText('see [docs](http://x) now'),
          'see docs now');
    });

    test('strips images entirely and collapses the leftover space', () {
      expect(paginator.toSpeechText('a ![img](x.png) b'), 'a b');
    });

    test('strips inline code backticks', () {
      expect(paginator.toSpeechText('run `ls -la` here'), 'run ls -la here');
    });

    test('strips list bullets', () {
      expect(paginator.toSpeechText('- one\n- two'), 'one\ntwo');
    });

    test('strips blockquote markers', () {
      expect(paginator.toSpeechText('> quoted text'), 'quoted text');
    });

    test('collapses excess whitespace', () {
      expect(paginator.toSpeechText('a    b\n\n\n\nc'), 'a b\n\nc');
    });

    test('leaves plain prose untouched', () {
      const prose = '这是一段普通的中文文本，没有标记。';
      expect(paginator.toSpeechText(prose), prose);
    });
  });
}
