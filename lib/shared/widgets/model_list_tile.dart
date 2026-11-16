import 'dart:io' show Platform;

import 'package:conduit/l10n/app_localizations.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:conduit/core/services/haptic_service.dart';

import 'package:conduit_core/models/model.dart';

import '../theme/theme_extensions.dart';
import 'model_avatar.dart';
import 'horizontal_gesture_ownership.dart';
import 'horizontal_overflow_fade.dart';

/// Whether a [Model] supports reasoning based on its parameters.
bool modelSupportsReasoning(Model model) {
  final params = model.supportedParameters ?? const [];
  if (params.any((p) => p.toLowerCase().contains('reasoning'))) return true;
  if (model.capabilities?['thinking'] == true) return true;
  final native = model.capabilities?['capabilities'];
  return native is Iterable &&
      native.any((value) => value.toString().toLowerCase() == 'thinking');
}

/// Small chip that displays a model capability (e.g. multimodal, reasoning).
class ModelCapabilityChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const ModelCapabilityChip({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    return Container(
      margin: const EdgeInsets.only(right: Spacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: theme.buttonPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppBorderRadius.chip),
        border: Border.all(
          color: theme.buttonPrimary.withValues(alpha: 0.3),
          width: BorderWidth.thin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.buttonPrimary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmallStyle.copyWith(
              color: theme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small text label for OpenWebUI model tags.
class ModelTagChip extends StatelessWidget {
  final String label;

  const ModelTagChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    return Container(
      margin: const EdgeInsets.only(right: Spacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: theme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppBorderRadius.chip),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.7),
          width: BorderWidth.thin,
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelSmallStyle.copyWith(
          color: theme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Compact list tile for model selection, styled like the sidebar
/// conversation tiles — no card borders, rounded active highlight.
class ModelListTile extends StatelessWidget {
  final Model model;
  final bool isSelected;
  final VoidCallback onTap;

  /// The URL of the model icon (resolved via [resolveModelIconUrlForModel]).
  final String? iconUrl;

  /// Whether this tile represents the "auto-select" option.
  final bool isAutoSelect;

  /// Whether this model is pinned in model selectors.
  final bool isPinned;

  const ModelListTile({
    super.key,
    required this.model,
    required this.isSelected,
    required this.onTap,
    this.iconUrl,
    this.isAutoSelect = false,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    final borderRadius = BorderRadius.circular(AppBorderRadius.card);

    // Selection is carried by the trailing checkmark, as in the native iOS
    // picker; rows themselves stay unfilled.
    const background = Colors.transparent;

    final Widget leading;
    if (isAutoSelect) {
      leading = SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          Platform.isIOS ? CupertinoIcons.wand_stars : Icons.auto_awesome,
          color: theme.textPrimary,
          size: IconSize.medium,
        ),
      );
    } else {
      leading = ModelAvatar(size: 32, imageUrl: iconUrl, label: model.name);
    }

    final hasCapabilities =
        !isAutoSelect && (model.isMultimodal || modelSupportsReasoning(model));
    final modelTagsByLowercase = <String, String>{};
    if (!isAutoSelect) {
      for (final tag in model.modelTags) {
        modelTagsByLowercase.putIfAbsent(tag.toLowerCase(), () => tag);
      }
    }
    final modelTags = modelTagsByLowercase.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final hasTags = modelTags.isNotEmpty;
    final hasMetadataRow = hasCapabilities || hasTags;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ConduitHaptics.selectionClick();
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: borderRadius,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isAutoSelect ? l10n.autoSelect : model.name,
                      style: AppTypography.bodyLargeStyle.copyWith(
                        fontSize: 16,
                        height: 1.35,
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isAutoSelect) ...[
                      const SizedBox(height: 2),
                      Text(
                        l10n.autoSelectDescription,
                        style: AppTypography.labelSmallStyle.copyWith(
                          color: theme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (hasMetadataRow) ...[
                      const SizedBox(height: 2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 22),
                        child: HorizontalOverflowFade(
                          child: HorizontalScrollGestureBoundary(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              child: Row(
                                children: [
                                  for (final tag in modelTags)
                                    ModelTagChip(label: tag),
                                  if (model.isMultimodal)
                                    ModelCapabilityChip(
                                      icon: Platform.isIOS
                                          ? CupertinoIcons.photo
                                          : Icons.image,
                                      label: l10n.modelCapabilityMultimodal,
                                    ),
                                  if (modelSupportsReasoning(model))
                                    ModelCapabilityChip(
                                      icon: Platform.isIOS
                                          ? CupertinoIcons.lightbulb
                                          : Icons.psychology_alt,
                                      label: l10n.modelCapabilityReasoning,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isPinned && !isAutoSelect) ...[
                const SizedBox(width: Spacing.xs),
                Icon(
                  Platform.isIOS
                      ? CupertinoIcons.pin_fill
                      : Icons.push_pin_rounded,
                  color: theme.textSecondary,
                  size: IconSize.small,
                ),
              ],
              if (isSelected) ...[
                const SizedBox(width: Spacing.xs),
                Icon(
                  Platform.isIOS ? CupertinoIcons.check_mark : Icons.check,
                  color: theme.buttonPrimary,
                  size: IconSize.medium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
