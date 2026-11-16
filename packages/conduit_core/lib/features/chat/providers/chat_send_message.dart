part of 'chat_providers.dart';

Future<void> _sendMessageInternal(
  dynamic ref,
  String message,
  List<String>? attachments, [
  List<String>? toolIds,
  bool isVoiceMode = false,
  String? pendingFolderIdOverride,
  void Function(ChatSendPlaceholderHandle handle)?
  onAssistantPlaceholderCreated,
  ChatSendVoiceContext? voice,
]) async {
  final conversationAtSendStart =
      ref.read(activeConversationProvider) as Conversation?;
  final sendMutationOwner = captureChatMutationOwner(
    ref,
    conversationAtSendStart,
  );
  // Settings chosen before this chat existed seed it; an existing chat reads
  // its own stored params further down, under its captured owner.
  final draftChatParamsAtSendStart = conversationAtSendStart == null
      ? Map<String, dynamic>.of(
          ref.read(pendingOpenWebUiChatSettingsProvider)
              as Map<String, dynamic>,
        )
      : const <String, dynamic>{};
  final reviewerMode = ref.read(reviewerModeProvider);
  final api = ref.read(apiServiceProvider);
  final selectedModelCandidate = ref.read(selectedModelProvider) as Model?;
  final reasoningEffortAtSendStart = ref.read(
    configuredReasoningEffortProvider,
  );
  // Admitted with the account and model this send started under.
  final codeInterpreterAtSendStart = _admitCodeInterpreter(ref);
  if (isSendBlocked(
    reviewerMode: reviewerMode,
    api: api,
    selectedModel: selectedModelCandidate,
  )) {
    throw Exception('No API service or model selected');
  }
  final Model selectedModel = selectedModelCandidate!;
  final serverModelId = selectedModel.id;
  final isLoadingConversation = ref.read(isLoadingConversationProvider);
  final currentConversation = ref.read(activeConversationProvider);
  if (!chatMutationTokenStillActive(ref, sendMutationOwner)) {
    throw StateError('The conversation changed while preparing the message.');
  }
  // Guard against a race where the user opens an existing chat and sends
  // before its history loads, which would otherwise create a new chat.
  if (isLoadingConversation && currentConversation == null) {
    throw StateError('Conversation is still loading');
  }

  // Get context attachments synchronously (no API calls)
  final contextAttachments = ref.read(contextAttachmentsProvider);
  final contextFiles = _contextAttachmentsToFiles(contextAttachments);

  // All attachments are server file IDs (images uploaded like OpenWebUI).
  // Legacy base64 support kept for backwards compatibility.
  final legacyBase64Images = <Map<String, dynamic>>[];
  final serverFileIds = <String>[];
  if (attachments != null) {
    for (final attachment in attachments) {
      if (attachment.startsWith('data:image/')) {
        legacyBase64Images.add({'type': 'image', 'url': attachment});
      } else {
        serverFileIds.add(attachment);
      }
    }
  }

  // Build initial user files with legacy base64 and context (server files
  // added later)
  final List<Map<String, dynamic>>? initialUserFiles =
      legacyBase64Images.isNotEmpty || contextFiles.isNotEmpty
      ? [...legacyBase64Images, ...contextFiles]
      : null;

  final existingMessages = ref.read(chatMessagesProvider);
  final openWebUiParentId = _resolveOpenWebUiParentIdForNewUserMessage(
    existingMessages,
  );

  // Create OpenWebUI-shaped user/assistant messages. Files will be updated
  // after fetching server info.
  final userMessageId = const Uuid().v4();
  final String assistantMessageId = const Uuid().v4();
  var userMessage = _withUserVoice(
    ChatMessage(
      id: userMessageId,
      role: 'user',
      content: message,
      timestamp: DateTime.now(),
      model: selectedModel.id,
      attachmentIds: attachments,
      files: initialUserFiles,
      metadata: {
        'parentId': openWebUiParentId,
        'childrenIds': <String>[assistantMessageId],
        'models': <String>[selectedModel.id],
      },
    ),
    voice,
  );

  // Add assistant placeholder immediately to show typing indicator right away
  final placeholder = ChatMessage(
    id: assistantMessageId,
    role: 'assistant',
    content: '',
    timestamp: DateTime.now(),
    model: selectedModel.id,
    isStreaming: true,
    metadata: {
      'parentId': userMessageId,
      'childrenIds': const <String>[],
      if (selectedModel.name.trim().isNotEmpty)
        'modelName': selectedModel.name.trim(),
    },
  );
  final voiceReply = voice?.reply;
  final assistantPlaceholder = voiceReply == null
      ? placeholder
      : _voiceReplyMessage(placeholder, voiceReply);
  final messagesNotifier =
      ref.read(chatMessagesProvider.notifier) as ChatMessagesNotifier;
  messagesNotifier.addMessages([userMessage, assistantPlaceholder]);
  final sendHandle = ChatSendPlaceholderHandle._(
    userMessageId: userMessageId,
    assistantMessageId: assistantMessageId,
    mutationOwner: sendMutationOwner,
  );
  onAssistantPlaceholderCreated?.call(sendHandle);
  if (voiceReply != null) {
    // The voice already answered: the turn is stored as it was said, and no
    // model runs. Chats this path holds only in memory keep it there.
    return;
  }

  // Now do async work in parallel: user settings + server file info
  String? userSystemPrompt;
  Map<String, dynamic>? userSettingsData;
  final serverFiles = <Map<String, dynamic>>[];

  if (!reviewerMode && api != null) {
    // Fetch user settings and server file info in parallel
    final settingsFuture = api.getUserSettings().catchError((_) => null);
    final fileInfoFutures = serverFileIds.map((fileId) async {
      try {
        final fileInfo = await api.getFileInfo(fileId);
        final fileName = fileInfo['filename'] ?? fileInfo['name'] ?? 'file';
        final fileSize = fileInfo['size'] ?? fileInfo['meta']?['size'];
        final contentType =
            fileInfo['meta']?['content_type'] ?? fileInfo['content_type'] ?? '';
        final collectionName =
            fileInfo['meta']?['collection_name'] ?? fileInfo['collection_name'];

        // Determine type: 'image' for image content types, 'file' for others
        // .toString() for safety against malformed API responses returning non-String
        final isImage = contentType.toString().startsWith('image/');
        final filePayload = <String, dynamic>{
          'type': isImage ? 'image' : 'file',
          'id': fileId,
          'name': fileName,
          // OpenWebUI now stores just the file ID, not the full URL path
          // The frontend resolves it when displaying
          'url': fileId,
        };
        if (fileSize != null) {
          filePayload['size'] = fileSize;
        }
        if (collectionName != null) {
          filePayload['collection_name'] = collectionName;
        }
        if (contentType.isNotEmpty) {
          filePayload['content_type'] = contentType;
        }
        return filePayload;
      } catch (_) {
        return <String, dynamic>{
          'type': 'file',
          'id': fileId,
          'name': 'file',
          'url': fileId,
        };
      }
    });

    // Wait for all async work to complete in parallel
    final fileInfoResults = await Future.wait(fileInfoFutures);
    userSettingsData = await settingsFuture;

    if (userSettingsData != null) {
      userSystemPrompt = _extractSystemPromptFromSettings(userSettingsData);
    }
    serverFiles.addAll(fileInfoResults);

    // Update user message with server file info if needed
    if (serverFiles.isNotEmpty || legacyBase64Images.isNotEmpty) {
      final allFiles = [...legacyBase64Images, ...serverFiles, ...contextFiles];
      userMessage = userMessage.copyWith(files: allFiles);
      ref
          .read(chatMessagesProvider.notifier)
          .updateMessageById(
            userMessageId,
            (ChatMessage m) => m.copyWith(files: allFiles),
          );
    }
  }

  // Check if we need to create a new conversation first
  var activeConversation = ref.read(activeConversationProvider);

  if (activeConversation == null) {
    final pendingFolderId =
        pendingFolderIdOverride ?? ref.read(pendingFolderIdProvider);
    final isTemporary = ref.read(temporaryChatEnabledProvider);

    if (isTemporary) {
      // Temporary chat: use local ID, skip server creation entirely
      final socketId = ref.read(socketServiceProvider)?.sessionId ?? 'unknown';
      final localConversation = Conversation(
        id: 'local:${socketId}_${const Uuid().v4()}',
        title: 'New Chat',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [userMessage, assistantPlaceholder],
        chatParams: draftChatParamsAtSendStart,
      );

      sendHandle._bindConversation(localConversation);
      ref.read(activeConversationProvider.notifier).set(localConversation);
      activeConversation = localConversation;
      ref.read(pendingFolderIdProvider.notifier).clear();
    } else {
      // Create new conversation with user message AND assistant placeholder
      // so the listener doesn't remove the placeholder when setting active
      final localConversation = Conversation(
        id: const Uuid().v4(),
        title: 'New Chat',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [userMessage, assistantPlaceholder],
        folderId: pendingFolderId,
        chatParams: draftChatParamsAtSendStart,
      );

      // Set as active conversation locally
      sendHandle._bindConversation(localConversation);
      ref.read(activeConversationProvider.notifier).set(localConversation);
      activeConversation = localConversation;

      if (!reviewerMode) {
        // Try to create on server - use lightweight message without large
        // base64 image data to avoid timeout (images sent in chat request)
        try {
          final lightweightMessage = userMessage.copyWith(
            attachmentIds: null,
            files: null,
            model: serverModelId,
            metadata: <String, dynamic>{
              ...?userMessage.metadata,
              'models': <String>[serverModelId],
            },
          );
          final serverConversation = await api.createConversation(
            title: 'New Chat',
            messages: [lightweightMessage],
            model: serverModelId,
            folderId: pendingFolderId,
            chatParams: draftChatParamsAtSendStart.isEmpty
                ? null
                : draftChatParamsAtSendStart,
          );

          // Clear the pending folder ID after successful creation
          ref.read(pendingFolderIdProvider.notifier).clear();

          // Keep local messages (user + assistant placeholder) instead of server
          // messages, since we're in the middle of sending and streaming
          final currentMessages = ref.read(chatMessagesProvider);
          final updatedConversation = localConversation.copyWith(
            id: serverConversation.id,
            messages: currentMessages,
            folderId: serverConversation.folderId ?? pendingFolderId,
          );
          sendHandle._bindConversation(updatedConversation);
          ref
              .read(activeConversationProvider.notifier)
              .set(updatedConversation);
          activeConversation = updatedConversation;

          ref
              .read(conversationsProvider.notifier)
              .upsertConversation(
                updatedConversation.copyWith(updatedAt: DateTime.now()),
                trustFolderConversation:
                    updatedConversation.folderId != null &&
                    updatedConversation.folderId!.isNotEmpty,
              );

          // CDT-RFC-001 Phase 1 (E4): materialize the chats row so the
          // stream-completion echo and pause checkpoint have a parent row.
          schedulePullChatNow(ref, serverConversation.id);

          // Invalidate conversations provider to refresh the list
          // Adding a small delay to prevent rapid invalidations that could cause duplicates
          Future.delayed(const Duration(milliseconds: 100), () {
            try {
              // Guard against using ref after provider disposal
              // Only Ref has .mounted; WidgetRef/ProviderContainer don't support
              // this check, so we proceed and let the underlying read operations
              // handle any disposal gracefully.
              final isMounted = ref is Ref ? ref.mounted : true;
              if (isMounted) {
                refreshConversationsCache(
                  ref,
                  includeFolders: pendingFolderId != null,
                );
              }
            } catch (_) {
              // If ref is disposed or invalid, skip
            }
          });
        } catch (e) {
          // Clear the pending folder ID on failure to prevent stale state
          ref.read(pendingFolderIdProvider.notifier).clear();
        }
      } else {
        // Clear the pending folder ID even in reviewer mode
        ref.read(pendingFolderIdProvider.notifier).clear();
      }
    }
  }

  // Reviewer mode: simulate a response locally and return
  if (reviewerMode) {
    // Check if there are attachments
    String? filename;
    if (attachments != null && attachments.isNotEmpty) {
      // Get the first attachment filename for the response
      // In reviewer mode, we just simulate having a file
      filename = "demo_file.txt";
    }

    // Check if this is voice input
    // In reviewer mode, we don't have actual voice input state
    final isVoiceInput = false;

    // Generate appropriate canned response
    final responseText = ReviewerModeService.generateResponse(
      userMessage: message,
      filename: filename,
      isVoiceInput: isVoiceInput,
    );

    // Simulate token-by-token streaming
    final words = responseText.split(' ');
    for (final word in words) {
      await Future.delayed(const Duration(milliseconds: 40));
      ref.read(chatMessagesProvider.notifier).appendToLastMessage('$word ');
    }
    ref.read(chatMessagesProvider.notifier).finishStreaming();

    // Save locally
    await _saveConversationLocally(ref);
    return;
  }

  // Get conversation history for context
  final List<ChatMessage> messages = ref.read(chatMessagesProvider);
  final List<Map<String, dynamic>> conversationMessages =
      <Map<String, dynamic>>[];

  for (final msg in messages) {
    // Skip in-progress assistant placeholders, but include assistant replies
    // that already settled their response content in the responseDone gap.
    if (_shouldIncludeConversationHistoryMessage(msg)) {
      // Prepare cleaned text content (strip tool details etc.)
      final cleaned = ToolCallsParser.sanitizeForApi(msg.content);

      final List<String> ids = msg.attachmentIds ?? const <String>[];
      if (ids.isNotEmpty) {
        final messageMap = await _buildMessagePayloadWithAttachments(
          api: api!,
          role: msg.role,
          cleanedText: cleaned,
          attachmentIds: ids,
        );
        if (msg.files != null && msg.files!.isNotEmpty) {
          // Safe cast - messageMap['files'] may be List<dynamic> after storage
          final rawFiles = messageMap['files'];
          final existingFiles = rawFiles is List
              ? rawFiles.whereType<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];
          messageMap['files'] = <Map<String, dynamic>>[
            ...existingFiles,
            ...msg.files!,
          ];
        }
        if (msg.output != null && msg.output!.isNotEmpty) {
          messageMap['output'] = msg.output;
        }
        conversationMessages.add(messageMap);
      } else {
        // Regular text-only message
        final Map<String, dynamic> messageMap = {
          'role': msg.role,
          'content': cleaned,
          if (msg.output != null) 'output': msg.output,
        };
        if (msg.files != null && msg.files!.isNotEmpty) {
          messageMap['files'] = msg.files;
        }
        conversationMessages.add(messageMap);
      }
    }
  }

  final selectedToolIds = toolIds ?? const <String>[];
  final toolIdsForApi = _extractToolIdsForApi(selectedToolIds);
  final isTemporary =
      (activeConversation != null && isTemporaryChat(activeConversation.id)) ||
      ref.read(temporaryChatEnabledProvider);

  // Check feature toggles for API (gated by server availability)
  final webSearchEnabled =
      ref.read(webSearchEnabledProvider) &&
      ref.read(webSearchAvailableProvider);
  final imageGenerationEnabled =
      ref.read(imageGenerationEnabledProvider) &&
      ref.read(imageGenerationAvailableProvider);

  // Get selected toggle filter IDs
  final selectedFilterIds = selectedFilterIdsForModel(ref, selectedModel);
  final List<String>? filterIdsForApi = selectedFilterIds.isNotEmpty
      ? selectedFilterIds
      : null;

  String? chatIdForBuffer;
  String? sessionIdForBuffer;
  String? messageIdForBuffer;
  OpenWebUiCompletionOwner? submittedOpenWebUiOwner;
  try {
    final modelItem = _buildLocalModelItem(selectedModel);
    final submittedConversation = activeConversation;
    final submittedOwner = submittedConversation == null
        ? null
        : captureOpenWebUiCompletionOwner(
            ref,
            chatId: submittedConversation.id,
            api: api,
          );
    submittedOpenWebUiOwner = submittedOwner;

    bool ownsOpenWebUiPreflight() => submittedOwner == null
        ? chatMutationTokenStillActive(ref, sendMutationOwner)
        : activeOpenWebUiChatIdForMutation(ref, submittedOwner) != null;

    void requireOpenWebUiPreflightOwner() {
      if (!ownsOpenWebUiPreflight()) {
        throw StateError(
          'The conversation changed while preparing the message.',
        );
      }
    }

    // The chat's own settings, read through the owner captured above (a chat
    // that does not exist yet carries the draft it was created with).
    final pickerReasoningEffort = reasoningEffortForModel(
      ref.read,
      selectedModel,
    );
    final turnSettings = submittedOwner == null
        ? _OpenWebUiTurnSettings(
            chatParams:
                activeConversation?.chatParams ?? const <String, dynamic>{},
            reasoningEffort: pickerReasoningEffort,
          )
        : await _resolveOpenWebUiTurnSettings(
            submittedOwner,
            conversation: submittedConversation,
            pickerReasoningEffort: pickerReasoningEffort,
          );
    requireOpenWebUiPreflightOwner();
    _insertOpenWebUiSystemMessage(
      conversationMessages,
      chatParams: turnSettings.chatParams,
      legacyChatSystem: activeConversation?.systemPrompt,
      globalSystem: userSystemPrompt,
    );
    final requestMessages = _buildChatCompletionMessages(
      conversationMessages: conversationMessages,
      isTemporary: isTemporary,
    );

    // Reconnect before choosing session_id so eligible sends stay on the
    // task/socket transport instead of falling back to fragile HTTP streaming.
    final socketService = _readOpenWebUiSocketForApi(ref, api);
    final socketSessionId = await _ensureConnectedSocketSessionId(
      socketService,
    );
    requireOpenWebUiPreflightOwner();

    List<Map<String, dynamic>>? toolServers;
    final admittedToolServers = <PersonalToolAdmission>[];
    try {
      toolServers = await _resolveToolServersForRequest(
        api: api,
        userSettings: userSettingsData,
        selectedToolIds: selectedToolIds,
        onUnresolvedSelections: (ids) =>
            _clearUnresolvedPersonalToolSelections(ref, ids),
        admitted: admittedToolServers,
      );
    } catch (_) {}
    requireOpenWebUiPreflightOwner();
    final codeInterpreterEnabled = codeInterpreterAtSendStart;

    // Background tasks should follow backend-synced user settings instead of
    // forcing local defaults. Enable title/tags generation only on the first
    // user turn of a new chat.
    bool shouldGenerateTitle = false;
    if (!isTemporary) {
      try {
        final conv = ref.read(activeConversationProvider);
        // Use the outbound conversationMessages we just built (excludes streaming placeholders)
        final nonSystemCount = conversationMessages
            .where((m) => (m['role']?.toString() ?? '') != 'system')
            .length;
        shouldGenerateTitle =
            (conv == null) ||
            ((conv.title == 'New Chat' || (conv.title.isEmpty)) &&
                nonSystemCount == 1);
      } catch (_) {}
    }

    final bgTasks = _buildOpenWebUiBackgroundTasks(
      userSettings: userSettingsData,
      shouldGenerateTitle: shouldGenerateTitle,
    );

    // Determine if we need background task flow (tools/tool servers or web search)
    final bool isBackgroundToolsFlowPre =
        toolIdsForApi.isNotEmpty ||
        (toolServers != null && toolServers.isNotEmpty);
    final bool isBackgroundWebSearchPre = webSearchEnabled;

    // Find the last user message ID for proper parent linking
    final lastUserMessageId = _lastUserMessageId(messages);

    // Use transport-aware session dispatch
    // Build template variables for prompt substitution (matches OpenWebUI's
    // getPromptVariables). The backend replaces {{USER_NAME}} etc. in system
    // prompts and tool descriptions.
    Map<String, dynamic>? promptVariables;
    Map<String, dynamic>? userMessageMap;
    try {
      promptVariables = await _buildOpenWebUiPromptVariablesForRequest(
        ref,
        now: DateTime.now(),
        userSettings: userSettingsData,
      );
    } catch (e) {
      DebugLogger.error(
        'Failed to build prompt variables: $e',
        scope: 'chat/providers',
        error: e,
      );
    }
    requireOpenWebUiPreflightOwner();

    try {
      userMessageMap = _buildOpenWebUiUserMessage(
        messages: messages,
        userMessageId: lastUserMessageId,
        modelId: serverModelId,
        assistantChildMessageId: assistantMessageId,
      );
    } catch (_) {}

    // Start buffering socket events for this chat BEFORE sending the HTTP
    // request. The backend may emit events (especially for fast pipe models)
    // before dispatchChatTransport registers the streaming handler.
    chatIdForBuffer = activeConversation?.id;
    sessionIdForBuffer = socketSessionId;
    messageIdForBuffer = assistantMessageId;
    if (chatIdForBuffer != null) {
      socketService?.startBuffering(
        chatIdForBuffer,
        sessionId: sessionIdForBuffer,
        messageId: messageIdForBuffer,
      );
    }

    try {
      requireOpenWebUiPreflightOwner();
      _admitPersonalToolServers(
        socketService,
        sessionId: socketSessionId,
        chatId: submittedOwner?.chatId,
        messageId: assistantMessageId,
        admitted: admittedToolServers,
      );
      final session = await api.sendMessageSession(
        messages: requestMessages,
        model: serverModelId,
        conversationId: submittedOwner?.chatId,
        toolIds: toolIdsForApi.isNotEmpty ? toolIdsForApi : null,
        filterIds: filterIdsForApi,
        enableWebSearch: webSearchEnabled,
        enableImageGeneration: imageGenerationEnabled,
        enableCodeInterpreter: codeInterpreterEnabled,
        isVoiceMode: isVoiceMode,
        modelItem: modelItem,
        sessionIdOverride: socketSessionId,
        toolServers: toolServers,
        backgroundTasks: bgTasks,
        responseMessageId: assistantMessageId,
        userSettings: userSettingsData,
        chatParams: turnSettings.chatParams,
        reasoningEffort: turnSettings.reasoningEffort,
        parentId: userMessageMap?['parentId']?.toString(),
        userMessage: userMessageMap,
        variables: promptVariables,
        files: _extractTopLevelRequestFiles(userMessageMap),
      );

      if (submittedOwner != null) {
        submittedOwner.chatId = await resolveOpenWebUiCompletionChatId(
          ref,
          owner: submittedOwner,
          assistantMessageId: assistantMessageId,
        );
      }
      final activeOwnerChatId = submittedOwner == null
          ? null
          : activeOpenWebUiChatIdForMutation(ref, submittedOwner);
      final ownerStillActive = activeOwnerChatId != null;
      if (activeOwnerChatId != null) {
        submittedOwner!.chatId = activeOwnerChatId;
        final active = ref.read(activeConversationProvider) as Conversation?;
        if (active != null) sendHandle._bindConversation(active);
      }
      if (!ownerStillActive) {
        DebugLogger.log(
          'send-owner-changed-after-submit',
          scope: 'chat/completion',
          data: {
            'chatId': submittedOwner?.chatId,
            'assistantMessageId': assistantMessageId,
          },
        );
        if (submittedOwner == null || isTemporary) {
          // Temporary chats have no durable server resource to recover into.
          await _abortQuietly(session);
        } else {
          await _finishSubmittedOpenWebUiCompletionHeadlessly(
            ref,
            session: session,
            owner: submittedOwner,
            assistantMessageId: assistantMessageId,
            // Inline sends have no requestCompletion outbox op that could
            // replay this POST when a legacy placeholder row is absent.
            requireDurableSubmittedMarker: false,
          );
        }
      } else {
        final modelUsesReasoning2 = _modelUsesReasoning(selectedModel.id);

        final bool isBackgroundFlow =
            isBackgroundToolsFlowPre ||
            isBackgroundWebSearchPre ||
            imageGenerationEnabled ||
            codeInterpreterEnabled ||
            bgTasks.isNotEmpty;

        final attached = await dispatchChatTransport(
          ref: ref,
          session: session,
          assistantMessageId: assistantMessageId,
          modelId: serverModelId,
          modelItem: modelItem,
          activeConversationId: submittedOwner?.chatId,
          api: api,
          socketService: socketService,
          workerManager: ref.read(workerManagerProvider),
          webSearchEnabled: webSearchEnabled,
          imageGenerationEnabled: imageGenerationEnabled,
          isBackgroundFlow: isBackgroundFlow,
          modelUsesReasoning: modelUsesReasoning2,
          toolsEnabled:
              toolIdsForApi.isNotEmpty ||
              (toolServers != null && toolServers.isNotEmpty) ||
              imageGenerationEnabled ||
              codeInterpreterEnabled,
          isTemporary: isTemporary,
          filterIds: filterIdsForApi,
          ownsActiveConversation: () =>
              activeOpenWebUiChatIdForMutation(ref, submittedOwner!) != null,
        );
        if (!attached) {
          if (isTemporary) {
            await _abortQuietly(session);
          } else {
            await _finishSubmittedOpenWebUiCompletionHeadlessly(
              ref,
              session: session,
              owner: submittedOwner!,
              assistantMessageId: assistantMessageId,
              requireDurableSubmittedMarker: false,
            );
          }
        }
      }
    } finally {
      if (chatIdForBuffer != null) {
        socketService?.stopBuffering(
          chatIdForBuffer,
          sessionId: sessionIdForBuffer,
          messageId: messageIdForBuffer,
        );
      }
    }

    // Clear context attachments after successfully initiating the message send.
    // This prevents stale attachments from being included in subsequent messages.
    try {
      final ownerStillActive =
          submittedOwner != null &&
          activeOpenWebUiChatIdForMutation(ref, submittedOwner) != null;
      if (ownerStillActive &&
          identical(ref.read(contextAttachmentsProvider), contextAttachments)) {
        ref.read(contextAttachmentsProvider.notifier).clear();
      }
    } catch (_) {}

    return;
  } catch (e, st) {
    // Clean up buffering on error
    DebugLogger.error(
      '_sendMessageInternal failed: $e',
      scope: 'chat/providers',
      error: e,
      stackTrace: st,
    );
    // Convert the assistant placeholder in-place to an error-state
    // message. This preserves the placeholder's ID and any files that
    // may have arrived before the error, matching OpenWebUI's same-slot
    // failure semantics.
    // Explicit ChatMessage type on closures is required because `ref` is
    // `dynamic` — without it Dart infers (dynamic) => dynamic at runtime.
    final ChatMessagesNotifier notifier =
        ref.read(chatMessagesProvider.notifier) as ChatMessagesNotifier;
    final ownerStillActive = submittedOpenWebUiOwner != null
        ? activeOpenWebUiChatIdForMutation(ref, submittedOpenWebUiOwner) != null
        : chatMutationTokenStillActive(ref, sendMutationOwner);
    if (ownerStillActive &&
        sendHandle._owns(
          ref,
          ref.read(activeConversationProvider) as Conversation?,
        )) {
      notifier.failLastStreamingAssistant(
        e,
        assistantMessageId: assistantMessageId,
      );
    }
    // A 401 or 403 here may be a model provider rejecting its API key, which
    // Open WebUI passes through, or the session ending. Ask the session
    // endpoint: as everywhere else, the auth interceptor reports its refusal
    // as the session ending, and a provider's refusal only marks the reply.
    if (e is ChatCompletionHttpException && e.mayRejectSession) {
      final ApiService? api = ref.read(apiServiceProvider) as ApiService?;
      if (api != null) {
        unawaited(
          api.getCurrentUser().then<void>(
            (_) {},
            onError: (Object error) => DebugLogger.log(
              'session-check-after-refused-completion',
              scope: 'chat/providers',
              data: {'errorType': error.runtimeType.toString()},
            ),
          ),
        );
      }
    }
  }
}

