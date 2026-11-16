part of 'chat_providers.dart';

/// The model and column a regeneration belongs to when the answer being
/// regenerated is one of several models' answers to one prompt.
///
/// Open WebUI regenerates such an answer with ITS model and keeps its column
/// (`modelIdx`), whatever the picker holds now; a duplicate-model chat is
/// told apart by the column alone. A single-model turn returns null and
/// regenerates with the picker's model as before.
({String modelId, int slot})? _comparisonRegenerationTarget(
  List<ChatMessage> messages,
) {
  if (messages.isEmpty || messages.last.role != 'assistant') return null;
  final tail = messages.last;
  final modelId = tail.model?.trim() ?? '';
  if (modelId.isEmpty) return null;
  for (var index = messages.length - 2; index >= 0; index--) {
    final candidate = messages[index];
    if (candidate.role != 'user') continue;
    final models = candidate.metadata?['models'];
    if (models is List && models.length > 1) {
      return (modelId: modelId, slot: tail.modelSlot);
    }
    return null;
  }
  return null;
}

Future<void> regenerateMessage(
  dynamic ref,
  String userMessageContent,
  List<String>? attachments, {
  bool forceImageGeneration = false,
  bool Function()? ownsPreparationState,
}) async {
  final conversationAtRegenerationStart =
      ref.read(activeConversationProvider) as Conversation?;
  final regenerationMutationOwner = captureChatMutationOwner(
    ref,
    conversationAtRegenerationStart,
  );
  bool ownsCurrentPreparationState() {
    try {
      return ownsPreparationState?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  final reviewerMode = ref.read(reviewerModeProvider);
  final api = ref.read(apiServiceProvider);
  final selectedModelCandidate = ref.read(selectedModelProvider) as Model?;
  // Admitted with the account and model this regeneration started under.
  final codeInterpreterAtRegenerationStart = _admitCodeInterpreter(ref);
  if (!ownsCurrentPreparationState()) {
    return;
  }
  if (!chatMutationTokenStillActive(ref, regenerationMutationOwner)) {
    throw StateError('The conversation changed while preparing regeneration.');
  }
  if (isSendBlocked(
    reviewerMode: reviewerMode,
    api: api,
    selectedModel: selectedModelCandidate,
  )) {
    throw Exception('No API service or model selected');
  }
  Model selectedModel = selectedModelCandidate!;
  var serverModelId = selectedModel.id;

  var activeConversation = ref.read(activeConversationProvider);
  if (activeConversation == null) {
    throw Exception('No active conversation');
  }
  // Regenerating one answer of a multi-model turn keeps that answer's model and
  // column whatever the picker holds now.
  final comparisonTarget = reviewerMode
      ? null
      : _comparisonRegenerationTarget(
          ref.read(chatMessagesProvider) as List<ChatMessage>,
        );
  if (comparisonTarget != null) {
    final listed =
        (ref.read(modelsProvider) as AsyncValue<List<Model>>).asData?.value ??
        const <Model>[];
    selectedModel =
        listed
            .where((model) => model.id == comparisonTarget.modelId)
            .firstOrNull ??
        Model(id: comparisonTarget.modelId, name: comparisonTarget.modelId);
    serverModelId = selectedModel.id;
  }
  final regenerationOwner = captureOpenWebUiCompletionOwner(
    ref,
    chatId: activeConversation.id,
    api: api,
  );
  ChatSendPlaceholderHandle? regenerationPlaceholder;
  var regenerationPlaceholderWasEstablished = false;
  ChatCompletionSession? submittedSession;
  void requireRegenerationOwner() {
    final activeChatId = activeOpenWebUiChatIdForMutation(
      ref,
      regenerationOwner,
    );
    if (activeChatId == null) {
      throw StateError('The conversation changed while regenerating.');
    }
    regenerationOwner.chatId = activeChatId;
  }

  // In reviewer mode, simulate response
  if (reviewerMode) {
    final assistantMessage = ChatMessage(
      id: const Uuid().v4(),
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      model: selectedModel.id,
      isStreaming: true,
      metadata: {'modelName': selectedModel.name},
    );
    ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);

    // Helpers defined above

    // Use canned response for regeneration
    final responseText = ReviewerModeService.generateResponse(
      userMessage: userMessageContent,
    );

    // Simulate streaming response
    final words = responseText.split(' ');
    for (final word in words) {
      await Future.delayed(const Duration(milliseconds: 40));
      if (!chatMutationTokenStillActive(ref, regenerationMutationOwner)) {
        return;
      }
      ref.read(chatMessagesProvider.notifier).appendToLastMessage('$word ');
    }

    if (!chatMutationTokenStillActive(ref, regenerationMutationOwner)) return;
    ref.read(chatMessagesProvider.notifier).finishStreaming();
    await _saveConversationLocally(ref);
    return;
  }

  // For real API, proceed with regeneration using existing conversation messages
  try {
    Map<String, dynamic>? userSettingsData;
    String? userSystemPrompt;
    try {
      userSettingsData = await api!.getUserSettings();
      userSystemPrompt = _extractSystemPromptFromSettings(userSettingsData);
    } catch (_) {}
    if (!ownsCurrentPreparationState()) return;
    requireRegenerationOwner();

    // The chat's own settings, read through the owner captured above so a
    // regenerated (or historical) turn is sent like the original was.
    final turnSettings = await _resolveOpenWebUiTurnSettings(
      regenerationOwner,
      conversation: activeConversation,
      pickerReasoningEffort: reasoningEffortForModel(ref.read, selectedModel),
    );
    if (!ownsCurrentPreparationState()) return;
    requireRegenerationOwner();

    // Include selected tool ids so provider-native tool calling is triggered
    final selectedToolIds = ref.read(selectedToolIdsProvider);
    final toolIdsForApi = _extractToolIdsForApi(selectedToolIds);
    // Include selected filter ids (toggle filters enabled by user)
    final selectedFilterIds = selectedFilterIdsForModel(ref, selectedModel);
    // Get conversation history for context, skipping archived variants that are
    // kept locally only for the version switcher.
    final List<ChatMessage> messages = ref.read(chatMessagesProvider);
    final List<Map<String, dynamic>> conversationMessages =
        <Map<String, dynamic>>[];
    var lastUserIndex = -1;
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].role == 'user') {
        lastUserIndex = index;
        break;
      }
    }

    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (_isArchivedAssistantVariant(msg)) {
        continue;
      }
      if (_shouldIncludeConversationHistoryMessage(msg)) {
        final cleaned = ToolCallsParser.sanitizeForApi(msg.content);

        // Prefer provided attachments for the last user message; otherwise use message attachments
        final bool isLastUser = i == lastUserIndex && msg.role == 'user';
        final List<String> messageAttachments =
            (isLastUser && (attachments != null && attachments.isNotEmpty))
            ? List<String>.from(attachments)
            : (msg.attachmentIds ?? const <String>[]);

        if (messageAttachments.isNotEmpty) {
          final messageMap = await _buildMessagePayloadWithAttachments(
            api: api,
            role: msg.role,
            cleanedText: cleaned,
            attachmentIds: messageAttachments,
          );
          if (!ownsCurrentPreparationState()) return;
          requireRegenerationOwner();
          if (msg.files != null && msg.files!.isNotEmpty) {
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
          conversationMessages.add({
            'role': msg.role,
            'content': cleaned,
            if (msg.files != null) 'files': msg.files,
            if (msg.output != null) 'output': msg.output,
          });
        }
      }
    }

    _insertOpenWebUiSystemMessage(
      conversationMessages,
      chatParams: turnSettings.chatParams,
      legacyChatSystem: activeConversation.systemPrompt,
      globalSystem: userSystemPrompt,
    );
    final isTemporary =
        isTemporaryChat(activeConversation.id) ||
        ref.read(temporaryChatEnabledProvider);
    final requestMessages = _buildChatCompletionMessages(
      conversationMessages: conversationMessages,
      isTemporary: isTemporary,
    );
    if (!ownsCurrentPreparationState()) return;
    requireRegenerationOwner();

    // Pre-seed assistant skeleton and persist chain; always use a new id so
    // server history can branch like OpenWebUI.
    final assistantMessageId = const Uuid().v4();
    final regenerationAttemptId = const Uuid().v4();
    final regenerationPlaceholderForAttempt = ChatSendPlaceholderHandle._(
      assistantMessageId: assistantMessageId,
      mutationOwner: regenerationMutationOwner,
      regenerationAttemptId: regenerationAttemptId,
    );
    regenerationPlaceholder = regenerationPlaceholderForAttempt;
    bool ownsLiveRegenerationPlaceholder() {
      try {
        final activeChatId = activeOpenWebUiChatIdForMutation(
          ref,
          regenerationOwner,
        );
        if (activeChatId == null) return false;
        // Keep the request destination synchronized with an in-place local ->
        // remote OpenWebUI id remap that lands during any preflight await.
        regenerationOwner.chatId = activeChatId;
        return _tailOwnedOpenWebUiRegenerationPlaceholder(
              ref,
              regenerationPlaceholderForAttempt,
            ) !=
            null;
      } catch (_) {
        return false;
      }
    }

    await _preseedAssistantAndPersist(
      ref,
      existingAssistantId: assistantMessageId,
      modelId: selectedModel.id,
      modelName: selectedModel.name,
      placeholderMetadata: <String, dynamic>{
        _openWebUiRegenerationAttemptMetadataKey: regenerationAttemptId,
        if (comparisonTarget != null)
          kMessageModelIdxMetadataKey: comparisonTarget.slot,
      },
    );
    regenerationPlaceholderWasEstablished = true;
    if (!ownsLiveRegenerationPlaceholder()) {
      _clearOpenWebUiRegenerationAttemptMarker(
        ref,
        regenerationPlaceholderForAttempt,
      );
      return;
    }

    // Attach previous assistant as a version snapshot to the new assistant
    try {
      final msgs = ref.read(chatMessagesProvider);
      if (msgs.length >= 2) {
        final prev = msgs[msgs.length - 2];
        final last = msgs.last;
        if (prev.role == 'assistant' && last.id == assistantMessageId) {
          (ref.read(chatMessagesProvider.notifier) as ChatMessagesNotifier)
              .updateLastMessageWithFunction(
                (ChatMessage m) =>
                    m.copyWith(versions: _buildReplayVersions(prev)),
              );
        }
      }
    } catch (_) {}

    // Feature toggles
    final webSearchEnabled =
        ref.read(webSearchEnabledProvider) &&
        ref.read(webSearchAvailableProvider);
    final imageGenerationEnabled =
        (forceImageGeneration || ref.read(imageGenerationEnabledProvider)) &&
        ref.read(imageGenerationAvailableProvider);

    final modelItem = _buildLocalModelItem(
      selectedModel,
      wireModelId: serverModelId,
    );

    // Reconnect before choosing session_id so eligible sends stay on the
    // task/socket transport instead of falling back to fragile HTTP streaming.
    final socketService = _readOpenWebUiSocketForApi(ref, api);
    final socketSessionId = await _ensureConnectedSocketSessionId(
      socketService,
    );
    if (!ownsLiveRegenerationPlaceholder()) {
      _clearOpenWebUiRegenerationAttemptMarker(
        ref,
        regenerationPlaceholderForAttempt,
      );
      return;
    }

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
    if (!ownsLiveRegenerationPlaceholder()) {
      _clearOpenWebUiRegenerationAttemptMarker(
        ref,
        regenerationPlaceholderForAttempt,
      );
      return;
    }
    final codeInterpreterEnabled = codeInterpreterAtRegenerationStart;

    // Background tasks should follow backend-synced user settings instead of
    // forcing local defaults.
    bool shouldGenerateTitle = false;
    if (!isTemporary) {
      try {
        final conv = ref.read(activeConversationProvider);
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
      webSearchEnabled: webSearchEnabled,
      imageGenerationEnabled: imageGenerationEnabled,
    );

    final bool isBackgroundToolsFlowPre =
        toolIdsForApi.isNotEmpty ||
        (toolServers != null && toolServers.isNotEmpty);
    final bool isBackgroundWebSearchPre = webSearchEnabled;

    // Find the last user message ID for proper parent linking
    String? lastUserMessageId;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') {
        lastUserMessageId = messages[i].id;
        break;
      }
    }

    // Build template variables (same as _sendMessageInternal)
    Map<String, dynamic>? promptVars2;
    Map<String, dynamic>? parentMsgMap;
    try {
      promptVars2 = await _buildOpenWebUiPromptVariablesForRequest(
        ref,
        now: DateTime.now(),
        userSettings: userSettingsData,
      );
    } catch (_) {}

    try {
      parentMsgMap = _buildOpenWebUiUserMessage(
        messages: messages,
        userMessageId: lastUserMessageId,
        modelId: serverModelId,
        assistantChildMessageId: assistantMessageId,
      );
    } catch (_) {}
    if (!ownsLiveRegenerationPlaceholder()) {
      _clearOpenWebUiRegenerationAttemptMarker(
        ref,
        regenerationPlaceholderForAttempt,
      );
      return;
    }

    // Start buffering socket events before sending to avoid timing races.
    // Include session/message aliases because some early taskSocket events are
    // emitted before the handler attaches and may not carry chat_id yet.
    final regenSocketService = socketService;
    final bufferedChatId = regenerationOwner.chatId;
    regenSocketService?.startBuffering(
      bufferedChatId,
      sessionId: socketSessionId,
      messageId: assistantMessageId,
    );

    try {
      if (!ownsLiveRegenerationPlaceholder()) {
        _clearOpenWebUiRegenerationAttemptMarker(
          ref,
          regenerationPlaceholderForAttempt,
        );
        return;
      }
      _admitPersonalToolServers(
        regenSocketService,
        sessionId: socketSessionId,
        chatId: regenerationOwner.chatId,
        messageId: assistantMessageId,
        admitted: admittedToolServers,
      );
      // Use transport-aware session dispatch
      final session = await api!.sendMessageSession(
        messages: requestMessages,
        model: serverModelId,
        conversationId: regenerationOwner.chatId,
        toolIds: toolIdsForApi.isNotEmpty ? toolIdsForApi : null,
        filterIds: selectedFilterIds.isNotEmpty ? selectedFilterIds : null,
        enableWebSearch: webSearchEnabled,
        enableImageGeneration: imageGenerationEnabled,
        enableCodeInterpreter: codeInterpreterEnabled,
        modelItem: modelItem,
        sessionIdOverride: socketSessionId,
        toolServers: toolServers,
        backgroundTasks: bgTasks,
        responseMessageId: assistantMessageId,
        userSettings: userSettingsData,
        chatParams: turnSettings.chatParams,
        reasoningEffort: turnSettings.reasoningEffort,
        parentId: parentMsgMap?['parentId']?.toString(),
        userMessage: parentMsgMap,
        variables: promptVars2,
        files: _extractTopLevelRequestFiles(parentMsgMap),
        // Only this one answer is asked for again, in its own column.
        messageIds: comparisonTarget == null
            ? null
            : [
                ChatCompletionTarget(
                  modelId: serverModelId,
                  messageId: assistantMessageId,
                  modelIdx: comparisonTarget.slot,
                ),
              ],
      );
      submittedSession = session;

      // Stop/replacement can race the completion POST itself. The request may
      // now own a remote task, but it must never attach that task to a row the
      // user already stopped or another mutation replaced.
      if (_openWebUiRegenerationPlaceholderOwnerIsActive(
            ref,
            regenerationPlaceholderForAttempt,
          ) &&
          !ownsLiveRegenerationPlaceholder()) {
        await _abortQuietly(session);
        _stopOpenWebUiTaskQuietly(api, session.taskId);
        _clearOpenWebUiRegenerationAttemptMarker(
          ref,
          regenerationPlaceholderForAttempt,
        );
        return;
      }

      regenerationOwner.chatId = await resolveOpenWebUiCompletionChatId(
        ref,
        owner: regenerationOwner,
        assistantMessageId: assistantMessageId,
      );
      final activeOwnerChatId = activeOpenWebUiChatIdForMutation(
        ref,
        regenerationOwner,
      );
      if (activeOwnerChatId == null) {
        DebugLogger.log(
          'regeneration-owner-changed-after-submit',
          scope: 'chat/completion',
          data: {
            'chatId': regenerationOwner.chatId,
            'assistantMessageId': assistantMessageId,
          },
        );
        if (isTemporary) {
          await _abortQuietly(session);
        } else {
          await _finishSubmittedOpenWebUiCompletionHeadlessly(
            ref,
            session: session,
            owner: regenerationOwner,
            assistantMessageId: assistantMessageId,
            // Regeneration is an inline request, not a replayable outbox op.
            requireDurableSubmittedMarker: false,
          );
        }
        return;
      }
      regenerationOwner.chatId = activeOwnerChatId;
      if (!ownsLiveRegenerationPlaceholder()) {
        await _abortQuietly(session);
        _stopOpenWebUiTaskQuietly(api, session.taskId);
        _clearOpenWebUiRegenerationAttemptMarker(
          ref,
          regenerationPlaceholderForAttempt,
        );
        return;
      }

      final modelUsesReasoning = _modelUsesReasoning(selectedModel.id);

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
        activeConversationId: regenerationOwner.chatId,
        api: api!,
        socketService: socketService,
        workerManager: ref.read(workerManagerProvider),
        webSearchEnabled: webSearchEnabled,
        imageGenerationEnabled: imageGenerationEnabled,
        isBackgroundFlow: isBackgroundFlow,
        modelUsesReasoning: modelUsesReasoning,
        toolsEnabled:
            toolIdsForApi.isNotEmpty ||
            (toolServers != null && toolServers.isNotEmpty) ||
            imageGenerationEnabled ||
            codeInterpreterEnabled,
        isTemporary: isTemporary,
        filterIds: selectedFilterIds.isNotEmpty ? selectedFilterIds : null,
        ownsActiveConversation: () =>
            activeOpenWebUiChatIdForMutation(ref, regenerationOwner) != null,
        ownsPendingPlaceholder: ownsLiveRegenerationPlaceholder,
      );
      if (!attached) {
        final ownerIsStillActive =
            activeOpenWebUiChatIdForMutation(ref, regenerationOwner) != null;
        if (ownerIsStillActive && !ownsLiveRegenerationPlaceholder()) {
          await _abortQuietly(session);
          _stopOpenWebUiTaskQuietly(api, session.taskId);
          _clearOpenWebUiRegenerationAttemptMarker(
            ref,
            regenerationPlaceholderForAttempt,
          );
        } else if (isTemporary) {
          await _abortQuietly(session);
        } else {
          await _finishSubmittedOpenWebUiCompletionHeadlessly(
            ref,
            session: session,
            owner: regenerationOwner,
            assistantMessageId: assistantMessageId,
            requireDurableSubmittedMarker: false,
          );
        }
      } else {
        _clearOpenWebUiRegenerationAttemptMarker(
          ref,
          regenerationPlaceholderForAttempt,
        );
      }
    } finally {
      regenSocketService?.stopBuffering(
        bufferedChatId,
        sessionId: socketSessionId,
        messageId: assistantMessageId,
      );
    }
    return;
  } catch (error, stackTrace) {
    final session = submittedSession;
    if (session != null) {
      await _abortQuietly(session);
    }
    _stopOpenWebUiTaskQuietly(api, session?.taskId);
    final placeholder = regenerationPlaceholder;
    if (regenerationPlaceholderWasEstablished &&
        placeholder != null &&
        _openWebUiRegenerationPlaceholderOwnerIsActive(ref, placeholder) &&
        _ownedMarkedOpenWebUiRegenerationPlaceholder(ref, placeholder) ==
            null) {
      // Stop or exact replacement revoked this attempt while an awaited
      // preflight/request was failing. That stale failure has no UI owner and
      // must not escape into the historical rollback path.
      _clearOpenWebUiRegenerationAttemptMarker(ref, placeholder);
      return;
    }
    _settleFailedOpenWebUiRegeneration(
      ref: ref,
      api: api,
      error: error,
      placeholder: regenerationPlaceholder,
      submittedTaskId: session?.taskId,
    );
    Error.throwWithStackTrace(error, stackTrace);
  }
}

