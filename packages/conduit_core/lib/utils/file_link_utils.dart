import 'package:conduit_core/services/server_tls_http_client_factory.dart';

/// File links in a chat message that are not PDFs: which ones become a file
/// card instead of a hand-off to the browser, what that card is called, where
/// the bytes are fetched from and the name a share of them carries.

/// Extensions the app previews or downloads from a link. PDFs have their own
/// inline view and are deliberately not here.
const Set<String> _fileLinkExtensions = {
  // Office documents: Quick Look renders these on iOS.
  '.xls',
  '.xlsx',
  '.xlsm',
  '.csv',
  '.ppt',
  '.pptx',
  '.doc',
  '.docx',
  // Photos linked instead of embedded.
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.heic',
  '.heif',
  '.bmp',
};

/// The lowercase extension of [url]'s path with its leading dot, or `''` when
/// the path has none. The query and the fragment never count.
String fileExtensionFromUrl(String url) {
  final name = fileNameFromUrl(url);
  if (name == null) return '';
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == name.length - 1) return '';
  return name.substring(dotIndex).toLowerCase();
}

/// Whether [href] points at a file the app previews or downloads.
bool isFileLink(String href) {
  final extension = fileExtensionFromUrl(href);
  return extension.isNotEmpty && _fileLinkExtensions.contains(extension);
}

/// The file name the last path segment of [url] carries, URL-decoded, or null
/// when the path has no segments.
String? fileNameFromUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  final rawPath = uri?.path.isNotEmpty == true
      ? uri!.path
      : trimmed.split('?').first.split('#').first;
  final segments = rawPath.split('/').where((part) => part.isNotEmpty);
  if (segments.isEmpty) return null;
  return _decodeUriComponent(segments.last).trim();
}

/// The card title: the link label without a leading file emoji, else the file
/// name from the URL, else [fallback].
String fileLinkTitle({
  required String? rawLabel,
  required String url,
  required String fallback,
}) {
  final label = (rawLabel ?? '')
      .replaceFirst(
        RegExp(
          r'^\s*(?:\u{1F4C4}|\u{1F4CA}|\u{1F4CE}|\u{1F5BC})\s*',
          unicode: true,
        ),
        '',
      )
      .trim();
  if (label.isNotEmpty && label != url.trim()) {
    return label;
  }

  final fileName = fileNameFromUrl(url);
  if (fileName != null && fileName.isNotEmpty) {
    return fileName;
  }
  return fallback;
}

/// A file name for sharing [title]: letters, digits, spaces, `.`, `_`, `-`, at
/// most 80 characters, ending in [fallbackExtension] when it carries none.
String fileShareFileName(String title, {required String fallbackExtension}) {
  var base = title
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s._\-]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (base.length > 80) base = base.substring(0, 80).trim();
  if (base.isEmpty) base = 'document';
  if (RegExp(r'\.[\p{L}\p{N}]{1,5}$', unicode: true).hasMatch(base)) {
    return base;
  }
  return '$base$fallbackExtension';
}

/// A name [fileName] can be written to disk with: no directories, no control
/// characters, at most 120 characters. Server-supplied names go through this.
String safeDownloadFileName(String fileName) {
  final segments = fileName.split('/').where((part) => part.isNotEmpty);
  var name = (segments.isEmpty ? '' : segments.last)
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .trim();
  if (name == '.' || name == '..') name = '';
  if (name.length > 120) name = name.substring(name.length - 120);
  return name.isEmpty ? 'document' : name;
}

/// Resolves a server-relative [url] against the selected server's [baseUrl];
/// absolute URLs pass through.
String resolveServerFileUrl(String url, String? baseUrl) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return url;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.hasScheme) {
    return trimmed;
  }

  var baseUri = baseUrl == null
      ? null
      : ServerTlsHttpClientFactory.parseBaseUri(baseUrl);
  if (baseUri == null) {
    return trimmed;
  }

  if (trimmed.startsWith('/')) {
    return '${_baseUrlWithoutTrailingSlash(baseUri)}$trimmed';
  }

  if (!baseUri.path.endsWith('/')) {
    baseUri = baseUri.replace(path: '${baseUri.path}/');
  }

  return baseUri.resolveUri(uri).toString();
}

String _baseUrlWithoutTrailingSlash(Uri uri) {
  final withoutFragment = uri.removeFragment();
  final withoutQuery = withoutFragment.replace(query: null);
  return withoutQuery.toString().replaceFirst(RegExp(r'/+$'), '');
}

String _decodeUriComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}