/// Returns a user-friendly error description based on the exception.
String chatErrorContentForException(Object e) {
  if (e is CodeInterpreterUnavailableException) {
    return '${e.message} Send the message again without it.';
  }

  final msg = e.toString();
  if (msg.contains('400')) {
    return 'There was an issue with the message format. This might be '
        'because the image attachment couldn\'t be processed, the request '
        'format is incompatible with the selected model, or the message '
        'contains unsupported content. Please try sending the message '
        'again, or try without attachments.';
  } else if (msg.contains('500')) {
    return 'Unable to connect to the AI model. The server returned an '
        'error (500). This is typically a server-side issue. Please try '
        'again or contact your administrator.';
  } else if (msg.contains('404')) {
    DebugLogger.log(
      'Model or endpoint not found (404)',
      scope: 'chat/providers',
    );
    return 'The selected AI model doesn\'t seem to be available. '
        'Please try selecting a different model or check with your '
        'administrator.';
  } else {
    return 'An unexpected error occurred while processing your request. '
        'Please try again or check your connection.';
  }
}

// Save current conversation to OpenWebUI server
// Removed server persistence; only local caching is used in mobile app.

// Fallback: Save current conversation to local storage
Future<void> _saveConversationLocally(dynamic ref) async {
  var ownerDisposed = false;
  if (ref is Ref) {
    ref.onDispose(() => ownerDisposed = true);
  }
  final dynamic ownerContext = _isWidgetRef(ref) ? ref.context : null;

  try {
    final messages = ref.read(chatMessagesProvider);
    final activeConversation = ref.read(activeConversationProvider);

    if (messages.isEmpty) return;

    // Create or update conversation locally
    final conversation =
        activeConversation ??
        Conversation(
          id: const Uuid().v4(),
          title: _generateConversationTitle(messages),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          messages: messages,
        );

    final copiedConversation = conversation.copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );
    final updatedConversation = activeConversation == null
        ? copiedConversation
        : copiedConversation;

    final db = _readAppDatabaseOrNull(ref);
    if (db != null && !isTemporaryChat(updatedConversation.id)) {
      final lastReadAt = updatedConversation.lastReadAt;
      // ChatLocks discipline: serialize with pull merges / turn echoes so a
      // stale optimistic stub can never overwrite a just-merged server row.
      final ChatLocks locks = ref.read(chatLocksProvider);
      await locks.runExclusive(updatedConversation.id, () async {
        await db.chatsDao.upsertEnvelopeStub(
          id: updatedConversation.id,
          title: updatedConversation.title,
          createdAt:
              updatedConversation.createdAt.millisecondsSinceEpoch ~/ 1000,
          updatedAt:
              updatedConversation.updatedAt.millisecondsSinceEpoch ~/ 1000,
          pinned: updatedConversation.pinned,
          archived: updatedConversation.archived,
          folderId: Value(updatedConversation.folderId),
          lastReadAt: lastReadAt == null
              ? null
              : lastReadAt.millisecondsSinceEpoch ~/ 1000,
        );
      });
    }

    // This helper can outlive a voice-mode/service notifier while awaiting the
    // database lock. Once that owner is gone, its completion must not mutate
    // app state or schedule another pull through the disposed Ref.
    if (ownerDisposed || (ownerContext != null && !ownerContext.mounted)) {
      return;
    }
    ref.read(activeConversationProvider.notifier).set(updatedConversation);
    refreshConversationsCache(ref);
  } catch (e) {
    DebugLogger.error(
      'Failed to save conversation locally',
      scope: 'chat/providers',
      error: e,
    );
  }
}

String _generateConversationTitle(List<ChatMessage> messages) {
  final firstUserMessage = messages.firstWhere(
    (msg) => msg.role == 'user',
    orElse: () => ChatMessage(
      id: '',
      role: 'user',
      content: 'New Chat',
      timestamp: DateTime.now(),
    ),
  );

  // Use first 50 characters of the first user message as title
  final title = firstUserMessage.content.length > 50
      ? '${firstUserMessage.content.substring(0, 50)}...'
      : firstUserMessage.content;

  return title.isEmpty ? 'New Chat' : title;
}
