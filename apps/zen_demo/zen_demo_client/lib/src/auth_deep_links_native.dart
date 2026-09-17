import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:meta/meta.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';

/// Native (iOS, Android, macOS): subscribe to the URLs the operating system delivers.
///
/// Two arrival shapes, and both must be handled or the feature only half works:
///
///  * **cold** — the tap launched the app. The URL is waiting as the initial link, and nothing
///    else will ever deliver it. This is the one that gets forgotten, and the symptom is "deep
///    links only work when the app is already open".
///  * **warm** — the app was running and the OS handed it a URL, which arrives on the stream.
///
/// The initial link is replayed first, then the stream is attached. `getInitialLink` keeps
/// returning the same launch URL for the process's lifetime, so it is read exactly once here
/// rather than on every rebuild; spending a token twice would make the second attempt look like a
/// spent link.

/// The App Link path Android's `https` intent filter registers (`AndroidManifest.xml`,
/// `pathPrefix="/auth/callback"`). Its host is a per-environment build placeholder
/// (`ZEN_APPLINKS_HOST`) that never reaches the Dart layer, so this is the only part of that
/// filter a compile-time check can name; domain ownership is what Android's own asset-links
/// verification gates before the OS ever routes the intent here.
const String _appLinkPath = '/auth/callback';

/// Whether [uri] matches one of this app's own registered deep-link filters — the custom
/// scheme in [redirectUri] (`AndroidManifest.xml`'s scheme filter, iOS/macOS
/// `CFBundleURLSchemes`; defaults to the build's [zenAuthRedirectUri]) or the `https` App Link
/// path. An exported Android activity accepts an explicit intent from any installed app
/// regardless of its declared `<data>` filters, so this check — not the manifest — is what
/// keeps an unrelated URI from reaching [subscribeToAuthLinks]'s `onLink`.
@visibleForTesting
bool isRegisteredAuthLink(Uri uri, {String redirectUri = zenAuthRedirectUri}) {
  final expected = redirectUri.isEmpty ? null : Uri.tryParse(redirectUri);
  if (expected != null && uri.scheme == expected.scheme && uri.host == expected.host) {
    return true;
  }
  return uri.scheme == 'https' && uri.path.startsWith(_appLinkPath);
}

Future<void> Function() subscribeToAuthLinks(void Function(Uri uri) onLink) {
  final appLinks = AppLinks();
  StreamSubscription<Uri>? subscription;
  var cancelled = false;

  void deliver(Uri uri) {
    if (!isRegisteredAuthLink(uri)) {
      // A rejected URI is either noise (some other app's link reaching this process) or a
      // legitimate new deep-link path this filter hasn't learned about yet, and the latter must
      // leave a trace rather than vanish silently during development.
      ZenLogger.instance.debug('auth_deep_links_native: rejected untrusted URI', internalData: {
        'uri': uri.toString(),
      });
      return;
    }
    onLink(uri);
  }

  unawaited(
    appLinks.getInitialLink().then((uri) {
      // A cancel that lands while this future is in flight must win: the widget is gone and
      // handing it a link would drive a disposed subscriber.
      if (cancelled) return;
      if (uri != null) deliver(uri);
      subscription = appLinks.uriLinkStream.listen(deliver);
    }),
  );

  return () async {
    cancelled = true;
    await subscription?.cancel();
  };
}