const String _openWebUiRegenerationAttemptMetadataKey =
    'conduitOpenWebUiRegenerationAttemptId';

bool _openWebUiRegenerationPlaceholderOwnerIsActive(
  dynamic ref,
  ChatSendPlaceholderHandle placeholder,
) {
  try {
    final active = ref.read(activeConversationProvider) as Conversation?;
    placeholder._followOpenWebUiRemap(
      ref.read(activeConversationInPlaceRemapProvider),
      active,
    );
    return placeholder._owns(ref, active);
  } catch (_) {
    return false;
  }
}

/// Finds the still-streaming row minted by this exact regeneration attempt,
/// regardless of its list position. Failure settlement uses this predicate so
/// a late setup error can mark its own non-tail row without touching a newer
/// assistant.
ChatMessage? _ownedMarkedOpenWebUiRegenerationPlaceholder(
  dynamic ref,
  ChatSendPlaceholderHandle placeholder,
) {
  if (!_openWebUiRegenerationPlaceholderOwnerIsActive(ref, placeholder)) {
    return null;
  }
  final attemptId = placeholder._regenerationAttemptId;
  if (attemptId == null || attemptId.isEmpty) return null;
  try {
    final messages = ref.read(chatMessagesProvider) as List<ChatMessage>;
    return messages
        .where(
          (message) =>
              message.id == placeholder.assistantMessageId &&
              message.role == 'assistant' &&
              message.isStreaming &&
              message.metadata?[_openWebUiRegenerationAttemptMetadataKey] ==
                  attemptId,
        )
        .firstOrNull;
  } catch (_) {
    return null;
  }
}

