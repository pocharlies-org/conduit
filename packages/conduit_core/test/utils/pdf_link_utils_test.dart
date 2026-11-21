import 'package:checks/checks.dart';
import 'package:conduit_core/utils/pdf_link_utils.dart';
import 'package:test/test.dart';

void main() {
  group('isPdfLink', () {
    test('accepts PDF paths with query strings, fragments and escapes', () {
      check(isPdfLink('https://example.com/reports/q1.pdf?token=abc')).isTrue();
      check(isPdfLink('https://example.com/reports/q1.PDF#page=2')).isTrue();
      check(isPdfLink('/api/v1/files/1/Quarterly%20Report.pdf')).isTrue();
    });

    test('rejects non-PDF paths and query-only PDF names', () {
      check(isPdfLink('https://example.com/report.html')).isFalse();
      check(isPdfLink('https://example.com/download?file=q1.pdf')).isFalse();
      check(isPdfLink('   ')).isFalse();
    });
  });

  test('page geometry falls back to A4 for pages without a size', () {
    check(pdfHeightForWidth(pageWidth: 612, pageHeight: 792, width: 306))
        .equals(396);
    check(pdfHeightForWidth(pageWidth: 0, pageHeight: 792, width: 100))
        .isCloseTo(141.4, 0.001);
    check(pdfPageAspect(width: 0, height: 0)).equals(0.707);
    check(pdfPageAspect(width: 300, height: 600)).equals(0.5);
  });

  group('PdfPageImageCache', () {
    late List<String> evicted;
    late PdfPageImageCache<String> cache;

    setUp(() {
      evicted = <String>[];
      cache = PdfPageImageCache<String>(
        maxBytes: 30,
        sizeOf: (image) => 10,
        onEvict: evicted.add,
      );
    });

    test('evicts the least recently shown pages over budget', () {
      cache
        ..put(0, 'p0')
        ..put(1, 'p1')
        ..put(2, 'p2')
        ..touch(0)
        ..put(3, 'p3');

      check(evicted).deepEquals(['p1']);
      check(cache.pages.toList()).deepEquals([2, 0, 3]);
      check(cache.heldBytes).equals(30);
    });

    test('never evicts the page it just stored', () {
      final big = PdfPageImageCache<String>(
        maxBytes: 5,
        sizeOf: (image) => 10,
        onEvict: evicted.add,
      )..put(0, 'p0');

      check(big.peek(0)).equals('p0');
      big.put(1, 'p1');
      check(evicted).deepEquals(['p0']);
      check(big.pages.toList()).deepEquals([1]);
    });

    test('pages the viewer keeps are passed over for eviction', () {
      cache
        ..put(0, 'p0')
        ..put(1, 'p1')
        ..put(2, 'p2')
        ..put(3, 'p3', keep: (page) => page == 0 || page == 1);

      check(evicted).deepEquals(['p2']);
      check(cache.pages.toList()).deepEquals([0, 1, 3]);

      // Only kept pages left to evict: the cache runs over budget.
      cache.put(4, 'p4', keep: (page) => page != 4);
      check(evicted).deepEquals(['p2']);
      check(cache.heldBytes).equals(40);
    });

    test('replacing a page evicts the old image; clear evicts all', () {
      cache
        ..put(0, 'old')
        ..put(0, 'new');
      check(evicted).deepEquals(['old']);
      check(cache.heldBytes).equals(10);

      cache.clear();
      check(evicted).deepEquals(['old', 'new']);
      check(cache.length).equals(0);
      check(cache.heldBytes).equals(0);
    });
  });
}
