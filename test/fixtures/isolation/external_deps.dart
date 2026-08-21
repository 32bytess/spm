import 'package:flutter/material.dart';
import 'deep_deps.dart';

// Direct StatelessWidget child. References DeepWidget (level 2)
class ExternalChild extends StatelessWidget {
  const ExternalChild({super.key});
  @override
  Widget build(BuildContext context) =>
      const Column(children: [Text('External'), DeepWidget()]);
}

// StatefulWidget child. Isolation must include both the widget AND its State
class ExternalStateful extends StatefulWidget {
  const ExternalStateful({super.key});
  @override
  State<ExternalStateful> createState() => _ExternalStatefulState();
}

class _ExternalStatefulState extends State<ExternalStateful> {
  @override
  Widget build(BuildContext context) => const Text('External stateful');
}

// Widget extending a custom base (not directly a Flutter widget type)
class _BaseCard extends StatelessWidget {
  const _BaseCard();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class ExternalCard extends _BaseCard {
  const ExternalCard();
}

// Cross-file helper returning List<Widget>. Should be included
List<Widget> buildExternalItems(BuildContext context) {
  return [const Text('a'), const Text('b')];
}

// CustomPainter subclass. Should be included
class ExternalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(ExternalPainter old) => false;
}

// ShapeBorder subclass. Should be included
class ExternalShape extends ShapeBorder {
  const ExternalShape();
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path();
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
  @override
  ShapeBorder scale(double t) => this;
}

// Function returning Decoration. Should be included
BoxDecoration buildExternalDecoration() =>
    const BoxDecoration(color: Colors.blue);

// Helper constant in another file
const kExternalColor = Colors.red;

// Helper function in another file (should NOT be included)
void externalHelper() {
  print('External helper called');
}

// Not a widget, but hands one out. `tree_extractor` walks the body of every
// widget-returning helper a scope calls, so shimming this away would report
// zero widgets where analyzing the original project counted the divider's
// subtree. It must be inlined whole.
class ExternalStyles {
  static Widget divider() =>
      const SizedBox(height: 1, child: ColoredBox(color: Colors.grey));

  static const double gap = 8;
}

// Produces no UI at all, so a declaration-only stand-in cannot move any count.
class ExternalService {
  final String prefix = 'svc';

  String label(int id) => '$prefix-$id';
}
