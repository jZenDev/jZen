import 'dart:async';

import 'package:flutter/foundation.dart';

// The activation exists only while the button's callback runs synchronously. An async callback
// inherits its zone, so the flag prevents a later, unrelated detail from claiming the button.
final Object _activationKey = Object();

class _Activation {
  _Activation(this.activate);
  final VoidCallback Function() activate;
  bool running = true;
}

void runDetailButtonCallback(VoidCallback callback, VoidCallback Function() activate) {
  final activation = _Activation(activate);
  try {
    runZoned(callback, zoneValues: <Object, Object>{_activationKey: activation});
  } finally {
    activation.running = false;
  }
}

VoidCallback? activateDetailButton() {
  final activation = Zone.current[_activationKey] as _Activation?;
  return activation != null && activation.running ? activation.activate() : null;
}
