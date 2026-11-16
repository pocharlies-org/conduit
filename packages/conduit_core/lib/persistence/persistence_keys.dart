/// Keys previously stored in SharedPreferences. Centralized so Hive-based
/// storage and migration logic stay aligned.
final class PreferenceKeys {
  static const String reduceMotion = 'reduce_motion';
  static const String animationSpeed = 'animation_speed';
  static const String disableHapticsWhileStreaming =
      'disable_haptics_while_streaming';
  static const String citationShowTitles = 'citation_show_titles';
  static const String highContrast = 'high_contrast';
  static const String darkMode = 'dark_mode';
  static const String defaultModel = 'default_model';
  static const String openRouterImageGenerationModel =
      'openrouter_image_generation_model_v1';
  static const String voiceLocaleId = 'voice_locale_id';
  static const String voiceHoldToTalk = 'voice_hold_to_talk';
  static const String voiceAutoSendFinal = 'voice_auto_send_final';
  static const String voiceBargeInEnabled = 'voice_barge_in_enabled';
  static const String voiceCallMode = 'voice_call_mode';
  static const String voiceSttPreference = 'voice_stt_preference';
  static const String voiceSttLanguageCode = 'voice_stt_language_code';
  static const String socketTransportMode = 'socket_transport_mode';
  static const String quickPills = 'quick_pills';
  static const String chatWebSearchEnabled = 'chat_web_search_enabled';
  static const String chatImageGenerationEnabled =
      'chat_image_generation_enabled';
  static const String sendOnEnterKey = 'send_on_enter';
  /// Holds the active Open WebUI *account* id. The key predates accounts:
  /// an account's id is the id its server config always had.
  static const String activeServerId = 'active_server_id';

  /// Non-secret display details of saved Open WebUI accounts (name, email,
  /// avatar, last use), so the account list renders without Keychain reads.
  static const String openWebUiAccountSummaries =
      'openwebui_account_summaries_v1';

  /// Set once the device-wide model and chat defaults were copied into the
  /// account that was active when per-account settings arrived.
  static const String accountScopedSettingsMigrated =
      'account_scoped_settings_migrated_v1';

  /// Which route each saved Open WebUI server was last reached through.
  static const String openWebUiEndpointHint = 'openwebui_endpoint_hint_v1';

  /// Fail-closed marker set before logout touches any remote or local state.
  /// It prevents bearer/credential restoration and proxy-cookie attachment
  /// after a process death or incomplete secure-storage cleanup.
  static const String incompleteLogoutFence = 'incomplete_logout_fence_v1';

  /// Set when a full sign-out could not delete every Open WebUI account
  /// database. The next start deletes them before any can open.
  static const String pendingAccountDatabaseWipe =
      'pending_account_database_wipe_v1';

  /// Accounts signed out of whose data could not all be removed. The next
  /// start finishes removing what each left.
  static const String pendingAccountPurges = 'pending_account_purges_v1';

  /// Accounts still saved -- signed out of by the plain logout -- whose chats
  /// are being deleted or could not all be. Until they are gone, an owner
  /// marker of theirs certifies nothing, and the next start retries.
  static const String pendingAccountDataPurges =
      'pending_account_data_purges_v1';
  static const String appIntentInvocationLedger =
      'app_intent_invocation_ledger_v1';
  static const String themeMode = 'theme_mode';
  static const String themePalette = 'theme_palette_v1';
  static const String localeCode = 'locale_code_v1';
  static const String reviewerMode = 'reviewer_mode_v1';
  static const String lastSeenReleaseVersion = 'last_seen_release_version_v1';
  static const String releaseNotesExistingInstallAtBootstrap =
      'release_notes_existing_install_at_bootstrap_v1';
  static const String releaseNotesBannerPreviousVersion =
      'release_notes_banner_previous_version_v1';
  static const String serverVersionWarningDismissed =
      'server_version_warning_dismissed_v1';
  static const String ttsVoice = 'tts_voice';
  static const String ttsVoiceName = 'tts_voice_name';
  static const String ttsSpeechRate = 'tts_speech_rate';
  static const String ttsPitch = 'tts_pitch';
  static const String ttsVolume = 'tts_volume';
  static const String ttsEngine = 'tts_engine'; // 'device' | 'server'
  static const String ttsServerVoiceId = 'tts_server_voice_id';
  static const String ttsServerVoiceName = 'tts_server_voice_name';
  static const String voiceSilenceDuration = 'voice_silence_duration';
  static const String androidAssistantTrigger = 'android_assistant_trigger';
  static const String temporaryChatByDefault = 'temporary_chat_by_default';

  /// Device-local disclosure switch for additional chat tools and settings.
  static const String advancedFeaturesEnabled = 'advanced_features_enabled_v1';
  static const String pinnedModels = 'pinned_models';

  // Notifications. The first three mirror Open WebUI's user-settings fields and
  // are synced to the server; the rest are Conduit-only client preferences.
  static const String notificationsEnabled = 'notifications_enabled';
  static const String notificationSound = 'notification_sound';
  static const String notificationSoundAlways = 'notification_sound_always';
  static const String notificationInAppBanner = 'notification_in_app_banner';
  static const String notificationSystem = 'notification_system';
  static const String notificationChatEnabled = 'notification_chat_enabled';
  static const String notificationChannelEnabled =
      'notification_channel_enabled';

  static const String reasoningEffortByModel = 'reasoning_effort_by_model_v1';

  /// Prefix for the per-server account owner marker that guards reopening an
  /// OpenWebUI database after process restart.
  static const String openWebUiAccountOwnerPrefix =
      'openwebui_account_owner_v1';

  // Drawer section collapsed states
  static const String drawerShowPinned = 'drawer_show_pinned';
  static const String drawerShowFolders = 'drawer_show_folders';
  static const String drawerShowRecent = 'drawer_show_recent';

  /// Notes sidebar tab section visibility (separate from [drawerShowPinned] /
  /// [drawerShowRecent]).
  static const String notesListShowPinned = 'notes_list_show_pinned';
  static const String notesListShowRecent = 'notes_list_show_recent';

  static const String sidebarActiveTab = 'sidebar_active_tab';
  static const String sidebarTabletWidth = 'sidebar_tablet_width_v1';
  static const String serverFeatureAvailability =
      'server_feature_availability_v1';

  /// One-time gate for the Hive `preferences_v1` → shared_preferences migration
  /// (PR-1 of the Hive removal). Set last, after every key is copied.
  static const String hiveToPrefsMigrationV1 = 'hive_to_prefs_migration_v1';

  /// Prefix for the per-server transport-options cache moved out of the Hive
  /// `caches` box (it needs a synchronous read). Combined with a safe-encoded
  /// server id: `transport_options:<safeServerId>`.
  static const String transportOptionsPrefix = 'transport_options';
}

final class LegacyPreferenceKeys {
  static const String attachmentUploadQueue = 'attachment_upload_queue';
  static const String taskQueue = 'outbound_task_queue_v1';
}
