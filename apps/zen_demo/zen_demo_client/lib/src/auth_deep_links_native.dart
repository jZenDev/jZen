import 'dart:async';

import 'package:app_links/app_links.dart';

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
Future<void> Function() subscribeToAuthLinks(void Function(Uri uri) onLink) {
  final appLinks = AppLinks();
  StreamSubscription<Uri>? subscription;
  var cancelled = false;

  unawaited(
    appLinks.getInitialLink().then((uri) {
      // A cancel that lands while this future is in flight must win: the widget is gone and
      // handing it a link would drive a disposed subscriber.
      if (cancelled) return;
      if (uri != null) onLink(uri);
      subscription = appLinks.uriLinkStream.listen(onLink);
    }),
  );

  return () async {
    cancelled = true;
    await subscription?.cancel();
  };
}
