part of 'chat_providers.dart';

// Helper function to validate file size
bool validateFileSize(int fileSize, int? maxSizeMB) {
  if (maxSizeMB == null) return true;
  final maxSizeBytes = maxSizeMB * 1024 * 1024;
  return fileSize <= maxSizeBytes;
}

// Helper function to validate file count
bool validateFileCount(int currentCount, int newFilesCount, int? maxCount) {
  if (maxCount == null) return true;
  return (currentCount + newFilesCount) <= maxCount;
}

// Small internal helper to convert a message with attachments into the
// OpenWebUI content payload format (text + image_url + files).
// - Adds text first (if non-empty)
// - Images (base64 or server-stored) go into content array as image_url
// - Non-image files go into files array for RAG/server-side resolution
Future<Map<String, dynamic>> _buildMessagePayloadWithAttachments({
  required dynamic api,
  required String role,
  required String cleanedText,
  required List<String> attachmentIds,
}) async {
  final List<Map<String, dynamic>> contentArray = [];

  if (cleanedText.isNotEmpty) {
    contentArray.add({'type': 'text', 'text': cleanedText});
  }

  // Collect non-image files for the files array
  final allFiles = <Map<String, dynamic>>[];

  for (final attachmentId in attachmentIds) {
    try {
      // Check if this is a base64 data URL (legacy or inline)
      if (attachmentId.startsWith('data:image/')) {
        // Inline image data URL - add directly to content array for LLM vision
        contentArray.add({
          'type': 'image_url',
          'image_url': {'url': attachmentId},
        });
        continue;
      }

      // For server-stored files, fetch info to determine type
      final fileInfo = await api.getFileInfo(attachmentId);
      final fileName = fileInfo['filename'] ?? fileInfo['name'] ?? 'Unknown';
      final fileSize = fileInfo['size'] ?? fileInfo['meta']?['size'];
      final contentType =
          fileInfo['meta']?['content_type'] ?? fileInfo['content_type'] ?? '';

      // Check if this is an image file
      final isImage = contentType.toString().startsWith('image/');

      if (isImage) {
        // Images must be in content array as image_url for LLM vision
        // Fetch the image content from server and convert to base64 data URL
        try {
          final fileContent = await api.getFileContent(attachmentId);
          String dataUrl;
          if (fileContent.startsWith('data:')) {
            dataUrl = fileContent;
          } else {
            // Determine MIME type from content type or file extension
            final mimeType = contentType.isNotEmpty
                ? contentType.toString()
                : _getMimeTypeFromFileName(fileName) ?? 'image/png';
            dataUrl = 'data:$mimeType;base64,$fileContent';
          }
          contentArray.add({
            'type': 'image_url',
            'image_url': {'url': dataUrl},
          });
        } catch (error) {
          // If we can't fetch the image, skip it
        }
      } else {
        // Non-image files go to files array for RAG/server-side processing
        final filePayload = <String, dynamic>{
          'type': 'file',
          'id': attachmentId,
          // OpenWebUI now stores just the file ID, not the full URL path
          'url': attachmentId,
          'name': fileName,
        };
        if (fileSize != null) {
          filePayload['size'] = fileSize;
        }
        allFiles.add(filePayload);
      }
    } catch (_) {
      // Swallow and continue to keep regeneration robust
    }
  }

  final messageMap = <String, dynamic>{
    'role': role,
    'content': contentArray.isNotEmpty ? contentArray : cleanedText,
  };
  if (allFiles.isNotEmpty) {
    messageMap['files'] = allFiles;
  }
  return messageMap;
}

String? _getMimeTypeFromFileName(String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'svg' => 'image/svg+xml',
    'bmp' => 'image/bmp',
    _ => null,
  };
}

@visibleForTesting
String? mimeTypeFromFileNameForTest(String fileName) {
  return _getMimeTypeFromFileName(fileName);
}

List<Map<String, dynamic>> _contextAttachmentsToFiles(
  List<ChatContextAttachment> attachments,
) {
  return attachments.map((attachment) {
    switch (attachment.type) {
      case ChatContextAttachmentType.web:
        // Web pages use type 'text' with file data nested under 'file' key
        return {
          'type': 'text',
          'name': attachment.url ?? attachment.displayName,
          if (attachment.url != null) 'url': attachment.url,
          if (attachment.collectionName != null)
            'collection_name': attachment.collectionName,
          'file': {
            'data': {'content': attachment.content ?? ''},
            'meta': {
              'name': attachment.displayName,
              if (attachment.url != null) 'source': attachment.url,
            },
          },
        };
      case ChatContextAttachmentType.youtube:
        // YouTube uses type 'text' with context 'full' for full transcript
        return {
          'type': 'text',
          'name': attachment.url ?? attachment.displayName,
          if (attachment.url != null) 'url': attachment.url,
          'context': 'full',
          if (attachment.collectionName != null)
            'collection_name': attachment.collectionName,
          'file': {
            'data': {'content': attachment.content ?? ''},
            'meta': {
              'name': attachment.displayName,
              if (attachment.url != null) 'source': attachment.url,
            },
          },
        };
      case ChatContextAttachmentType.knowledge:
        // Knowledge base files use type 'file' with id for lookup
        final map = <String, dynamic>{
          'type': 'file',
          'id': attachment.fileId ?? attachment.id,
          'name': attachment.displayName,
          'knowledge': true,
          if (attachment.collectionName != null)
            'collection_name': attachment.collectionName,
          if (attachment.url != null) 'source': attachment.url,
        };
        return map;
      case ChatContextAttachmentType.note:
        return <String, dynamic>{
          'type': 'note',
          'id': attachment.id,
          'name': attachment.displayName,
          'title': attachment.displayName,
        };
    }
  }).toList();
}

/// Whether a send/regenerate should be blocked given the current backend state.
///
/// A send needs an OpenWebUI [api] or reviewer mode. A null [selectedModel]
/// always blocks. Extracted so the rule is unit-testable independent of the
/// large send pipelines.
@visibleForTesting
bool isSendBlocked({
  required bool reviewerMode,
  required Object? api,
  required Model? selectedModel,
}) {
  if (selectedModel == null) return true;
  if (reviewerMode) return false;
  return api == null;
}
