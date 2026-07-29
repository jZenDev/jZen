/// Web (and any target without `dart:io`): there is nothing to subscribe to.
///
/// A browser does not hand a running page a URL — it navigates, and the session store has already
/// read the link out of `Uri.base` before the first frame. Returning a no-op cancel keeps the
/// caller identical on both sides, and keeps the deep-link plugin out of the web bundle entirely.
Future<void> Function() subscribeToAuthLinks(void Function(Uri uri) onLink) => () async {};
