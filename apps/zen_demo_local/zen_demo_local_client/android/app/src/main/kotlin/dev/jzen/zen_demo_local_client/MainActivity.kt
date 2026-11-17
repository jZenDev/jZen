package dev.jzen.zen_demo_local_client

import io.flutter.embedding.android.FlutterFragmentActivity

// `local_auth` (the owner check behind "Forgot PIN?") shows its prompt through a FragmentActivity;
// on a plain FlutterActivity it cannot show one and the check fails at once, without a prompt.
class MainActivity : FlutterFragmentActivity()
