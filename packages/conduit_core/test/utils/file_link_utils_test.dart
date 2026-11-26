import 'package:checks/checks.dart';
import 'package:conduit_core/utils/file_link_utils.dart';
import 'package:test/test.dart';

void main() {
  group('isFileLink', () {
    test('accepts the office and photo extensions the app previews', () {
      for (final href in [
        'https://ofimatica.test/files/2026-11/presupuesto_149f.xlsx',
        '/api/v1/files/7/Deck%20Q1.pptx',
        'https://x.test/a.XLSX?token=abc',
        'https://x.test/foto.jpeg#meta',
      ]) {
        check(isFileLink(href)).isTrue();
      }
    });

    test('rejects PDFs, pages and links whose name sits in the query', () {
      check(isFileLink('https://x.test/a.pdf')).isFalse();
      check(isFileLink('https://x.test/report.html')).isFalse();
      check(isFileLink('https://x.test/download?file=a.xlsx')).isFalse();
      check(isFileLink('')).isFalse();
    });
  });

  group('fileLinkTitle', () {
    test('prefers the label without its file emoji', () {
      check(
        fileLinkTitle(
          rawLabel: '\u{1F4C4} Q1 report',
          url: 'https://x.test/a.pdf',
          fallback: 'PDF',
        ),
      ).equals('Q1 report');
      check(
        fileLinkTitle(
          rawLabel: '\u{1F4CA} Presupuesto',
          url: 'https://x.test/a.xlsx',
          fallback: 'Archivo',
        ),
      ).equals('Presupuesto');
    });

    test('falls back to the decoded file name, then the fallback', () {
      check(
        fileLinkTitle(
          rawLabel: 'https://x.test/dir/My%20File.pdf',
          url: 'https://x.test/dir/My%20File.pdf',
          fallback: 'PDF',
        ),
      ).equals('My File.pdf');
      check(fileLinkTitle(rawLabel: null, url: '', fallback: 'PDF')).equals(
        'PDF',
      );
    });
  });

  test('share file names are safe and keep the extension they carry', () {
    check(
      fileShareFileName('Q1: report/final', fallbackExtension: '.pdf'),
    ).equals('Q1 report final.pdf');
    check(fileShareFileName('notes.PDF', fallbackExtension: '.pdf')).equals(
      'notes.PDF',
    );
    check(fileShareFileName('***', fallbackExtension: '.pdf')).equals(
      'document.pdf',
    );
    check(
      fileShareFileName('Presupuesto', fallbackExtension: '.xlsx'),
    ).equals('Presupuesto.xlsx');
    check(
      fileShareFileName('a' * 120, fallbackExtension: '.pdf').length,
    ).equals(84);
  });

  group('safeDownloadFileName', () {
    test('keeps a server name out of the directory tree', () {
      check(safeDownloadFileName('../../etc/passwd')).equals('passwd');
      check(safeDownloadFileName('a/b/../c.xlsx')).equals('c.xlsx');
      check(safeDownloadFileName('gira\r\n.xlsx')).equals('gira.xlsx');
      check(safeDownloadFileName('..')).equals('document');
      check(safeDownloadFileName('')).equals('document');
    });

    test('keeps the tail of an over-long name', () {
      check(safeDownloadFileName('x' * 300).length).equals(120);
    });
  });

  group('resolveServerFileUrl', () {
    test('absolute URLs pass through', () {
      check(
        resolveServerFileUrl('https://cdn.test/a.pdf', 'https://owui.test'),
      ).equals('https://cdn.test/a.pdf');
    });

    test('root-relative paths join the server origin and base path', () {
      check(
        resolveServerFileUrl('/files/a.pdf', 'https://owui.test/base/'),
      ).equals('https://owui.test/base/files/a.pdf');
    });

    test('relative paths resolve under the base path', () {
      check(
        resolveServerFileUrl('files/a.pdf', 'https://owui.test/base'),
      ).equals('https://owui.test/base/files/a.pdf');
    });

    test('without a server a relative path stays as is', () {
      check(resolveServerFileUrl('files/a.pdf', null)).equals('files/a.pdf');
    });
  });
}
