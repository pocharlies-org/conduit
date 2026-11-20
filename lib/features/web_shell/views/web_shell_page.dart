import 'dart:async';

import 'package:conduit_core/auth/auth_state_manager.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/platform/webview_cookie_helper.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit/shared/widgets/platform_ui/vocabulary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether `candidate` stays inside the instance served at `base`.
bool webShellIsInternal(String candidate, String base) {
  final host = Uri.tryParse(candidate)?.host;
  return host != null && host.isNotEmpty && host == Uri.tryParse(base)?.host;
}

/// The real Open WebUI web inside the app: it loads the current server with
/// the app's own session (the `token` cookie carries the native JWT), so
/// everything the web does works without a native port. Links to another host
/// leave through the system browser instead of stranding the app.
class WebShellPage extends ConsumerStatefulWidget {
  const WebShellPage({super.key});

  @override
  ConsumerState<WebShellPage> createState() => _WebShellPageState();
}

class _WebShellPageState extends ConsumerState<WebShellPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final baseUrl = ref.watch(apiServiceProvider)?.baseUrl;
    final token = ref.watch(authStateManagerProvider).asData?.value.token;
    final ready =
        isWebViewSupported &&
        baseUrl != null &&
        token != null &&
        token.isNotEmpty;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: l10n.webShellTitle,
        leading: ConduitIconButton(
          icon: CupertinoIcons.back,
          tooltip: l10n.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: !ready
          ? ConduitEmptyState(
              icon: CupertinoIcons.globe,
              title: l10n.webShellNoServer,
              message: '',
              isCompact: true,
            )
          : _WebShellWebView(baseUrl: baseUrl, token: token),
    );
  }
}

class _WebShellWebView extends StatefulWidget {
  const _WebShellWebView({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  @override
  State<_WebShellWebView> createState() => _WebShellWebViewState();
}

class _WebShellWebViewState extends State<_WebShellWebView> {
  // shortcut: the session cookie is written when the shell opens; a JWT that
  // rotates while the shell stays open is picked up on the next open.
  Future<void> _prepareAndLoad(InAppWebViewController controller) async {
    await CookieManager().setCookie(
      url: WebUri(widget.baseUrl),
      name: 'token',
      value: widget.token,
      path: '/',
    );
    if (!mounted) return;
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.baseUrl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      onWebViewCreated: (controller) {
        unawaited(_prepareAndLoad(controller));
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url;
        if (url == null) return NavigationActionPolicy.ALLOW;
        if (webShellIsInternal(url.toString(), widget.baseUrl)) {
          return NavigationActionPolicy.ALLOW;
        }
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
        return NavigationActionPolicy.CANCEL;
      },
    );
  }
}
