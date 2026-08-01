import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_identity/zen_identity.dart';

import '../l10n/generated/identity_localizations.dart';
import '../state/auth_link_outcome.dart';

/// Tells the user what happened to an auth link that arrived while the app was already running.
///
/// Place it **inside** `MaterialApp` (wrapping `home`, or via `builder`), because it needs the
/// `ScaffoldMessenger` and the `Localizations` that `MaterialApp` provides. That is the opposite
/// of the app's deep-link *receiver*, which sits above `MaterialApp` so it outlives every screen —
/// the two are deliberately at different heights: one must survive navigation, the other must be
/// able to reach the current scaffold.
///
/// Without this, a refused link while the app is open does nothing whatsoever: the session store
/// declines to sign anyone out (a stale link must not evict whoever is using the app now), so
/// there is no state change for any screen to notice, and the user is left believing their tap
/// was ignored. The login screen's own message only ever covered the *startup* case.
///
/// It is a widget in the framework rather than a snippet each application writes, for the reason
/// auth is framework-side generally: the wording is already translated here, and an application
/// that forgot to write it would not see anything missing — it would just be silent.
class ZenAuthLinkListener extends ConsumerWidget {
  /// The app below this listener.
  final Widget child;

  const ZenAuthLinkListener({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ZenAuthLink?>(authLinkOutcomeProvider, (previous, next) {
      if (next == null) return;

      final messages = IdentityLocalizations.of(context);
      final String text = switch (next.kind) {
        ZenAuthLinkKind.confirmedWithoutSession => messages.emailConfirmedBanner,
        // Everything else published here is a refusal; `failed` is the only other kind
        // AuthLinkOutcome lets through.
        _ => messages.linkExpiredBanner,
      };

      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));

      // Cleared immediately: the message is on screen, and leaving the outcome set would show it
      // again on the next rebuild. Done after the listener runs, so it does not modify a provider
      // during the notification that is still being delivered.
      Future.microtask(() => ref.read(authLinkOutcomeProvider.notifier).clear());
    });

    return child;
  }
}
