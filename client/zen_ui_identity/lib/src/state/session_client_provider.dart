import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_transport/zen_transport.dart';

/// The session-bearing HTTP client, so the identity store can resume a persisted session.
///
/// Optional, and null by default, because resuming is a native concern: a browser reattaches its
/// own cookies and needs nothing here. An app that wants a session to survive being closed
/// overrides this with the same client it gave the repository — the same one, not another, or
/// the restored cookie would land in a jar nobody sends from.
///
/// Kept apart from `identityRepositoryProvider` because the two answer different questions: the
/// repository is *what calls the API*, this is *where the session physically lives*.
final sessionClientProvider = Provider<ZenSessionClient?>((ref) => null);
