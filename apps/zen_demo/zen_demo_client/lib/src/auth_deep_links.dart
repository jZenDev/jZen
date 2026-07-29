import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'auth_deep_links_stub.dart' if (dart.library.io) 'auth_deep_links_native.dart';

/// Delivers auth links the operating system hands this app to the framework's session store.
///
/// Deep-link *registration* is per-platform and per-application — a scheme in a plist and a
/// manifest, and a plugin to read it — so it lives here, in the app, not in the framework
/// (ADR-019). What the framework provides is the other side of the handover:
/// `IdentitySessionStore.consumeAuthLink(uri)` takes a plain [Uri] and does not care how it
/// arrived.
///
/// On the web this is a no-op, by conditional import: there the link *is* how the app was opened,
/// and the session store has already consumed it from `Uri.base` before the first frame. A second
/// consumer would race the first and try to spend the same token twice — so the web build does not
/// compile the plugin in at all.
class AuthDeepLinks extends ConsumerStatefulWidget {
  /// The app below this listener.
  final Widget child;

  const AuthDeepLinks({required this.child, super.key});

  @override
  ConsumerState<AuthDeepLinks> createState() => _AuthDeepLinksState();
}

class _AuthDeepLinksState extends ConsumerState<AuthDeepLinks> {
  Future<void> Function()? _cancel;

  @override
  void initState() {
    super.initState();
    // Both arrival shapes go to the same place. The distinction that matters is upstream of here:
    // a cold start (the tap launched the app) is invisible to the session store, because off the
    // web `Uri.base` is a file path, not the link — so the initial link must be fetched and
    // replayed, which subscribeToAuthLinks does before it starts streaming.
    _cancel = subscribeToAuthLinks((uri) {
      if (!mounted) return;
      ref.read(identitySessionStoreProvider.notifier).consumeAuthLink(uri);
    });
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
