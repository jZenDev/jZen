import 'package:flutter/widgets.dart';
import 'package:zen_core/zen_core.dart';

import 'src/core/demo_local_boot.dart';
import 'src/demo_local_app.dart';
import 'src/start_failed_app.dart';

/// jZen Local: no server, no sign-in. The app opens its own encrypted store and syncs it through
/// the transport its build names (ADR-073).
Future<void> main() async {
  // Plugins (the keystore, the data directory) are reached over platform channels.
  WidgetsFlutterBinding.ensureInitialized();
  switch (await bootDemoLocal()) {
    case ZenSuccess(:final data):
      runApp(DemoLocalApp(session: data.session, lock: data.lock));
    case ZenFailure(:final error):
      runApp(StartFailedApp(error: error));
  }
}
