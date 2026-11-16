import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/openwebui_accounts_controller.dart';
import 'package:conduit_core/utils/debug_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit/shared/widgets/platform_ui/vocabulary.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/widgets/utility_components.dart';
import '../../../core/utils/account_display.dart';

export '../../../core/utils/account_display.dart';

/// The avatar of an account the app is not signed in to: the image saved the
/// last time it was active when that image travels with it (a data URL, as
/// Open WebUI stores uploaded pictures), else its initial.
class SavedAccountAvatar extends StatelessWidget {
  const SavedAccountAvatar({
    super.key,
    required this.entry,
    required this.size,
  });

  final OpenWebUiAccountEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final image = entry.summary.profileImage;
    final characters = accountDisplayName(entry, l10n).characters;
    return UserAvatar(
      size: size,
      imageUrl: image != null && image.startsWith('data:image') ? image : null,
      fallbackText: characters.isEmpty ? 'U' : characters.first.toUpperCase(),
    );
  }
}

/// A saved Open WebUI account as a row under its server: its avatar, who it
/// is, and a check when it is the active one. Tapping switches to it; a long
/// press signs out of it. [showSignOut] adds a sign-out button as well, for
/// the server's own page.
class SavedAccountRow extends ConsumerWidget {
  const SavedAccountRow({
    super.key,
    required this.entry,
    this.showSignOut = false,
  });

  final OpenWebUiAccountEntry entry;
  final bool showSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = context.conduitTheme;
    final name = accountDisplayName(entry, l10n);
    void signOut() => signOutOfSavedAccount(context, ref, entry);
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.accountsSignOutOf(name)): signOut,
      },
      child: GestureDetector(
        onLongPress: signOut,
        child: UtilityRow(
          title: name,
          subtitle: accountSubtitle(entry, l10n),
          leading: SavedAccountAvatar(entry: entry, size: IconSize.xl),
          selected: entry.isActive,
          preserveTrailingSemantics: true,
          // The active account signed out -- its session expired -- is
          // switched to as any other, which opens its sign-in.
          onTap: entry.isActive && entry.hasSession
              ? null
              : () => switchToSavedAccount(context, ref, entry.id),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.isActive)
                ActiveCheckmark(semanticLabel: l10n.accountsActive),
              if (showSignOut)
                AdaptiveButton.icon(
                  key: Key('accounts-sign-out-${entry.id}'),
                  semanticLabel: l10n.accountsSignOutOf(name),
                  icon: UiUtils.platformIcon(
                    ios: CupertinoIcons.square_arrow_left,
                    android: Icons.logout,
                  ),
                  iconColor: theme.error,
                  style: AdaptiveButtonStyle.plain,
                  // A row of a scrolling list: no native view per row.
                  useNative: false,
                  onPressed: signOut,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The check that marks the account in use.
class ActiveCheckmark extends StatelessWidget {
  const ActiveCheckmark({super.key, required this.semanticLabel});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Icon(
        UiUtils.platformIcon(
          ios: CupertinoIcons.checkmark_alt,
          android: Icons.check,
        ),
        color: context.conduitTheme.buttonPrimary,
        size: IconSize.medium,
      ),
    );
  }
}

/// Signs out of every account. OWU-134: the seeded Chat server stays as the
/// app's configuration, so the next boot lands on its sign-in.
Future<void> signOutOfAllAccounts(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(signOutCoordinatorProvider).signOut();
  } catch (_) {
    if (!context.mounted) return;
    UiUtils.showMessage(context, AppLocalizations.of(context)!.errorMessage);
  }
}

/// Makes [accountId] the active account, asking first when that would stop
/// a reply that is still being written, and opens its sign-in when it needs
/// one.
Future<void> switchToSavedAccount(
  BuildContext context,
  WidgetRef ref,
  String accountId,
) async {
  final l10n = AppLocalizations.of(context)!;
  // The page this began on may not outlast the switch.
  final router = GoRouter.of(context);
  final controller = ref.read(openWebUiAccountsControllerProvider);
  try {
    var result = await controller.switchTo(accountId);
    if (result == OpenWebUiAccountChangeResult.blockedByActiveReply) {
      if (!context.mounted) return;
      if (!await _confirmSwitchStopsReply(context)) return;
      result = await controller.switchTo(accountId, force: true);
    }
    if (result == OpenWebUiAccountChangeResult.needsSignIn) {
      _openSignIn(router);
    }
  } catch (error, stackTrace) {
    DebugLogger.error(
      'account-switch-failed',
      scope: 'profile/accounts',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) UiUtils.showMessage(context, l10n.errorMessage);
  }
}