/// Dispatch callbacks in the shared OpenWebUI transport are tail-based.
/// Therefore transport admission is stricter than failure settlement: the
/// exact marked row must also be the current list tail.
ChatMessage? _tailOwnedOpenWebUiRegenerationPlaceholder(
  dynamic ref,
  ChatSendPlaceholderHandle placeholder,
) {
  final owned = _ownedMarkedOpenWebUiRegenerationPlaceholder(ref, placeholder);
  if (owned == null) return null;
  try {
    final messages = ref.read(chatMessagesProvider) as List<ChatMessage>;
    return identical(messages.lastOrNull, owned) ? owned : null;
  } catch (_) {
    return null;
  }
}

void _clearOpenWebUiRegenerationAttemptMarker(
  dynamic ref,
  ChatSendPlaceholderHandle placeholder,
) {
  final attemptId = placeholder._regenerationAttemptId;
  if (attemptId == null || attemptId.isEmpty) return;
  _clearOpenWebUiRegenerationAttemptMarkerById(
    ref,
    assistantMessageId: placeholder.assistantMessageId,
    attemptId: attemptId,
  );
}

void _clearOpenWebUiRegenerationAttemptMarkerById(
  dynamic ref, {
  required String assistantMessageId,
  required String attemptId,
}) {
  try {
    (ref.read(chatMessagesProvider.notifier) as ChatMessagesNotifier)
        .updateMessageById(assistantMessageId, (message) {
          if (message.metadata?[_openWebUiRegenerationAttemptMetadataKey] !=
              attemptId) {
            return message;
          }
          final metadata = Map<String, dynamic>.from(message.metadata!);
          metadata.remove(_openWebUiRegenerationAttemptMetadataKey);
          return message.copyWith(metadata: metadata.isEmpty ? null : metadata);
        });
  } catch (_) {
    // Attempt metadata is advisory cleanup. Disposal/navigation must not turn
    // a successfully stopped or attached transport into a send failure.
  }
}

