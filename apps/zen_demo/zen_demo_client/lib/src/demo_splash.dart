import 'package:flutter/material.dart';

/// Shown while the session is being restored, before it is known which side of sign-in to show.
class DemoSplash extends StatelessWidget {
  const DemoSplash({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
