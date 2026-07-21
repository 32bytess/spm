import 'package:flutter/material.dart';

// Level-2 widget: referenced only by ExternalChild (in external_deps.dart),
// not directly by the root scope. The recursive traversal must reach it.
class DeepWidget extends StatelessWidget {
  const DeepWidget({super.key});
  @override
  Widget build(BuildContext context) => const Text('deep');
}

// Non-widget at level 2 — should NOT be included even though a widget references it.
class DeepService {
  void doSomething() {}
}