/// Settles only the OpenWebUI placeholder minted by one regeneration attempt.
///
/// A later turn may already be streaming in the same conversation when this
/// failure arrives. The owner-bound handle and message id prevent that late
/// failure from stopping, finalizing, or attaching an error to the newer turn.
void _settleFailedOpenWebUiRegeneration({
  required dynamic ref,
  required ApiService? api,
  required Object error,
  required ChatSendPlaceholderHandle? placeholder,
  required String? submittedTaskId,
}) {
  if (placeholder == null) return;
  final ownedAssistant = _ownedMarkedOpenWebUiRegenerationPlaceholder(
    ref,
    placeholder,
  );
  if (ownedAssistant == null) return;

  // Never use the chat-wide task fallback here: a newer generation can be
  // active in this same conversation. Cancel only handles uniquely bound to
  // this assistant/session and leave an unaddressable remote task alone.
  final metadata = ownedAssistant.metadata;
  if (metadata?['transport'] == 'httpStream' ||
      metadata?['hasActiveAbortHandle'] == true) {
    api?.cancelStreamingMessage(ownedAssistant.id);
  }
  final metadataTaskId = metadata?['taskId']?.toString();
  if (metadataTaskId != submittedTaskId) {
    _stopOpenWebUiTaskQuietly(api, metadataTaskId);
  }
  (ref.read(chatMessagesProvider.notifier) as ChatMessagesNotifier)
      .failLastStreamingAssistant(
        error,
        assistantMessageId: placeholder.assistantMessageId,
      );
  _clearOpenWebUiRegenerationAttemptMarker(ref, placeholder);
}

void _stopOpenWebUiTaskQuietly(ApiService? api, String? taskId) {
  if (api == null || taskId == null || taskId.isEmpty) return;
  unawaited(() async {
    try {
      await api.stopTask(taskId);
    } catch (_) {}
  }());
}
