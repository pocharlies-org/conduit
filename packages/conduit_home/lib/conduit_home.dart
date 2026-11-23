/// The home build's login: the edani Keycloak sheet, its native bridge, its
/// token renewal and the accounts it ships seeded with (OWU-157).
///
/// A generic conduit build simply does not depend on this package: the core's
/// `signInFlowProvider` and `sessionRenewalProvider` default to «no flow».
library;

export 'pkce_sign_in.dart' show runPkceSignIn, authorizationCodeFromCallback;
export 'owui_oidc.dart' show OwuiOidc, OidcTokens, homeOwuiConfig;
export 'renewal.dart' show renewHomeSession;
export 'seed.dart' show installHomeSeed;
export 'system_browser_auth.dart';
