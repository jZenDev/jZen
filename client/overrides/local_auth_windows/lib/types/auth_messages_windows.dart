import 'package:flutter/foundation.dart';
import 'package:local_auth_platform_interface/types/auth_messages.dart';

/// Windows side authentication messages, the type `local_auth` names in its default messages.
///
/// Same shape as pub.dev's `local_auth_windows`, which is unused there too.
@immutable
class WindowsAuthMessages extends AuthMessages {
  /// Constructs a new instance.
  const WindowsAuthMessages();

  @override
  Map<String, String> get args => <String, String>{};
}
