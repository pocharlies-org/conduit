import 'package:flutter/widgets.dart';

import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';

/// Where a [ConduitActionCard] currently stands: a plain card, generating
/// (spinner replaces the actions), done, or failed (subtitle in error color).
enum ConduitCardState { idle, loading, success, error }

/// The app's one card API: a titled surface with an optional leading glyph,
/// subtitle, body and a trailing actions row, plus the loading/success/error
/// header state. Chat cards (file links, image generation) build on this
/// instead of re-drawing the card chrome.
class ConduitActionCard extends StatelessWidget {
  const ConduitActionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.body,
    this.actions,
    this.state = ConduitCardState.idle,
    this.onTap,
    this.onLongPress,
    this.maxWidth,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? body;
  final List<Widget>? actions;
  final ConduitCardState state;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final conduitTheme = context.conduitTheme;
    final actions = this.actions;
    final showActions =
        state != ConduitCardState.loading && actions != null && actions.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Semantics(
        button: onTap != null,
        label: title,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: conduitTheme.cardBackground,
              borderRadius: BorderRadius.circular(AppBorderRadius.md),
              border: Border.all(
                color: conduitTheme.textPrimary.withValues(alpha: 0.12),
                width: BorderWidth.regular,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: Spacing.sm),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelStyle.copyWith(
                              color: conduitTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: AppTypography.labelMediumStyle.copyWith(
                                color: state == ConduitCardState.error
                                    ? conduitTheme.error
                                    : conduitTheme.textSecondary.withValues(
                                        alpha: 0.7,
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    if (state == ConduitCardState.loading)
                      const AdaptiveProgressIndicator.activity(radius: 9)
                    else if (showActions)
                      Wrap(
                        spacing: Spacing.sm,
                        runSpacing: Spacing.xs,
                        children: actions,
                      ),
                  ],
                ),
                if (body != null) ...[
                  const SizedBox(height: Spacing.sm),
                  body!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
