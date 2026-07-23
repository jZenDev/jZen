// The conditional import below is the compile-time platform axis that lets the toolchain
// tree-shake the wrong platform's code out of each bundle (docs/architecture/STANDARDS.md
// "Client config is compile-time").
import 'package:zen_core/zen_core.dart';

import 'zen_codec_selector_stub.dart'
    if (dart.library.html) 'zen_codec_selector_web.dart'
    if (dart.library.io) 'zen_codec_selector_io.dart';
import 'zen_transport_header.dart';

/// Selects the appropriate transport format based on environment and platform.
///
/// The selection logic follows these rules:
/// - In DEV mode: always use JSON
/// - In PRD mode on web: use JSON
/// - In PRD mode on native (mobile/server/desktop): use Protobuf binary
///
/// This function uses compile-time constants (`zenIsDev`) and conditional imports to
/// ensure proper tree-shaking.
ZenTransportFormat selectDefaultCodec() {
  if (zenIsDev) {
    return ZenTransportFormat.json;
  }

  // Platform-specific selection in PRD mode.
  return selectPlatformCodec();
}
