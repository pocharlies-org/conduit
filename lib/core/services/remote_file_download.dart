import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/utils/file_link_utils.dart';

import '../network/image_header_utils.dart';

/// Downloads a file the assistant generated to a local path, so it can be
/// previewed or handed to another app.
///
/// The server's session is attached only when [url] points at the configured
/// server: a generated file may live on a host of its own (ofimatica), which
/// must not receive the chat bearer. Throws [RemoteFileDownloadException] when
/// the bytes cannot be fetched.
Future<File> downloadServerFile({
  required String url,
  required ProviderContainer container,
  String? fileName,
}) async {
  final api = container.read(apiServiceProvider);
  final requestUrl = resolveServerFileUrl(url, api?.baseUrl);
  final headers =
      buildImageHeadersForUrlFromContainer(container, requestUrl) ??
      const <String, String>{};

  final Response<List<int>> response;
  try {
    response = await Dio().get<List<int>>(
      requestUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        validateStatus: (status) => status != null && status < 400,
      ),
    );
  } on DioException catch (error) {
    throw RemoteFileDownloadException(
      error.response?.statusCode == null
          ? 'sin respuesta del servidor'
          : 'HTTP ${error.response!.statusCode}',
      cause: error,
    );
  }

  final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
  if (contentType?.toLowerCase().startsWith('text/html') ?? false) {
    // A login or error page answering for a file: previewing it would show a
    // sign-in screen where a spreadsheet should be.
    throw const RemoteFileDownloadException('respuesta HTML, no el archivo');
  }

  final bytes = response.data;
  if (bytes == null || bytes.isEmpty) {
    throw const RemoteFileDownloadException('respuesta vacía');
  }

  final name = safeDownloadFileName(
    fileName ?? fileNameFromUrl(requestUrl) ?? 'archivo',
  );
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// Why a generated file could not be fetched.
class RemoteFileDownloadException implements Exception {
  const RemoteFileDownloadException(this.reason, {this.cause});

  final String reason;
  final Object? cause;

  @override
  String toString() => 'RemoteFileDownloadException: $reason';
}