/// Whether the active account may be left for one being signed in to: at
/// once when no reply is being written, else once the user agrees to stop
/// it, which this then does.
///
/// Signing in to an added account makes it the active one before the
/// accounts controller is involved, so this asks what [switchToSavedAccount]
/// asks when the controller reports a reply in the way.
Future<bool> confirmLeavingActiveAccount(BuildContext context, WidgetRef ref) =>
    _mayStopReply(
      context,
      ref.read,
      guard: accountChangeReplyGuardProvider,
      stop: accountChangeStopRepliesProvider,
      confirm: () => _confirmSwitchStopsReply(context),
    );

Future<bool> _mayStopReply(
  BuildContext context,
  T Function<T>(ProviderListenable<T> provider) read, {
  required ProviderListenable<bool Function()> guard,
  required ProviderListenable<void Function()> stop,
  required Future<bool> Function() confirm,
}) async {
  if (!read(guard)()) return true;
  if (!await confirm() || !context.mounted) return false;
  try {
    read(stop)();
  } catch (error, stackTrace) {
    DebugLogger.error(
      'account-change-stop-replies-failed',
      scope: 'auth/accounts',
      error: error,
      stackTrace: stackTrace,
    );
  }
  return true;
}

/// Opens sign-in for the active account, which a switch or a sign-out left
/// signed out. Sign-in becomes the router's location, so the router moves on
/// to chat once it succeeds.
void _openSignIn(GoRouter router) => router.go(Routes.authentication);

/// Drops the added account whose sign-in never finished, which makes the
/// account it was added from active again, and returns to chat.
///
/// When it could not be dropped and is still there, signed out, the flow
/// stays open, with its Cancel: in chat, the router would only open that
/// account's sign-in again, without one. Returns false then, for the page to
/// say so.
Future<bool> abandonAddedAccount(BuildContext context, WidgetRef ref) async {
  var left = false;
  try {
    left = await ref
        .read(openWebUiAccountsControllerProvider)
        .abandonPendingSignIn();
  } catch (error, stackTrace) {
    DebugLogger.error(
      'abandon-added-account-failed',
      scope: 'auth/accounts',
      error: error,
      stackTrace: stackTrace,
    );
  }
  if (!context.mounted) return true;
  if (!left) {
    // Not dropped because a sign-in reached it is not still pending; read
    // again, not as last shown. Unreadable, it may be: stay.
    final stillPending = await ref
        .read(pendingSignInAbandonableProvider.future)
        .then((pending) => pending, onError: (Object _) => true);
    if (!context.mounted) return true;
    if (stillPending) return false;
  }
  context.go(Routes.chat);
  return true;
}

Future<bool> _confirmSwitchStopsReply(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return ThemedDialogs.confirm(
    context,
    title: l10n.accountsReplyInProgressTitle,
    message: l10n.accountsSwitchStopsReply,
    confirmText: l10n.accountsSwitchAnyway,
    isDestructive: true,
  );
}

/// Signs out of [entry] after confirming, and again when that would stop a
/// reply that is still being written. When the account that takes over
/// needs a sign-in, opens it.
Future<void> signOutOfSavedAccount(
  BuildContext context,
  WidgetRef ref,
  OpenWebUiAccountEntry entry,
) async {
  final l10n = AppLocalizations.of(context)!;
  final name = accountDisplayName(entry, l10n);
  final confirmed = await ThemedDialogs.confirm(
    context,
    title: l10n.accountsSignOutConfirmTitle(name),
    message: l10n.accountsSignOutConfirmMessage,
    confirmText: l10n.signOut,
    isDestructive: true,
  );
  if (!confirmed || !context.mounted) return;
  // The row this began on goes with the account it showed.
  final router = GoRouter.of(context);
  final controller = ref.read(openWebUiAccountsControllerProvider);
  try {
    var result = await controller.signOut(entry.id);
    if (result == OpenWebUiAccountChangeResult.blockedByActiveReply) {
      if (!context.mounted) return;
      final stopReply = await ThemedDialogs.confirm(
        context,
        title: l10n.accountsReplyInProgressTitle,
        message: l10n.accountsSignOutStopsReply,
        confirmText: l10n.accountsSignOutAnyway,
        isDestructive: true,
      );
      if (!stopReply) return;
      result = await controller.signOut(entry.id, force: true);
    }
    // OWU-134: sign-in is the only destination a signed-out session has,
    // whether another account takes over or the last one left.
    if (result == OpenWebUiAccountChangeResult.needsSignIn) {
      _openSignIn(router);
    }
  } catch (error, stackTrace) {
    DebugLogger.error(
      'account-sign-out-failed',
      scope: 'profile/accounts',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) UiUtils.showMessage(context, l10n.errorMessage);
  }
}
