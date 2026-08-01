import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_identity/zen_identity.dart';

/// The outcome of an auth link that arrived while the app was **already running**, waiting to be
/// shown to the user. Null when there is nothing to report.
///
/// The startup path does not need this: a link the app was *opened* with is consumed before the
/// first frame, and the login screen reads the result as it builds. A link that arrives later has
/// no such moment. The user is wherever they happened to be, no screen is being built, and before
/// this the outcome went nowhere at all — a refused link silently did nothing, which is the worst
/// possible answer to "I tapped the link in my email". The whole point of the flow is that
/// tapping the link visibly does something.
///
/// Only outcomes worth interrupting someone for are published: a refusal, and a confirmation that
/// still needs a manual sign-in. A link that signs the user in reports itself by signing them in.
class AuthLinkOutcome extends Notifier<ZenAuthLink?> {
  @override
  ZenAuthLink? build() => null;

  /// Publishes [link] for display, if it is something the user needs told.
  void report(ZenAuthLink link) {
    switch (link.kind) {
      case ZenAuthLinkKind.failed:
      case ZenAuthLinkKind.confirmedWithoutSession:
        state = link;
      case ZenAuthLinkKind.none:
      case ZenAuthLinkKind.session:
      case ZenAuthLinkKind.recovery:
        // `none` is any other deep link the app handles and is not this feature's business;
        // the two success kinds are self-evident, because the app changes in front of the user.
        break;
    }
  }

  /// Marks the outcome as shown. Without this a rebuild would repeat the message.
  void clear() => state = null;
}

/// The pending outcome of a warm auth link. Watched by [ZenAuthLinkListener].
final authLinkOutcomeProvider =
    NotifierProvider<AuthLinkOutcome, ZenAuthLink?>(AuthLinkOutcome.new);
